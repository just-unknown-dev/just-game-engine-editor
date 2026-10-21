import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:just_editor_core/host.dart';
import 'package:just_editor_core/io.dart' show FileSystemException;
import '../../core/prefs/recent_scenes.dart';
import '../../core/serialization/scene_manager.dart';
import '../dialogs/create_scene_overlay.dart';
import '../dialogs/scene_actions_dialogs.dart';
import 'scene_row.dart';

/// How the Scenes list is ordered.
enum SceneSort {
  /// The game's own order — `scenes.json` — the first being where it
  /// starts; rows can be dragged to change it.
  playOrder('Play order', 'Play order'),

  /// A to Z.
  name('Name', 'A–Z'),

  /// The scenes opened lately first, then the rest A to Z.
  recent('Recently opened', 'Recently opened');

  const SceneSort(this.label, this.caption);

  /// In the sort menu.
  final String label;

  /// Over the list.
  final String caption;

  static SceneSort fromName(String name) =>
      values.firstWhere((s) => s.name == name, orElse: () => playOrder);
}

enum _RowAction {
  open,
  rename,
  duplicate,
  makeStart,
  moveUp,
  moveDown,
  addToGame,
  leaveOut,
  delete,
}

/// Shown in the right panel while no scene is open: every scene in
/// `assets/scenes/`, to open, make, and look after.
///
/// - A search over the names; Enter opens the first match.
/// - Sorted by play order (the default), name, or the ones opened lately;
///   the last few opened stand at the top, under Recent.
/// - Each row says where it is in the play order, which one the game starts
///   with, whether it is 2D or 3D, how much is in it and when it was saved.
/// - In play order the rows can be dragged — or moved with Alt+↑ and Alt+↓ —
///   and that is the order `scenes.json` is written in: the order the game
///   plays them.
/// - Keys, with the list focused: ↑ ↓ Home End move, Enter opens, F2
///   renames, Ctrl+D duplicates, Delete deletes, Esc clears the search, and
///   typing searches.
/// - Right-click or ⋮ for the rest; New scene opens a dialog.
class ScenePickerPanel extends StatefulWidget {
  const ScenePickerPanel({
    super.key,
    required this.onSceneSelected,
    required this.sceneManager,
    this.prefs,
    this.now,
  });

  /// Called when the user opens an existing scene **or** successfully creates
  /// a new one.
  final Future<void> Function(String sceneName) onSceneSelected;

  final SceneManager sceneManager;

  /// Where the recent scenes and the sort are kept; without it, neither is
  /// remembered.
  final EditorPrefs? prefs;

  /// The clock saved times are read against; now when null. For tests.
  final DateTime? now;

  /// How the list was last sorted.
  static final SettingPref<String> sortPref = SettingPref.text(
    OverlaySettingsPrefKeys.scenesSort,
    SceneSort.playOrder.name,
  );

  /// How many recent scenes stand at the top.
  static const int recentShown = 3;

  @override
  State<ScenePickerPanel> createState() => _ScenePickerPanelState();
}

class _ScenePickerPanelState extends State<ScenePickerPanel> {
  /// Every scene: the play order, then any the game does not list.
  List<String> _all = [];

  /// The game's play order.
  List<String> _order = [];

