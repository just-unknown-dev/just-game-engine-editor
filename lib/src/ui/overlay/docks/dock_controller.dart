import 'dart:async';
import 'dart:convert';

import 'package:just_signals/just_signals.dart';

import '../../../extension/editor_contributions.dart';

/// The bottom panel's state: which dock is showing, how tall each is, which
/// are pinned as tabs and in what order, and what each remembers.
///
/// One dock shows at a time. Built-in and module docks go through the same
/// controller. The settings dialog is not a dock: it has a gear of its own
/// on the viewport.
///
/// Everything here survives a restart once [attach] has been given somewhere
/// to keep it.
class DockController {
  DockController();

  /// What the settings panel was saved as when it shared the dock slot; a
  /// saved state from then is read as "nothing open".
  static const String _legacySettingsId = 'settings';

  /// The open dock's id, or null when the panel is collapsed.
  final Signal<String?> openId = Signal(null, debugLabel: 'openDock');

  /// Each dock's height once it has been resized. Replaced, never mutated,
  /// so a watcher sees every change.
  final Signal<Map<String, double>> heights = Signal(
    const {},
    debugLabel: 'dockHeights',
  );

  /// The pinned tabs, left to right. Empty until [reconcile] has seen the
  /// docks that exist.
  final Signal<List<String>> order = Signal(const [], debugLabel: 'dockOrder');

  /// The panel fills the viewport instead of sitting at its foot.
  final Signal<bool> maximised = Signal(false, debugLabel: 'dockMaximised');

  /// Docks showing in a dialog of their own rather than in the panel.
  final Signal<Set<String>> poppedOut = Signal(
    const {},
    debugLabel: 'docksPoppedOut',
  );

  /// What the open dock was opened with; cleared when another opens.
  Map<String, Object?> openArgs = const {};

  /// The dock last shown, for "toggle the panel" to come back to.
  String? _lastDock;

  /// Docks the user has unpinned. Kept apart from [order] so a dock that is
  /// new to this project (a module just added) is told from one dismissed.
  final Set<String> _unpinned = {};
  final Map<String, Map<String, Object?>> _memory = {};

  bool isOpen(String id) => openId.value == id;

  /// The dock showing in the panel, or null when it is collapsed.
  String? get activeDock => openId.value;

  /// Opens [id] with [args].
  void open(String id, {Map<String, Object?> args = const {}}) {
    openArgs = args;
    _lastDock = id;
    if (!order.value.contains(id) && !poppedOut.value.contains(id)) pin(id);
    // Same dock, new args: say so, or nobody rebuilds.
    openId.value == id ? openId.forceSet(id) : openId.value = id;
    _save();
  }

  /// Opens [id], or closes it when it is the open one.
  void toggle(String id) => isOpen(id) ? close() : open(id);

  /// Collapses the panel, or brings back the dock last shown.
  void togglePanel({String? fallback}) {
    if (activeDock != null) return close();
    final id =
        _lastDock ?? (order.value.isEmpty ? fallback : order.value.first);
    if (id != null) open(id);
  }

  void close() {
    openId.value = null;
    maximised.value = false;
    _save();
  }

  /// The next (or previous) pinned tab, wrapping.
  void cycle(int delta) {
    final tabs = order.value;
    if (tabs.isEmpty) return;
    final at = tabs.indexOf(activeDock ?? '');
    open(
      tabs[((at < 0 ? 0 : at + delta) % tabs.length + tabs.length) %
          tabs.length],
    );
  }

  // ── Tabs ─────────────────────────────────────────────────────────────────

  /// Brings [order] in line with the [docks] that exist: gone ones leave,
  /// new ones that pin by default join at the end, in their declared order.
  void reconcile(List<DockDefinition> docks) {
    _defaultHeights
      ..clear()
      ..addAll({for (final d in docks) d.id: d.defaultHeight});
    final known = {for (final d in docks) d.id};
    final next = [
      for (final id in order.value)
        if (known.contains(id)) id,
    ];
    for (final d in docks) {
      if (!next.contains(d.id) &&
          d.pinnedByDefault &&
          !_unpinned.contains(d.id)) {
        next.add(d.id);
      }
    }
    if (!_sameList(next, order.value)) order.value = List.unmodifiable(next);
    final open = activeDock;
    if (open != null && !known.contains(open)) openId.value = null;
  }

  void pin(String id, {int? at}) {
    if (order.value.contains(id)) return;
    _unpinned.remove(id);
    final next = List.of(order.value);
    next.insert((at ?? next.length).clamp(0, next.length), id);
    order.value = List.unmodifiable(next);
    _save();
  }

  /// Takes [id] off the tab bar; it stays reachable from the `+` menu.
  void unpin(String id) {
    if (!order.value.contains(id)) return;
    _unpinned.add(id);
    order.value = List.unmodifiable([
      for (final o in order.value)
        if (o != id) o,
    ]);
    if (activeDock == id) {
      order.value.isEmpty ? close() : open(order.value.first);
    }
    _save();
  }

  /// Moves the tab [id] to position [to].
  void move(String id, int to) {
    final next = List.of(order.value);
    final from = next.indexOf(id);
    if (from < 0) return;
    next
      ..removeAt(from)
      ..insert(to.clamp(0, next.length), id);
    order.value = List.unmodifiable(next);
    _save();
  }

