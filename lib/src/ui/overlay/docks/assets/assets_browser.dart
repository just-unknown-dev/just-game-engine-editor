import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../../core/constants/editor_constants.dart';
import '../../../../ui/widgets/editor_menu.dart';
import '../../../../core/scope/editor_scope.dart';
import '../../../../extension/editor_contributions.dart';
import '../shared/dock_widgets.dart';
import 'asset_index.dart';

IconData assetIcon(AssetKind kind) => switch (kind) {
  AssetKind.folder => Icons.folder_rounded,
  AssetKind.image => Icons.image_outlined,
  AssetKind.sprite => Icons.brush_outlined,
  AssetKind.scene => Icons.map_outlined,
  AssetKind.animator => Icons.account_tree_outlined,
  AssetKind.tileset => Icons.grid_view,
  AssetKind.levelMap => Icons.grid_on,
  AssetKind.tiled => Icons.layers_outlined,
  AssetKind.data => Icons.data_object_rounded,
  AssetKind.audio => Icons.graphic_eq_rounded,
  AssetKind.font => Icons.font_download_outlined,
  AssetKind.other => Icons.insert_drive_file_outlined,
};

Color assetColor(AssetKind kind) => switch (kind) {
  AssetKind.folder => const Color(0xFFFFC86B),
  AssetKind.image || AssetKind.sprite => const Color(0xFF7DD8E0),
  AssetKind.scene => const Color(0xFF7DE6B1),
  AssetKind.animator => const Color(0xFFFFCA28),
  AssetKind.tileset || AssetKind.levelMap => const Color(0xFF9CCC65),
  AssetKind.tiled => const Color(0xFF80CBC4),
  AssetKind.audio => const Color(0xFFD9A7FF),
  _ => EditorTheme.textMuted,
};

/// The image that stands for [entry] in the grid: itself for an image, the
/// exported sheet beside a sprite project. Null draws an icon instead.
String? thumbnailOf(AssetIndex index, AssetEntry entry) {
  if (entry.kind == AssetKind.image) return entry.path;
  if (entry.kind == AssetKind.sprite) {
    final dot = entry.path.lastIndexOf('.');
    final sheet = '${entry.path.substring(0, dot)}.png';
    if (index.entryAt(sheet) != null) return sheet;
  }
  if (entry.kind == AssetKind.tileset) return _tilesetImage(index, entry);
  return null;
}

/// A tileset's image, read from its file — remembered until the file
/// changes, as the grid asks on every build.
final Map<String, (DateTime?, String?)> _tilesetImages = {};

String? _tilesetImage(AssetIndex index, AssetEntry entry) {
  final known = _tilesetImages[entry.path];
  if (known != null && known.$1 == entry.modified) return known.$2;
  String? image;
  try {
    final json = jsonDecode(
      File(index.absolute(entry.path)).readAsStringSync(),
    );
    final path = json is Map ? json['image'] : null;
    if (path is String && index.entryAt(path) != null) image = path;
  } catch (_) {
    // Not readable as a tileset: an icon, then.
  }
  _tilesetImages[entry.path] = (entry.modified, image);
  return image;
}

/// The asset browser: folders on the left, what is in the open one in the
/// middle, and the selected file on the right.
class AssetsBrowserDock extends StatefulWidget {
  const AssetsBrowserDock({
    super.key,
    required this.scope,
    required this.dock,
    required this.index,
  });

  final EditorScope scope;
  final DockContext dock;
  final AssetIndex index;

  @override
  State<AssetsBrowserDock> createState() => AssetsBrowserDockState();
}

class AssetsBrowserDockState extends State<AssetsBrowserDock> {
  AssetIndex get _index => widget.index;
  DockMemory? get _memory => widget.dock.memory;

  late String _dir = _memory?.read<String>('dir') ?? _index.folder;
  late bool _grid = _memory?.read<bool>('grid') ?? true;
  late final Set<String> _openFolders = {
    _index.folder,
    ...(_memory?.read<List<Object?>>('open') ?? const []).whereType<String>(),
  };
  String _query = '';
  final Set<AssetKind> _kinds = {};
  String? _selected;

  /// The last delete, while it can still be taken back.
  TrashedAsset? _trashed;
  Timer? _forgetTrashed;

  @override
  void initState() {
    super.initState();
    _index.revision.addListener(_changed);
    _index
      ..scan()
      ..startWatching();
  }

