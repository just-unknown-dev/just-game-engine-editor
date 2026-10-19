import 'dart:async';
import 'dart:convert';

import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';

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
  Map<String, Object?> get openArgs => _openArgs;
  Map<String, Object?> _openArgs = const {};

  /// The dock last shown, for "toggle the panel" to come back to.
  String? _lastDock;

  /// Docks the user has unpinned. Kept apart from [order] so a dock that is
  /// new to this project (a module just added) is told from one dismissed.
  final Set<String> _unpinned = {};
  final Map<String, Map<String, Object?>> _memory = {};

  bool isOpen(String id) => openId.value == id;

  /// The dock showing in the panel, or null when it is collapsed.
  String? get activeDock => openId.value;

  /// Opens [id] with [args]. A dock popped out into a window of its own
  /// stays there, brought in front of the other windows: it is never built
  /// in the panel and the window at once.
  void open(String id, {Map<String, Object?> args = const {}}) {
    if (poppedOut.value.contains(id)) {
      poppedOut.value = Set.unmodifiable({
        for (final o in poppedOut.value)
          if (o != id) o,
        id,
      });
      return;
    }
    // A copy each time: a dock opened again with the same args — a click on
    // the same readout — is told so, and takes them again.
    _openArgs = Map.unmodifiable({...args});
    _lastDock = id;
    if (!order.value.contains(id) && !poppedOut.value.contains(id)) pin(id);
    // Same dock, new args: say so, or nobody rebuilds.
    openId.value == id ? openId.forceSet(id) : openId.value = id;
    _save();
  }

  /// Opens [id], or closes it when it is the open one.
  void toggle(String id) => isOpen(id) ? close() : open(id);

  /// Collapses the panel, or brings back the dock last shown — or, when
  /// that one is in a window of its own now, the first tab that is not.
  void togglePanel({String? fallback}) {
    if (activeDock != null) return close();
    // The dock last shown — unless it is gone (a module taken out): then
    // the first one there is.
    final last = _lastDock;
    final id =
        last != null &&
            order.value.contains(last) &&
            !poppedOut.value.contains(last)
        ? last
        : _firstInPanel ?? fallback;
    if (id != null && !poppedOut.value.contains(id)) open(id);
  }

  /// The first tab that shows in the panel, not in a window.
  String? get _firstInPanel {
    for (final id in order.value) {
      if (!poppedOut.value.contains(id)) return id;
    }
    return null;
  }

  void close() {
    openId.value = null;
    maximised.value = false;
    _save();
  }

  /// The next (or previous) pinned tab in the panel, wrapping.
  void cycle(int delta) {
    final tabs = [
      for (final id in order.value)
        if (!poppedOut.value.contains(id)) id,
    ];
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
      final next = _firstInPanel;
      next == null ? close() : open(next);
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
      _lastDock = json['last'] as String? ?? (open is String ? open : null);
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