  void popOut(String id) {
    poppedOut.value = Set.unmodifiable({...poppedOut.value, id});
    _save();
    if (activeDock == id) {
      final rest = [
        for (final o in order.value)
          if (o != id && !poppedOut.value.contains(o)) o,
      ];
      rest.isEmpty ? close() : open(rest.first);
    }
  }

  void popIn(String id) {
    poppedOut.value = Set.unmodifiable({
      for (final o in poppedOut.value)
        if (o != id) o,
    });
    _save();
    open(id);
  }

  // ── Size ─────────────────────────────────────────────────────────────────

  final Map<String, double> _defaultHeights = {};

  /// Shortest a dock may be dragged.
  static const double minHeight = 180;

  /// How tall the panel is right now, given [available] room above the
  /// status strip: nothing when collapsed, all of it when maximised.
  double panelHeight(double available) {
    final id = activeDock;
    if (id == null) return 0;
    final room = available < minHeight ? minHeight : available;
    if (maximised.value) return room;
    return heightOf(
      id,
      fallback: _defaultHeights[id] ?? 280,
    ).clamp(minHeight, room).toDouble();
  }

  double heightOf(String id, {required double fallback}) =>
      heights.value[id] ?? fallback;

  /// Drags the top edge of [id] by [dy] screen pixels (up is negative).
  void resize(
    String id,
    double dy, {
    required double fallback,
    double min = 180,
    required double max,
  }) {
    heights.value = Map.unmodifiable({
      ...heights.value,
      id: (heightOf(id, fallback: fallback) - dy).clamp(min, max),
    });
    _save();
  }

  /// Forgets a resize, so the dock is its declared height again.
  void resetHeight(String id) {
    heights.value = Map.unmodifiable({
      for (final e in heights.value.entries)
        if (e.key != id) e.key: e.value,
    });
    _save();
  }

  // ── Memory ───────────────────────────────────────────────────────────────

  /// What the dock [id] remembers.
  DockMemory memoryOf(String id) => _Memory(this, id);

  // ── Persistence ──────────────────────────────────────────────────────────

  void Function(String json)? _store;
  Timer? _saveTimer;

  /// Restores from [saved] (what an earlier [toJson] produced; anything else
  /// is ignored) and from then on hands changes to [store], debounced.
  void attach({required String saved, required void Function(String) store}) {
    restore(saved);
    _store = store;
  }

  void restore(String saved) {
    if (saved.isEmpty) return;
    try {
      final json = jsonDecode(saved);
      if (json is! Map) return;
      List<String> strings(Object? v) => [
        if (v is List)
          for (final x in v)
            if (x is String) x,
      ];
      order.value = List.unmodifiable(strings(json['order']));
      // A dock left in a window of its own opens in it again.
      poppedOut.value = Set.unmodifiable(strings(json['popped']).toSet());
      _unpinned
        ..clear()
        ..addAll(strings(json['unpinned']));
      final h = json['heights'];
      if (h is Map) {
        heights.value = Map.unmodifiable({
          for (final e in h.entries)
            if (e.value is num) '${e.key}': (e.value as num).toDouble(),
        });
      }
      final m = json['memory'];
      if (m is Map) {
        _memory
          ..clear()
          ..addAll({
            for (final e in m.entries)
              if (e.value is Map)
                '${e.key}': (e.value as Map).cast<String, Object?>(),
          });
      }
      final open = json['open'];
      // The panel starts collapsed, however it was left: the editor opens
      // on the level, its panels and the status strip, and the docks are
      // there when they are asked for. Which dock it was is remembered,
      // so F2 brings that one straight back.
      _lastDock =
          json['last'] as String? ??
          (open is String && open != _legacySettingsId ? open : null);
    } catch (_) {
      // A damaged preference is not worth failing the editor over.
    }
  }

  String toJson() => jsonEncode({
    'open': activeDock,
    'last': _lastDock,
    'order': order.value,
    'popped': poppedOut.value.toList(),
    'unpinned': _unpinned.toList(),
    'heights': heights.value,
    'memory': _memory,
  });

  void _save() {
    final store = _store;
    if (store == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 400),
      () => store(toJson()),
    );
  }

  /// Writes now, if anything is waiting to be written.
  void flush() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _store?.call(toJson());
    }
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void dispose() {
    flush();
    _saveTimer?.cancel();
    openId.dispose();
    heights.dispose();
    order.dispose();
    maximised.dispose();
    poppedOut.dispose();
  }
}

class _Memory implements DockMemory {
  _Memory(this._controller, this._id);

  final DockController _controller;
  final String _id;

  @override
  T? read<T>(String key) {
    final value = _controller._memory[_id]?[key];
    if (value is T) return value;
    // JSON has one number type; a dock asking for a double gets one.
    if (T == double && value is num) return value.toDouble() as T;
    return null;
  }

  @override
  void write(String key, Object? value) {
    final bag = _controller._memory.putIfAbsent(_id, () => {});
    if (value == null ? !bag.containsKey(key) : bag[key] == value) return;
    value == null ? bag.remove(key) : bag[key] = value;
    _controller._save();
  }
}