  @override
  void dispose() {
    _index.revision.removeListener(_changed);
    _forgetTrashed?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      // The open folder or the selection may have been renamed away.
      if (_dir != _index.folder && _index.entryAt(_dir) == null) {
        _dir = _index.folder;
      }
      if (_selected != null && _index.entryAt(_selected!) == null) {
        _selected = null;
      }
    });
  }

  void _go(String dir) {
    setState(() {
      _dir = dir;
      _selected = null;
      // Every folder on the way is opened in the tree.
      var at = dir;
      while (at.contains('/')) {
        _openFolders.add(at);
        at = at.substring(0, at.lastIndexOf('/'));
      }
    });
    _memory
      ?..write('dir', _dir)
      ..write('open', _openFolders.toList());
  }

  List<AssetEntry> get _shown {
    if (_query.trim().isEmpty && _kinds.isEmpty) return _index.childrenOf(_dir);
    return _index.search(_query, kinds: _kinds, within: _dir);
  }

  void _log(String message, {bool failed = false}) => widget.scope.log.log(
    message,
    source: 'assets',
    category: 'files',
    level: failed ? DebuggerLogLevel.error : DebuggerLogLevel.info,
  );

  // ── Operations ───────────────────────────────────────────────────────────

  void _open(AssetEntry entry) {
    if (entry.isDirectory) return _go(entry.path);
    // A timeline is edited in the dock beside this one, not in a workspace.
    if (entry.path.toLowerCase().endsWith('.timeline.json')) {
      widget.scope.dockController.open(
        'timeline', // BuiltInDocks.timeline, which imports this file
        args: {'path': entry.path},
      );
      return;
    }
    if (!widget.scope.openInWorkspace(entry.path)) {
      _index.openExternally(entry.path);
    }
  }

  Future<void> _newFolder() async {
    final path = await _index.newFolder(_dir);
    if (mounted) setState(() => _selected = path);
  }

  /// Points what is loaded in the editor at [to] wherever it named [from]:
  /// the files on disk are rewritten separately.
  int _rewriteWorld(String from, String to) {
    final scope = widget.scope;
    var changed = 0;
    for (final entity in scope.world.entities) {
      for (final component in entity.components) {
        final definition = scope.definitions.definitionFor(component);
        if (definition == null) continue;
        for (final field in definition.fields) {
          if (field.kind.id != jge.FieldTypes.assetRef.id) continue;
          if (field.read(component) == from && field.write != null) {
            field.write!(component, to);
            changed++;
          }
        }
      }
    }
    // Tile maps name their tilesets, and tilesets their images, inside
    // themselves rather than in a field.
    changed += scope.mapDocs.renamed(from, to);
    if (changed > 0) {
      scope.sceneState
        ..markDirty()
        ..refresh();
    }
    return changed;
  }

  Future<void> _rename(AssetEntry entry) async {
    final name = await _promptForName(entry.name);
    if (name == null || name == entry.name || !mounted) return;
    final users = entry.isDirectory
        ? const <String>[]
        : await AssetReferences.find(_index, entry.path);
    var update = false;
    if (users.isNotEmpty && mounted) {
      final choice = await _confirm(
        title: 'Rename "${entry.name}"',
        body:
            'It is used by:\n${users.map((u) => '  • $u').join('\n')}\n\n'
            'Update those to the new name?',
        primary: 'Rename and update',
        secondary: 'Rename only',
      );
      if (choice == null) return;
      update = choice;
    }
    try {
      final to = await _index.rename(entry.path, name);
      if (update) {
        final files = await AssetReferences.rewrite(_index, entry.path, to);
        final live = _rewriteWorld(entry.path, to);
        _log(
          'Renamed ${entry.name} → $name; updated ${files.length} files'
          '${live > 0 ? ' and $live components in the open scene' : ''}.',
        );
      }
      if (mounted) setState(() => _selected = to);
    } on FileSystemException catch (e) {
      _log('Could not rename: ${e.message}', failed: true);
    }
  }

  Future<void> _delete(AssetEntry entry) async {
    final users = entry.isDirectory
        ? const <String>[]
        : await AssetReferences.find(_index, entry.path);
    if (!mounted) return;
    if (users.isNotEmpty) {
      final go = await _confirm(
        title: 'Delete "${entry.name}"?',
        body:
            'It is still used by:\n${users.map((u) => '  • $u').join('\n')}\n\n'
            'It goes to ${AssetIndex.trashFolder}/ and can be restored.',
        primary: 'Delete anyway',
      );
      if (go != true) return;
    }
    try {
      final trashed = await _index.trash(entry.path);
      _forgetTrashed?.cancel();
      _forgetTrashed = Timer(const Duration(seconds: 12), () {
        if (mounted) setState(() => _trashed = null);
      });
      if (mounted) setState(() => _trashed = trashed);
    } on FileSystemException catch (e) {
      _log('Could not delete: ${e.message}', failed: true);
    }
  }

  Future<void> _restore() async {
    final trashed = _trashed;
    if (trashed == null) return;
    setState(() => _trashed = null);
    final path = await trashed.restore();
    if (mounted) setState(() => _selected = path);
  }

  Future<void> _showReferences(AssetEntry entry) async {
    final users = await AssetReferences.find(_index, entry.path);
    if (!mounted) return;
    await _confirm(
      title: 'Used by',
      body: users.isEmpty
          ? 'Nothing under ${_index.folder}/ mentions ${entry.name}.'
          : users.map((u) => '• $u').join('\n'),
      primary: 'OK',
      cancellable: false,
    );
  }

  Future<String?> _promptForName(String initial) {
    final dot = initial.lastIndexOf('.');
    final controller = TextEditingController(text: initial)
      // The stem is what gets retyped; the extension rarely is.
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: dot <= 0 ? initial.length : dot,
      );
    return showDialog<String>(
      context: context,
      builder: (context) => EditorLook(
        child: AlertDialog(
          backgroundColor: EditorTheme.dialogBg,
          title: Text(
            'Rename',
            style: TextStyle(color: EditorTheme.textPrimary, fontSize: 13),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: EditorTheme.textPrimary, fontSize: 12),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Rename'),
            ),
          ],
        ),
      ),
    );
  }

  /// True for [primary], false for [secondary], null when cancelled.
  Future<bool?> _confirm({
    required String title,
    required String body,
    required String primary,
    String? secondary,
    bool cancellable = true,
  }) => showDialog<bool>(
    context: context,
    builder: (context) => EditorLook(
      child: AlertDialog(
        backgroundColor: EditorTheme.dialogBg,
        title: Text(
          title,
          style: TextStyle(color: EditorTheme.textPrimary, fontSize: 13),
        ),
        content: SingleChildScrollView(
          child: Text(
            body,
            style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
          ),
        ),
        actions: [
          if (cancellable)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          if (secondary != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(secondary),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(primary),
          ),
        ],
      ),
    ),
  );

  Future<void> _menu(AssetEntry entry, Offset at) async {
    setState(() => _selected = entry.path);
    final actions = [
      for (final a in widget.scope.assetActions)
        if (a.appliesTo(entry.path, isDirectory: entry.isDirectory)) a,
    ];
    PopupMenuItem<VoidCallback> item(
      String label,
      IconData icon,
      VoidCallback run, {
      Color? color,
    }) => editorMenuItem<VoidCallback>(run, label, icon: icon, color: color);
    final run = await showEditorMenu<VoidCallback>(context, at, [
      item('Open', Icons.open_in_new_rounded, () => _open(entry)),
      for (final a in actions)
        item(a.label, a.icon, () => a.run(widget.scope, entry.path)),
      editorMenuDivider(),
      item('Rename…', Icons.drive_file_rename_outline, () => _rename(entry)),
      if (!entry.isDirectory)
        item(
          'Duplicate',
          Icons.copy_rounded,
          () => _index.duplicate(entry.path),
        ),
      if (!entry.isDirectory)
        item(
          'Find references',
          Icons.travel_explore_rounded,
          () => _showReferences(entry),
        ),
      item(
        'Reveal in file manager',
        Icons.folder_open_rounded,
        () => _index.reveal(entry.path),
      ),
      if (!entry.isDirectory)
        item(
          'Open with the default app',
          Icons.launch_rounded,
          () => _index.openExternally(entry.path),
        ),
      editorMenuDivider(),
      item(
        'Delete',
        Icons.delete_outline_rounded,
        () => _delete(entry),
        color: EditorTheme.error,
      ),
    ]);
    run?.call();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final selected = _selected == null ? null : _index.entryAt(_selected!);
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 190, child: _tree()),
              VerticalDivider(width: 1, color: EditorTheme.border),
              Expanded(
                child: Column(
                  children: [
                    _toolbar(),
                    Expanded(
                      child: shown.isEmpty
                          ? EditorEmptyState(
                              icon: Icons.folder_off_outlined,
                              title: _query.isEmpty && _kinds.isEmpty
                                  ? 'This folder is empty'
                                  : 'Nothing matches',
                              hint: _query.isEmpty && _kinds.isEmpty
                                  ? 'Files saved or dropped here show up by '
                                        'themselves.'
                                  : null,
                            )
                          : _grid
                          ? _gridView(shown)
                          : _listView(shown),
                    ),
                  ],
                ),
              ),
              if (selected != null && !selected.isDirectory) ...[
                VerticalDivider(width: 1, color: EditorTheme.border),
                SizedBox(width: 230, child: _preview(selected)),
              ],
            ],
          ),
        ),
        if (_trashed case final trashed?)
          Container(
            height: 26,
            color: EditorTheme.surfaceDarker,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Moved ${trashed.originalPath.split('/').last} to '
                    '${AssetIndex.trashFolder}/',
                    style: TextStyle(
                      color: EditorTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
                TextButton(onPressed: _restore, child: const Text('Restore')),
              ],
            ),
          ),
      ],
    );
  }

  Widget _toolbar() {
    final parts = _dir.split('/');
    return EditorToolbar(
      children: [
        // Breadcrumbs: every folder on the way is a way back.
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < parts.length; i++) ...[
                  if (i > 0)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 13,
                      color: EditorTheme.textMuted,
                    ),
                  InkWell(
                    onTap: () => _go(parts.sublist(0, i + 1).join('/')),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(
                        parts[i],
                        style: TextStyle(
                          color: i == parts.length - 1
                              ? EditorTheme.textPrimary
                              : EditorTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        for (final kind in const [
          AssetKind.image,
          AssetKind.sprite,
          AssetKind.scene,
          AssetKind.tileset,
          AssetKind.levelMap,
          AssetKind.audio,
        ])
          EditorChip(
            label: kind.label,
            color: assetColor(kind),
            selected: _kinds.contains(kind),
            onTap: () => setState(
              () => _kinds.contains(kind)
                  ? _kinds.remove(kind)
                  : _kinds.add(kind),
            ),
          ),
        const SizedBox(width: 6),
        EditorSearchField(
          hint: 'Search in ${parts.last}',
          width: 170,
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(width: 4),
        EditorIconButton(
          icon: _grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
          tooltip: _grid ? 'List' : 'Grid',
          onTap: () {
            setState(() => _grid = !_grid);
            _memory?.write('grid', _grid);
          },
        ),
        EditorIconButton(
          icon: Icons.create_new_folder_outlined,
          tooltip: 'New folder',
          onTap: _newFolder,
        ),
        EditorIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh',
          onTap: _index.scan,
        ),
      ],
    );
  }

  Widget _tree() {
    Widget node(String dir, int depth) {
      final children = [
        for (final e in _index.childrenOf(dir))
          if (e.isDirectory) e,
      ];
      final open = _openFolders.contains(dir);
      final actions = [
        for (final a in widget.scope.assetActions)
          if (a.appliesTo(dir, isDirectory: true)) a,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _go(dir),
            child: Container(
              height: 22,
              color: dir == _dir ? EditorTheme.selectionBg : null,
              padding: EdgeInsets.only(left: 4.0 + depth * 12, right: 4),
              child: Row(
                children: [
                  Semantics(
                    button: children.isNotEmpty,
                    label: children.isEmpty
                        ? null
                        : open
                        ? 'Collapse'
                        : 'Expand',
                    child: InkWell(
                      onTap: children.isEmpty
                          ? null
                          : () => setState(
                              () => open
                                  ? _openFolders.remove(dir)
                                  : _openFolders.add(dir),
                            ),
                      child: Icon(
                        children.isEmpty
                            ? Icons.remove
                            : open
                            ? Icons.expand_more_rounded
                            : Icons.chevron_right_rounded,
                        size: 13,
                        color: children.isEmpty
                            ? Colors.transparent
                            : EditorTheme.textMuted,
                      ),
                    ),
                  ),
                  Icon(
                    open && children.isNotEmpty
                        ? Icons.folder_open_rounded
                        : Icons.folder_rounded,
                    size: 13,
                    color: assetColor(AssetKind.folder),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      dir.split('/').last,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: dir == _dir
                            ? EditorTheme.textPrimary
                            : EditorTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (dir == _dir)
                    for (final a in actions)
                      EditorIconButton(
                        icon: a.icon,
                        tooltip: a.label,
                        onTap: () => a.run(widget.scope, dir),
                      ),
                ],
              ),
            ),
          ),
          if (open)
            for (final c in children) node(c.path, depth + 1),
        ],
      );
    }

    return SingleChildScrollView(child: node(_index.folder, 0));
  }

  Widget _draggable(AssetEntry entry, Widget child) => entry.isDirectory
      ? child
      : Draggable<String>(
          // The project-relative path: what an inspector field, and the
          // viewport, take.
          data: entry.path,
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: EditorTheme.dialogBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: EditorTheme.border),
              ),
              child: Text(
                entry.name,
                style: TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: child),
          child: child,
        );

  /// Selection is on the raw pointer, not a tap: a tap that shares the
  /// arena with a double tap only resolves once the double-tap time is up,
  /// and a click should select at once.
  Widget _interactive(AssetEntry entry, Widget child) => Listener(
    onPointerDown: (_) {
      if (_selected != entry.path) setState(() => _selected = entry.path);
    },
    child: GestureDetector(
      onDoubleTap: () => _open(entry),
      onSecondaryTapUp: (d) => _menu(entry, d.globalPosition),
      child: _draggable(entry, child),
    ),
  );

  Widget _thumbnail(AssetEntry entry, double size) {
    final image = thumbnailOf(_index, entry);
    if (image == null) {
      return Icon(
        assetIcon(entry.kind),
        size: size * 0.5,
        color: assetColor(entry.kind),
      );
    }
    return Image.file(
      File(_index.absolute(image)),
      // Keyed by when it changed, so a re-saved sheet is not the cached one.
      key: ValueKey('$image@${_index.entryAt(image)?.modified}'),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
      cacheWidth: (size * 2).round(),
      errorBuilder: (context, _, _) => Icon(
        Icons.broken_image_outlined,
        size: size * 0.5,
        color: EditorTheme.textMuted,
      ),
    );
  }

  Widget _gridView(List<AssetEntry> shown) => GridView.builder(
    padding: const EdgeInsets.all(8),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 92,
      mainAxisExtent: 92,
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
    ),
    itemCount: shown.length,
    itemBuilder: (context, i) {
      final entry = shown[i];
      final selected = entry.path == _selected;
      return _interactive(
        entry,
        Tooltip(
          message: entry.path,
          child: Container(
            decoration: BoxDecoration(
              color: selected ? EditorTheme.selectionBg : null,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected
                    ? EditorTheme.primaryMutedLight
                    : Colors.transparent,
              ),
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                Expanded(child: Center(child: _thumbnail(entry, 56))),
                const SizedBox(height: 3),
                Text(
                  entry.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? EditorTheme.textPrimary
                        : EditorTheme.textSecondary,
                    fontSize: 10,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _listView(List<AssetEntry> shown) => ListView.builder(
    itemExtent: 22,
    itemCount: shown.length,
    itemBuilder: (context, i) {
      final entry = shown[i];
      final selected = entry.path == _selected;
      return _interactive(
        entry,
        Container(
          color: selected ? EditorTheme.selectionBg : null,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(
                assetIcon(entry.kind),
                size: 13,
                color: assetColor(entry.kind),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  // A search shows where each hit lives.
                  _query.isEmpty && _kinds.isEmpty
                      ? entry.name
                      : entry.path.substring(_dir.length + 1),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? EditorTheme.textPrimary
                        : EditorTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
              if (!entry.isDirectory)
                Text(
                  entry.sizeLabel,
                  style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _preview(AssetEntry entry) {
    final actions = [
      for (final a in widget.scope.assetActions)
        if (a.appliesTo(entry.path, isDirectory: false)) a,
    ];
    final modified = entry.modified;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: EditorTheme.surfaceDarker,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: EditorTheme.border),
              ),
              child: Center(child: _thumbnail(entry, 150)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            [
              entry.kind.label,
              entry.sizeLabel,
              if (modified != null)
                '${modified.year}-${modified.month.toString().padLeft(2, '0')}-'
                    '${modified.day.toString().padLeft(2, '0')}',
            ].join(' · '),
            style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              EditorIconButton(
                icon: Icons.open_in_new_rounded,
                tooltip: 'Open',
                onTap: () => _open(entry),
              ),
              for (final a in actions)
                EditorIconButton(
                  icon: a.icon,
                  tooltip: a.label,
                  onTap: () => a.run(widget.scope, entry.path),
                ),
              EditorIconButton(
                icon: Icons.travel_explore_rounded,
                tooltip: 'Find references',
                onTap: () => _showReferences(entry),
              ),
              const Spacer(),
              EditorIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Delete (to the trash)',
                color: EditorTheme.error,
                onTap: () => _delete(entry),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