  Map<String, SceneSummary> _summaries = {};
  List<String> _recent = [];
  SceneSort _sort = SceneSort.playOrder;
  String _query = '';
  String? _cursor;
  String? _actionError;

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'scenes.search');
  final FocusNode _listFocus = FocusNode(debugLabel: 'scenes.list');
  final Map<String, GlobalKey> _rowKeys = {};

  ValueListenable<String>? _sortPref;
  ValueListenable<String>? _recentPref;

  SceneManager get _manager => widget.sceneManager;

  @override
  void initState() {
    super.initState();
    final prefs = widget.prefs;
    if (prefs != null) {
      _sort = SceneSort.fromName(prefs.get(ScenePickerPanel.sortPref));
      _sortPref = prefs.watch(ScenePickerPanel.sortPref)
        ..addListener(_onSortPref);
      _recentPref = RecentScenes.watch(prefs)..addListener(_onRecentPref);
    }
    _listFocus.addListener(_onFocus);
    _searchFocus.addListener(_onFocus);
    _refreshScenes();
  }

  @override
  void dispose() {
    _forgetDeleted?.cancel();
    _sortPref?.removeListener(_onSortPref);
    _recentPref?.removeListener(_onRecentPref);
    _search.dispose();
    _searchFocus.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  void _onSortPref() {
    final sort = SceneSort.fromName(_sortPref!.value);
    if (mounted && sort != _sort) setState(() => _sort = sort);
  }

  void _onRecentPref() {
    if (mounted) setState(_readRecent);
  }

  void _readRecent() {
    final prefs = widget.prefs;
    _recent = prefs == null ? [] : RecentScenes.of(prefs, existing: _all);
  }

  void _refreshScenes() {
    List<String> all;
    List<String> order;
    try {
      all = _manager.store.listSceneNames();
      order = _manager.playOrder();
    } on FileSystemException {
      all = [];
      order = [];
    }
    final summaries = <String, SceneSummary>{};
    for (final name in all) {
      // Read once and remembered until the file changes; a file that is
      // not a scene is summed up as unreadable, and one gone between the
      // listing and the read is null: the next refresh drops it.
      final summary = _manager.summaryOf(name);
      if (summary != null) summaries[name] = summary;
    }
    setState(() {
      _all = all;
      _order = order;
      _summaries = summaries;
      _readRecent();
      if (_cursor != null && !all.contains(_cursor)) _cursor = null;
      _rowKeys.removeWhere((name, _) => !all.contains(name));
    });
  }

  // ── What is shown ─────────────────────────────────────────────────────

  List<String> get _sorted => switch (_sort) {
    SceneSort.playOrder => _all,
    SceneSort.name => [..._all]..sort(_byName),
    SceneSort.recent => [
      ..._recent,
      ...[..._all.where((n) => !_recent.contains(n))]..sort(_byName),
    ],
  };

  static int _byName(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  List<String> get _shown {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _sorted;
    return _sorted.where((n) => n.toLowerCase().contains(query)).toList();
  }

  bool get _canReorder => _sort == SceneSort.playOrder && _query.isEmpty;

  List<String> get _recentGroup => _query.isEmpty && _sort != SceneSort.recent
      ? _recent.take(ScenePickerPanel.recentShown).toList()
      : const [];

  /// The row lit: the keys' row while the list has the focus; while
  /// searching, the one Enter would open.
  String? _litIn(List<String> shown) {
    if (_listFocus.hasFocus) return _cursor;
    if (_searchFocus.hasFocus && _query.isNotEmpty && shown.isNotEmpty) {
      return shown.contains(_cursor) ? _cursor : shown.first;
    }
    return null;
  }

  GlobalKey _keyFor(String name) =>
      _rowKeys.putIfAbsent(name, () => GlobalKey(debugLabel: 'scene:$name'));

  void _setCursor(String? name) {
    setState(() => _cursor = name);
    if (name == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _rowKeys[name]?.currentContext;
      if (context != null && context.mounted) {
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
        if (!context.mounted) return;
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    });
  }

  void _setQuery(String query) {
    setState(() {
      _query = query;
      final shown = _shown;
      if (_cursor != null && !shown.contains(_cursor)) {
        _cursor = shown.isEmpty ? null : shown.first;
      }
    });
  }

  void _clearSearch() {
    _search.clear();
    _setQuery('');
  }

  Future<void> _setSort(SceneSort sort) async {
    setState(() => _sort = sort);
    final prefs = widget.prefs;
    if (prefs != null) await prefs.set(ScenePickerPanel.sortPref, sort.name);
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _open(String name) => widget.onSceneSelected(name);

  Future<void> _newScene() async {
    setState(() => _actionError = null);
    final name = await showNewSceneDialog(context, store: _manager.store);
    if (name == null || !mounted) return;
    _refreshScenes();
    await widget.onSceneSelected(name);
  }

  /// Runs [action], showing what went wrong in the banner. A refused or
  /// failed action reads the list again: what it acted on may have changed
  /// on disk.
  Future<bool> _attempt(Future<void> Function() action) async {
    setState(() => _actionError = null);
    String? problem;
    try {
      await action();
      return true;
    } on SceneManagerException catch (e) {
      problem = e.message;
    } on FileSystemException catch (e) {
      problem = e.path == null ? e.message : '${e.message}: ${e.path}';
    } on Exception catch (e) {
      // An unreadable scenes.json, say: said, not thrown into the frame.
      problem = '$e';
    }
    if (mounted) {
      _refreshScenes();
      setState(() => _actionError = problem);
    }
    return false;
  }

  Future<void> _onRename(String name) async {
    if (_manager.isProtected(name)) return;
    setState(() => _actionError = null);
    final newName = await promptSceneName(
      context,
      title: 'Rename "$name"',
      actionLabel: 'Rename',
      initialValue: name,
      // Its own name is free, in other letter case too: `level_01` can
      // become `Level_01`. Every other scene's name is taken.
      validate: (value) => _manager.validateName(value, ignoring: name),
    );
    if (newName == null || newName == name || !mounted) return;
    final done = await _attempt(() => _manager.renameScene(name, newName));
    if (!done || !mounted) return;
    final prefs = widget.prefs;
    if (prefs != null) await RecentScenes.rename(prefs, name, newName);
    if (!mounted) return;
    _refreshScenes();
    _setCursor(newName);
    await _offerToRepoint(name, newName);
  }

  /// After [from] became [to]: the other scenes that still name [from] —
  /// a goal's next scene — are offered to be pointed at [to] too.
  Future<void> _offerToRepoint(String from, String to) async {
    final Map<String, int> mentions;
    try {
      mentions = await _manager.mentionsOf(from, except: to);
    } on FileSystemException {
      return;
    }
    if (mentions.isEmpty || !mounted) return;
    final where = [
      for (final MapEntry(key: scene, value: count) in mentions.entries)
        '  • $scene ($count)',
    ].join('\n');
    final go = await showEditorConfirm(
      context,
      title: 'Point other scenes at "$to"?',
      message:
          'These scenes still name "$from" — as a goal\'s next scene, say — '
          'and would look for a scene that is not there:\n$where\n\n'
          'Each place that is exactly "$from" becomes "$to".',
      confirmLabel: 'Update them',
      danger: false,
    );
    if (!go || !mounted) return;
    await _attempt(() => _manager.rewriteMentions(from, to, mentions.keys));
    if (mounted) _refreshScenes();
  }

  Future<void> _onDuplicate(String name) async {
    setState(() => _actionError = null);
    final newName = await promptSceneName(
      context,
      title: 'Duplicate "$name"',
      actionLabel: 'Duplicate',
      initialValue: _copyName(name),
      // A copy needs a name of its own: the source's, in any letter case,
      // is taken too.
      validate: _manager.validateName,
    );
    if (newName == null || !mounted) return;
    final done = await _attempt(() => _manager.duplicateScene(name, newName));
    if (!done || !mounted) return;
    _refreshScenes();
    _setCursor(newName);
  }

  /// `level_02_copy`, or `level_02_copy_2` when that is taken.
  String _copyName(String name) {
    final taken = {for (final n in _all) n.toLowerCase()};
    var candidate = '${name}_copy';
    for (var i = 2; taken.contains(candidate.toLowerCase()); i++) {
      candidate = '${name}_copy_$i';
    }
    return candidate;
  }

  Future<void> _onDelete(String name) async {
    if (_manager.isProtected(name)) return;
    setState(() => _actionError = null);
    final confirmed = await confirmDeleteScene(context, name);
    if (!confirmed || !mounted) return;
    // The cursor goes to a neighbour, not back to the top.
    final shown = _shown;
    final at = shown.indexOf(name);
    final neighbour = at < 0
        ? null
        : at + 1 < shown.length
        ? shown[at + 1]
        : at > 0
        ? shown[at - 1]
        : null;
    DeletedScene? deleted;
    final done = await _attempt(
      () async => deleted = await _manager.deleteScene(name),
    );
    if (!done || !mounted) return;
    final prefs = widget.prefs;
    if (prefs != null) await RecentScenes.forget(prefs, name);
    if (!mounted) return;
    _refreshScenes();
    if (_cursor == name || _cursor == null) _setCursor(neighbour);
    _offerUndo(deleted);
  }

  /// The scene deleted last, while it can still be brought back from here.
  DeletedScene? _deleted;
  Timer? _forgetDeleted;

  /// How long the Undo stays offered.
  static const Duration _undoFor = Duration(seconds: 12);

  void _offerUndo(DeletedScene? deleted) {
    _forgetDeleted?.cancel();
    _forgetDeleted = deleted == null
        ? null
        : Timer(_undoFor, () {
            if (mounted) setState(() => _deleted = null);
          });
    setState(() => _deleted = deleted);
  }

  Future<void> _undoDelete() async {
    final deleted = _deleted;
    if (deleted == null) return;
    _forgetDeleted?.cancel();
    setState(() => _deleted = null);
    final done = await _attempt(deleted.restore);
    if (!done || !mounted) return;
    _refreshScenes();
    _setCursor(deleted.name);
  }

  /// Writes [order] as the play order — straight away on screen, then to
  /// `scenes.json`.
  Future<void> _writeOrder(List<String> order) async {
    final listed = order.toSet();
    setState(() {
      _order = order;
      _all = [...order, ..._all.where((n) => !listed.contains(n))];
    });
    await _attempt(() => _manager.setPlayOrder(order));
    if (mounted) _refreshScenes();
  }

  Future<void> _move(String name, int by) async {
    final at = _order.indexOf(name);
    if (at < 0) return;
    final to = (at + by).clamp(0, _order.length - 1);
    if (to == at) return;
    final order = [..._order]
      ..removeAt(at)
      ..insert(to, name);
    await _writeOrder(order);
    _setCursor(name);
  }

  Future<void> _makeStart(String name) =>
      _writeOrder([name, ..._order.where((n) => n != name)]);

  Future<void> _addToGame(String name) =>
      _writeOrder([..._order.where((n) => n != name), name]);

  Future<void> _leaveOut(String name) =>
      _writeOrder(_order.where((n) => n != name).toList());

  /// A row dragged from [from] to [to] in the play-order list — [to] as
  /// it is once the row has left [from].
  Future<void> _onReorder(int from, int to) async {
    final rows = [..._all];
    final moved = rows.removeAt(from);
    rows.insert(to, moved);
    // Dragging a scene the game does not list puts it in the play order;
    // the others stay out.
    final listed = {..._order, moved};
    await _writeOrder(rows.where(listed.contains).toList());
    _setCursor(moved);
  }

  Future<void> _showMenu(String name, Offset at) async {
    setState(() => _cursor = name);
    final place = _order.indexOf(name);
    final guarded = _manager.isProtected(name);
    final action = await showEditorMenu<_RowAction>(context, at, [
      editorMenuItem(
        _RowAction.open,
        'Open',
        icon: Icons.open_in_new_rounded,
        shortcut: 'Enter',
      ),
      editorMenuItem(
        _RowAction.rename,
        guarded ? 'Rename (the game uses it)' : 'Rename…',
        icon: Icons.drive_file_rename_outline,
        shortcut: 'F2',
        enabled: !guarded,
      ),
      editorMenuItem(
        _RowAction.duplicate,
        'Duplicate…',
        icon: Icons.copy_outlined,
        shortcut: EditorKeys.withPrimary('D'),
      ),
      editorMenuDivider(),
      if (place >= 0) ...[
        editorMenuItem(
          _RowAction.makeStart,
          place == 0 ? 'The game starts here' : 'Start the game here',
          icon: Icons.flag_outlined,
          enabled: place > 0,
        ),
        editorMenuItem(
          _RowAction.moveUp,
          'Earlier in the play order',
          icon: Icons.arrow_upward_rounded,
          shortcut: 'Alt+↑',
          enabled: place > 0,
        ),
        editorMenuItem(
          _RowAction.moveDown,
          'Later in the play order',
          icon: Icons.arrow_downward_rounded,
          shortcut: 'Alt+↓',
          enabled: place < _order.length - 1,
        ),
        editorMenuItem(
          _RowAction.leaveOut,
          'Leave out of the game',
          icon: Icons.playlist_remove_rounded,
          enabled: !guarded,
        ),
      ] else
        editorMenuItem(
          _RowAction.addToGame,
          'Add to the play order',
          icon: Icons.playlist_add_rounded,
        ),
      editorMenuDivider(),
      editorMenuItem(
        _RowAction.delete,
        guarded ? 'Delete (the game uses it)' : 'Delete…',
        icon: Icons.delete_outline,
        color: EditorTheme.error,
        shortcut: 'Del',
        enabled: !guarded,
      ),
    ]);
    if (action == null || !mounted) return;
    switch (action) {
      case _RowAction.open:
        await _open(name);
      case _RowAction.rename:
        await _onRename(name);
      case _RowAction.duplicate:
        await _onDuplicate(name);
      case _RowAction.makeStart:
        await _makeStart(name);
      case _RowAction.moveUp:
        await _move(name, -1);
      case _RowAction.moveDown:
        await _move(name, 1);
      case _RowAction.addToGame:
        await _addToGame(name);
      case _RowAction.leaveOut:
        await _leaveOut(name);
      case _RowAction.delete:
        await _onDelete(name);
    }
  }

  Future<void> _showSortMenu(Offset at) async {
    final sort = await showEditorMenu<SceneSort>(context, at, [
      editorMenuHeading('Sort by'),
      for (final s in SceneSort.values)
        editorMenuItem(
          s,
          s.label,
          icon: s == _sort ? Icons.check_rounded : null,
          iconSlot: true,
        ),
    ]);
    if (sort != null && mounted) await _setSort(sort);
  }

  // ── Keys ──────────────────────────────────────────────────────────────

  static final Set<LogicalKeyboardKey> _listKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.delete,
    LogicalKeyboardKey.escape,
  };

  /// Ctrl held — Cmd on macOS, where Ctrl is not a shortcut key.
  static bool get _ctrl => EditorKeys.primaryPressed;

  /// A character typed into the list, for the search; null for anything
  /// else.
  static String? _typed(KeyEvent event) {
    if (_ctrl ||
        HardwareKeyboard.instance.isAltPressed ||
        EditorKeys.otherPressed) {
      return null;
    }
    final c = event.character;
    if (c == null || c.length != 1 || c.trim().isEmpty) return null;
    return c.codeUnitAt(0) < 0x20 || c.codeUnitAt(0) == 0x7f ? null : c;
  }

  /// The keys the list keeps from the editor's shortcuts while it has the
  /// focus — Ctrl+S and the rest still reach the editor. A Mac's Backspace
  /// deletes, as Delete does.
  bool _claims(KeyEvent event) {
    if (_ctrl) return event.logicalKey == LogicalKeyboardKey.keyD;
    return _listKeys.contains(event.logicalKey) ||
        EditorKeys.isDeleteKey(event.logicalKey) ||
        _typed(event) != null;
  }

  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final shown = _shown;
    final at = _cursor == null ? -1 : shown.indexOf(_cursor!);
    final alt = HardwareKeyboard.instance.isAltPressed;
    final page = math.max(1, (context.size?.height ?? 400) ~/ 48 - 2);

    void go(int index) {
      if (shown.isEmpty) return;
      _setCursor(shown[index.clamp(0, shown.length - 1)]);
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (alt) {
        if (_canReorder && _cursor != null) _move(_cursor!, 1);
      } else {
        go(at + 1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (alt) {
        if (_canReorder && _cursor != null) _move(_cursor!, -1);
      } else if (at <= 0) {
        // Off the top: back to the search.
        _searchFocus.requestFocus();
      } else {
        go(at - 1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      go(at + page);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      go(math.max(0, at - page));
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.home) {
      go(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      go(shown.length - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_query.isNotEmpty) {
        _clearSearch();
      } else {
        setState(() => _cursor = null);
      }
      return KeyEventResult.handled;
    }
    final cursor = _cursor;
    if (cursor != null && shown.contains(cursor)) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _open(cursor);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.f2) {
        _onRename(cursor);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyD && _ctrl) {
        _onDuplicate(cursor);
        return KeyEventResult.handled;
      }
      if (EditorKeys.isDeleteKey(key)) {
        _onDelete(cursor);
        return KeyEventResult.handled;
      }
    }
    final typed = _typed(event);
    if (typed != null) {
      // Typing in the list searches.
      final text = _search.text + typed;
      _search.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _setQuery(text);
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return _listKeys.contains(key)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final shown = _shown;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && shown.isNotEmpty) {
      _listFocus.requestFocus();
      _setCursor(_litIn(shown) ?? shown.first);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _query.isNotEmpty) {
      _clearSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onSearchSubmitted(String _) {
    final lit = _litIn(_shown) ?? (_shown.isEmpty ? null : _shown.first);
    if (lit != null) _open(lit);
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final lit = _litIn(shown);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _toolbar(),
        if (_actionError != null)
          _ActionErrorBanner(
            message: _actionError!,
            onDismiss: () => setState(() => _actionError = null),
          ),
        if (_deleted case final deleted?)
          _DeletedBanner(
            name: deleted.name,
            onUndo: _undoDelete,
            onDismiss: () => _offerUndo(null),
          ),
        Expanded(
          child: _all.isEmpty
              ? EditorEmptyState(
                  icon: Icons.map_outlined,
                  title: 'No scenes yet',
                  hint:
                      'A scene is one level of the game, saved in '
                      'assets/scenes/. Make the first one here.',
                  actionLabel: 'New scene',
                  onAction: _newScene,
                )
              : shown.isEmpty
              ? EditorEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No scene matches "${_query.trim()}"',
                  actionLabel: 'Clear the search',
                  actionIcon: Icons.close_rounded,
                  onAction: _clearSearch,
                )
              : _list(shown, lit),
        ),
        if (_all.isNotEmpty) _footer(),
      ],
    );
  }

  Widget _toolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
    child: Row(
      children: [
        Expanded(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onSearchKey,
            child: EditorSearchField(
              controller: _search,
              focusNode: _searchFocus,
              width: null,
              hint: 'Search scenes',
              onChanged: _setQuery,
              onSubmitted: _onSearchSubmitted,
            ),
          ),
        ),
        const SizedBox(width: 2),
        Builder(
          builder: (context) => EditorIconButton(
            icon: Icons.sort_rounded,
            tooltip: 'Sort: ${_sort.label}',
            isActive: _sort != SceneSort.playOrder,
            onTap: () {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              _showSortMenu(
                box.localToGlobal(box.size.bottomLeft(Offset.zero)),
              );
            },
          ),
        ),
        EditorIconButton(
          icon: Icons.add_rounded,
          tooltip: 'New scene',
          color: EditorTheme.accent,
          onTap: _newScene,
        ),
      ],
    ),
  );

  Widget _list(List<String> shown, String? lit) {
    final recent = _recentGroup;
    final start = _order.isEmpty ? null : _order.first;
    final canReorder = _canReorder;
    final now = widget.now;

    SceneRow row(String name, {int? dragIndex, bool compact = false}) =>
        SceneRow(
          key: compact ? ValueKey('recent:$name') : _keyFor(name),
          name: name,
          summary: _summaries[name],
          playIndex: _order.contains(name) ? _order.indexOf(name) : null,
          isStart: name == start,
          isProtected: _manager.isProtected(name),
          isCursor: !compact && name == lit,
          query: _query,
          dragIndex: dragIndex,
          showPlace: _sort == SceneSort.playOrder,
          compact: compact,
          now: now,
          onOpen: () {
            setState(() => _cursor = name);
            _open(name);
          },
          onMenu: (at) => _showMenu(name, at),
        );

    final count = _query.isEmpty
        ? '${_all.length}'
        : '${shown.length} of ${_all.length}';
    return EditorKeyClaim(
      claims: _claims,
      child: Focus(
        focusNode: _listFocus,
        onKeyEvent: _onListKey,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (_) => _listFocus.requestFocus(),
          child: CustomScrollView(
            slivers: [
              if (recent.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: EditorSectionHeader(
                    'Recent',
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
                  ),
                ),
                SliverList.list(
                  children: [for (final n in recent) row(n, compact: true)],
                ),
              ],
              SliverToBoxAdapter(
                child: EditorSectionHeader(
                  _sort.caption,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  trailing: Text(
                    count,
                    style: TextStyle(
                      color: EditorTheme.textMuted,
                      fontSize: EditorMetrics.fontCaption,
                    ),
                  ),
                ),
              ),
              if (canReorder)
                SliverReorderableList(
                  itemCount: shown.length,
                  onReorderItem: _onReorder,
                  proxyDecorator: (child, _, _) => Material(
                    color: EditorTheme.panelRaised,
                    elevation: 6,
                    shadowColor: Colors.black54,
                    child: child,
                  ),
                  itemBuilder: (context, i) => row(shown[i], dragIndex: i),
                )
              else
                SliverList.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) => row(shown[i]),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer() => Container(
    padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: EditorTheme.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _query.isNotEmpty
                ? 'Enter opens the lit scene · Esc clears'
                : _canReorder
                ? 'Drag a number to reorder · the game starts at 1'
                : 'Sort by play order to reorder',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: EditorTheme.textMuted, fontSize: 10.5),
          ),
        ),
        Tooltip(
          message: _keysHelp,
          child: Icon(
            Icons.keyboard_outlined,
            size: 14,
            color: EditorTheme.textMuted,
            semanticLabel: _keysHelp,
          ),
        ),
      ],
    ),
  );

  static String get _keysHelp =>
      'With the list focused:\n'
      '↑ ↓  Home  End — move\n'
      'Enter — open\n'
      'F2 — rename\n'
      '${EditorKeys.withPrimary('D')} — duplicate\n'
      '${EditorKeys.isMac ? 'Delete or Backspace' : 'Delete'} — delete\n'
      'Alt+↑ ↓ — earlier or later in the play order\n'
      'Type — search';
}

/// A scene just deleted: where it went, and the way back.
class _DeletedBanner extends StatelessWidget {
  const _DeletedBanner({
    required this.name,
    required this.onUndo,
    required this.onDismiss,
  });

  final String name;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EditorTheme.panelRaised,
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.delete_outline, size: 14, color: EditorTheme.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Deleted "$name": it is in ${AssetIndex.trashFolder}/',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
            ),
          ),
          EditorButton(
            label: 'Undo',
            kind: EditorButtonKind.ghost,
            onPressed: onUndo,
          ),
          EditorIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Dismiss',
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _ActionErrorBanner extends StatelessWidget {
  const _ActionErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EditorTheme.error.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 14, color: EditorTheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: EditorTheme.errorLight, fontSize: 11),
            ),
          ),
          EditorIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Dismiss',
            color: EditorTheme.errorLight,
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}
