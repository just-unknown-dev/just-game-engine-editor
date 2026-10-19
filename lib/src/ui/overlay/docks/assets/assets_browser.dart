import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import '../../../../core/prefs/recent_scenes.dart';
import '../../../../core/scope/editor_scope_services.dart';
import '../../../../core/serialization/scene_manager.dart';
import '../../../dialogs/scene_actions_dialogs.dart';

IconData assetIcon(AssetKind kind) => kind.icon;

Color assetColor(AssetKind kind) => kind.color ?? EditorTheme.textMuted;

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

/// Each index's tilesets' images, read from their files — remembered until
/// a file changes, as the grid asks on every build; a tileset gone from
/// the index is forgotten ([_forgetGoneTilesets]), and the whole of it goes
/// with the index.
final Expando<Map<String, (DateTime?, String?)>> _tilesetImagesOf = Expando(
  'tilesetImages',
);

Map<String, (DateTime?, String?)> _tilesetImages(AssetIndex index) =>
    _tilesetImagesOf[index] ??= {};

void _forgetGoneTilesets(AssetIndex index) =>
    _tilesetImagesOf[index]?.removeWhere((path, _) {
      final entry = index.entryAt(path);
      return entry == null || entry.kind != AssetKind.tileset;
    });

String? _tilesetImage(AssetIndex index, AssetEntry entry) {
  final known = _tilesetImages(index)[entry.path];
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
  _tilesetImages(index)[entry.path] = (entry.modified, image);
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
    this.onOpenScene,
    this.sceneManager,
  });

  final EditorScope scope;
  final DockContext dock;
  final AssetIndex index;

  /// Opens the scene named so in the editor: what a scene file in the
  /// scenes folder does when it is opened here. Without it, it opens as
  /// another file does.
  final Future<void> Function(String sceneName)? onOpenScene;

  /// What a scene of the scenes folder is renamed and duplicated through,
  /// and asked about before it is deleted: its name checked, the game's
  /// play order (`scenes.json`, which lists scenes by name) kept, and the
  /// scenes the game's own code opens left alone. Without it, a manager
  /// over the scope's scenes, with none of those protected.
  final SceneManager? sceneManager;

  /// The name of the scene whose file is [file] (an absolute path) when it
  /// is in [scenesRoot] — what the editor opens a scene by; null for any
  /// other file.
  static String? sceneNameAt(String file, String scenesRoot) {
    const ending = '.scene.json';
    final path = file.replaceAll(r'\', '/');
    if (!path.toLowerCase().endsWith(ending)) return null;
    final slash = path.lastIndexOf('/');
    final folder = path.substring(0, slash).toLowerCase();
    final root = scenesRoot.replaceAll(r'\', '/').toLowerCase();
    if (folder != root) return null;
    final name = path.substring(slash + 1);
    return name.substring(0, name.length - ending.length);
  }

  @override
  State<AssetsBrowserDock> createState() => _AssetsBrowserDockState();
}

class _AssetsBrowserDockState extends State<AssetsBrowserDock> {
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

  /// The browser's own focus: Delete, F2, Ctrl+D and Enter act on the
  /// selected file while it has it, not on the level.
  final FocusNode _focus = FocusNode(debugLabel: 'assetsBrowser');

  /// The last delete, while it can still be taken back.
  TrashedAsset? _trashed;
  Timer? _forgetTrashed;

  /// Where the scene deleted last was in the play order, so a restore puts
  /// it back there; null when it was not a listed scene.
  (String, int)? _trashedScene;

  SceneManager? _ownManager;
  SceneManager get _scenes =>
      widget.sceneManager ??
      (_ownManager ??= SceneManager(store: widget.scope.scenes));

  @override
  void initState() {
    super.initState();
    _index.revision.addListener(_changed);
    unawaited(_attempt('scan the assets', _index.scan));
    _index.startWatching();
  }

  @override
  void dispose() {
    _index.revision.removeListener(_changed);
    _forgetTrashed?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    _forgetGoneTilesets(_index);
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

  /// Runs [action], saying in the Console when it fails — "Could not
  /// [what]: …" — rather than letting the error go unheard. Whether it
  /// went through.
  Future<bool> _attempt(String what, Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on SceneManagerException catch (e) {
      _log('Could not $what: ${e.message}', failed: true);
    } on FileSystemException catch (e) {
      _log(
        'Could not $what: ${e.message}${e.path == null ? '' : ' (${e.path})'}',
        failed: true,
      );
    } on Object catch (e) {
      // A program that would not start (no xdg-open on a bare Linux
      // desktop), and the rest.
      _log('Could not $what: $e', failed: true);
    }
    return false;
  }

  // ── Keys ─────────────────────────────────────────────────────────────────

  static const List<LogicalKeyboardKey> _keys = [
    LogicalKeyboardKey.delete,
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ];

  /// The keys the browser keeps while it has the focus itself (not its
  /// search field) and something is selected: Ctrl+D (Cmd+D on macOS, where
  /// Backspace also deletes).
  bool _claims(KeyEvent event) {
    if (!_focus.hasPrimaryFocus || _selected == null) return false;
    if (EditorKeys.primaryPressed) {
      return event.logicalKey == LogicalKeyboardKey.keyD;
    }
    return _keys.contains(event.logicalKey) ||
        EditorKeys.isDeleteKey(event.logicalKey);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_claims(event)) {
      return KeyEventResult.ignored;
    }
    final entry = _index.entryAt(_selected!);
    if (entry == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyD) {
      if (!entry.isDirectory && !entry.isPackage) unawaited(_duplicate(entry));
    } else if (EditorKeys.isDeleteKey(key)) {
      if (!entry.isPackage) unawaited(_delete(entry));
    } else if (key == LogicalKeyboardKey.f2) {
      if (!entry.isPackage) unawaited(_rename(entry));
    } else {
      _open(entry);
    }
    return KeyEventResult.handled;
  }

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
    // A scene of the scenes folder opens as the scene, in the editor.
    if ((widget.onOpenScene, sceneNameOf(entry.path)) case (
      final open?,
      final name?,
    )) {
      unawaited(_attempt('open $name', () => open(name)));
      return;
    }
    if (!widget.scope.openInWorkspace(entry.path)) {
      unawaited(
        _attempt('open ${entry.name}', () => _index.openExternally(entry.path)),
      );
    }
  }

  /// The name of the scene at [path] (project-relative), when it is a scene
  /// of the scenes folder — what the editor opens a scene by; null for any
  /// other file.
  String? sceneNameOf(String path) => AssetsBrowserDock.sceneNameAt(
    _index.absolute(path),
    widget.scope.scenes.scenesRoot,
  );

  Future<void> _newFolder() async {
    String? path;
    final made = await _attempt('make a folder', () async {
      path = await _index.newFolder(_dir);
    });
    if (made && mounted) setState(() => _selected = path);
  }

  /// [path] with [from] made [to]: [from] itself, or — when [from] is a
  /// [folder] — a path under it. Null when it is neither.
  static String? _moved(
    String path,
    String from,
    String to, {
    required bool folder,
  }) {
    if (path == from) return to;
    if (folder && path.startsWith('$from/')) {
      return '$to${path.substring(from.length)}';
    }
    return null;
  }

  /// Points what is loaded in the editor at [to] wherever it named [from]
  /// — for a [folder], at the same place under [to] wherever it named a
  /// path under [from]; [files] are the files that were in it. The files
  /// on disk are rewritten separately.
  int _rewriteWorld(
    String from,
    String to, {
    bool folder = false,
    List<String> files = const [],
  }) {
    final scope = widget.scope;
    var changed = 0;
    for (final entity in scope.world.entities) {
      for (final component in entity.components) {
        final definition = scope.definitions.definitionFor(component);
        if (definition == null) continue;
        for (final field in definition.fields) {
          if (field.kind.id != jge.FieldTypes.assetRef.id) continue;
          final write = field.write;
          final value = field.read(component);
          if (write == null || value is! String) continue;
          final next = _moved(value, from, to, folder: folder);
          if (next == null) continue;
          write(component, next);
          changed++;
        }
      }
    }
    // Tile maps name their tilesets, and tilesets their images, inside
    // themselves rather than in a field.
    for (final file in folder ? files : [from]) {
      changed += scope.mapDocs.renamed(
        file,
        _moved(file, from, to, folder: folder) ?? file,
      );
    }
    if (changed > 0) {
      scope.sceneState
        ..markDirty()
        ..refresh();
    }
    return changed;
  }

  /// Why [entry] cannot be renamed or deleted ([verb]) now; null when it
  /// can.
  String? _whyNot(AssetEntry entry, String verb) {
    final scope = widget.scope;
    // The play-test's snapshot — what Stop puts back, and what a save
    // writes — would go on naming the old path.
    if (scope.isPlayTesting.value) {
      return 'Stop the play-test first: the level it will put back still '
          'names ${entry.name} as it is.';
    }
    bool isOrHolds(String? path) =>
        path != null &&
        (path == entry.path ||
            entry.isDirectory && path.startsWith('${entry.path}/'));
    final open = scope.activeWorkspace.value;
    if (isOrHolds(open?.path)) {
      return '${open!.path} is open in ${open.definition.label}; close it '
          'first.';
    }
    final scenes = _index.relative(scope.scenes.scenesRoot);
    if (entry.isDirectory && isOrHolds(scenes)) {
      return 'The editor and the game keep their scenes in $scenes; it '
          'cannot be ${verb}d.';
    }
    final scene = sceneNameOf(entry.path);
    if (scene != null) {
      if (_scenes.isProtected(scene)) {
        return '"$scene" is used by the game\'s own code and cannot be '
            '${verb}d.';
      }
      if (scope.sceneState.activeScene.value?.name == scene) {
        return '"$scene" is the scene open in the editor: close it first.';
      }
    }
    return null;
  }

  /// [_whyNot], said; true when it was.
  Future<bool> _refused(AssetEntry entry, String verb) async {
    final why = _whyNot(entry, verb);
    if (why == null) return false;
    await _confirm(
      title: "Can't $verb ${entry.name}",
      body: why,
      primary: 'OK',
      cancellable: false,
    );
    return true;
  }

  Future<void> _rename(AssetEntry entry) async {
    if (await _refused(entry, 'rename') || !mounted) return;
    final scene = sceneNameOf(entry.path);
    // A scene is renamed by its name, as the Scenes list renames it.
    final sceneTo = scene == null
        ? null
        : await promptSceneName(
            context,
            title: 'Rename "$scene"',
            actionLabel: 'Rename',
            initialValue: scene,
            validate: (value) => _scenes.validateName(value, ignoring: scene),
          );
    final name = scene == null
        ? await _promptForName(entry.name)
        : sceneTo == null
        ? null
        : '$sceneTo.scene.json';
    if (name == null || name == entry.name || !mounted) return;
    // Asked again: things may have changed while the name was typed.
    if (await _refused(entry, 'rename') || !mounted) return;
    final users = await AssetReferences.find(_index, entry.path);
    var update = false;
    if (users.isNotEmpty && mounted) {
      final choice = await _confirm(
        title: 'Rename "${entry.name}"',
        body:
            '${entry.isDirectory ? 'What is in it is' : 'It is'} used by:\n'
            '${users.map((u) => '  • $u').join('\n')}\n\n'
            'Update those to the new name? The files changed are kept as '
            'they were in ${AssetReferences.backupFolder}/.',
        primary: 'Rename and update',
        secondary: 'Rename only',
      );
      if (choice == null) return;
      update = choice;
    }
    if (!mounted || _whyNot(entry, 'rename') != null) return;
    final files = [
      if (entry.isDirectory)
        for (final e in _index.entries)
          if (!e.isDirectory && e.path.startsWith('${entry.path}/')) e.path,
    ];
    final parent = entry.parent;
    var to = '$parent/$name';
    final renamed = await _attempt('rename ${entry.name}', () async {
      if (scene != null && sceneTo != null) {
        // Through the scene manager: the play order follows.
        await _scenes.renameScene(scene, sceneTo);
        await RecentScenes.rename(widget.scope.prefs, scene, sceneTo);
        await _index.scan();
      } else {
        to = await _index.rename(entry.path, name);
      }
    });
    if (!renamed) return;
    if (update) {
      await _attempt('update what uses ${entry.name}', () async {
        final changed = await AssetReferences.rewrite(_index, entry.path, to);
        final live = _rewriteWorld(
          entry.path,
          to,
          folder: entry.isDirectory,
          files: files,
        );
        _log(
          'Renamed ${entry.name} → $name; updated ${changed.length} files'
          '${live > 0 ? ' and $live components in the open scene' : ''}.',
        );
      });
    }
    if (mounted) setState(() => _selected = to);
  }

  Future<void> _duplicate(AssetEntry entry) async {
    final scene = sceneNameOf(entry.path);
    String? copy;
    if (scene != null) {
      final taken = {for (final n in _scenes.listScenes()) n.toLowerCase()};
      var initial = '${scene}_copy';
      for (var i = 2; taken.contains(initial.toLowerCase()); i++) {
        initial = '${scene}_copy_$i';
      }
      final newScene = await promptSceneName(
        context,
        title: 'Duplicate "$scene"',
        actionLabel: 'Duplicate',
        initialValue: initial,
        validate: (value) => _scenes.validateName(value, ignoring: scene),
      );
      if (newScene == null || !mounted) return;
      final done = await _attempt('duplicate $scene', () async {
        // Listed in the play order straight after the original.
        await _scenes.duplicateScene(scene, newScene);
        await _index.scan();
      });
      if (done) copy = '${entry.parent}/$newScene.scene.json';
    } else {
      await _attempt('duplicate ${entry.name}', () async {
        copy = await _index.duplicate(entry.path);
      });
    }
    if (copy != null && mounted) setState(() => _selected = copy);
  }

  Future<void> _delete(AssetEntry entry) async {
    if (await _refused(entry, 'delete') || !mounted) return;
    // A folder's own files naming each other go with it.
    final users = [
      for (final u in await AssetReferences.find(_index, entry.path))
        if (!entry.isDirectory || !u.startsWith('${entry.path}/')) u,
    ];
    if (!mounted) return;
    if (users.isNotEmpty) {
      final go = await _confirm(
        title: 'Delete "${entry.name}"?',
        body:
            '${entry.isDirectory ? 'What is in it is' : 'It is'} still used '
            'by:\n${users.map((u) => '  • $u').join('\n')}\n\n'
            'It goes to ${AssetIndex.trashFolder}/ and can be restored.',
        primary: 'Delete anyway',
      );
      if (go != true || !mounted) return;
    }
    if (_whyNot(entry, 'delete') != null) return;
    final scene = sceneNameOf(entry.path);
    final order = scene == null ? const <String>[] : _scenes.playOrder();
    TrashedAsset? trashed;
    final done = await _attempt('delete ${entry.name}', () async {
      trashed = await _index.trash(entry.path);
      if (scene != null) {
        // Out of the game's play order too; it comes back with a restore.
        await _scenes.setPlayOrder(_scenes.playOrder());
        await RecentScenes.forget(widget.scope.prefs, scene);
      }
    });
    if (!done && trashed == null) return;
    _trashedScene = scene != null && order.contains(scene)
        ? (scene, order.indexOf(scene))
        : null;
    _forgetTrashed?.cancel();
    _forgetTrashed = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _trashed = null);
    });
    if (mounted) setState(() => _trashed = trashed);
  }

  Future<void> _restore() async {
    final trashed = _trashed;
    if (trashed == null) return;
    final scene = _trashedScene;
    String? path;
    final done = await _attempt('restore ${trashed.originalPath}', () async {
      path = await trashed.restore();
      // Back in the play order where it was, when it is back as itself.
      if (scene != null && path == trashed.originalPath) {
        final order = _scenes.playOrder()..remove(scene.$1);
        order.insert(scene.$2.clamp(0, order.length), scene.$1);
        await _scenes.setPlayOrder(order);
      }
    });
    if (!mounted) return;
    setState(() {
      // A failed restore stays on offer: the file is still in the trash.
      if (done || path != null) {
        _trashed = null;
        _trashedScene = null;
        _selected = path;
      }
    });
  }

  Future<void> _showReferences(AssetEntry entry) async {
    final users = await AssetReferences.find(_index, entry.path);
    if (!mounted) return;
    await _confirm(
      title: 'Used by',
      body: users.isEmpty
          ? 'Nothing in the project mentions ${entry.name} by its path: '
                'not the files under ${_index.folder}/, the game\'s code '
                'under ${AssetReferences.codeFolder}/, nor '
                '${AssetReferences.pubspec}.'
          : users.map((u) => '• $u').join('\n'),
      primary: 'OK',
      cancellable: false,
    );
  }

  Future<String?> _promptForName(String initial) async {
    final dot = initial.lastIndexOf('.');
    final controller = TextEditingController(text: initial)
      // The stem is what gets retyped; the extension rarely is.
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: dot <= 0 ? initial.length : dot,
      );
    try {
      return await showDialog<String>(
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
    } finally {
      // After the dialog's route has gone, not while it animates out.
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
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
      // An installed package's files are its own: use them, don't edit them
      // here (an update would bring the originals back).
      if (!entry.isPackage)
        item('Rename…', Icons.drive_file_rename_outline, () => _rename(entry)),
      if (!entry.isDirectory && !entry.isPackage)
        item('Duplicate', Icons.copy_rounded, () => _duplicate(entry)),
      item(
        'Find references',
        Icons.travel_explore_rounded,
        () => _showReferences(entry),
      ),
      item(
        'Reveal in file manager',
        Icons.folder_open_rounded,
        () => unawaited(
          _attempt('reveal ${entry.name}', () => _index.reveal(entry.path)),
        ),
      ),
      if (!entry.isDirectory)
        item(
          'Open with the default app',
          Icons.launch_rounded,
          () => unawaited(
            _attempt(
              'open ${entry.name}',
              () => _index.openExternally(entry.path),
            ),
          ),
        ),
      if (!entry.isPackage) ...[
        editorMenuDivider(),
        item(
          'Delete',
          Icons.delete_outline_rounded,
          () => _delete(entry),
          color: EditorTheme.error,
        ),
      ],
    ]);
    run?.call();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final selected = _selected == null ? null : _index.entryAt(_selected!);
    // Its keys while it has the focus — a click on a file gives it — rather
    // than the level's: Delete would delete the selected entity.
    return EditorKeyClaim(
      claims: _claims,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: _body(shown, selected),
      ),
    );
  }

  Widget _body(List<AssetEntry> shown, AssetEntry? selected) {
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
        for (final kind in widget.scope.assetKinds.filters)
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
          tooltip: AssetIndex.isPackagePath(_dir)
              ? "An installed package's folders can't be changed"
              : 'New folder',
          onTap: AssetIndex.isPackagePath(_dir) ? null : _newFolder,
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
              // The row's width decides whether the folder's actions fit
              // beside its name as buttons of their own.
              child: LayoutBuilder(
                builder: (context, box) => Row(
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
                    if (dir == _dir && actions.isNotEmpty)
                      _FolderActions(
                        actions: actions,
                        // What the arrow, the folder and a little of the
                        // name leave.
                        room: box.maxWidth - 13 - 13 - 5 - 48,
                        run: (a) => a.run(widget.scope, dir),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            for (final c in children) node(c.path, depth + 1),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          node(_index.folder, 0),
          // Installed packages' assets, by the keys the game loads them with.
          if (_index.hasPackages) node(AssetIndex.packagesFolder, 0),
        ],
      ),
    );
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
          // Dropped where the pointer is, not where the label's corner
          // is: the viewport places it under the pointer.
          dragAnchorStrategy: pointerDragAnchorStrategy,
          childWhenDragging: Opacity(opacity: 0.4, child: child),
          child: child,
        );

  /// Selection is on the raw pointer, not a tap: a tap that shares the
  /// arena with a double tap only resolves once the double-tap time is up,
  /// and a click should select at once.
  Widget _interactive(AssetEntry entry, Widget child) => Listener(
    onPointerDown: (_) {
      _focus.requestFocus();
      if (_selected != entry.path) setState(() => _selected = entry.path);
    },
    child: GestureDetector(
      onDoubleTap: () => _open(entry),
      onSecondaryTapUp: (d) => _menu(entry, d.globalPosition),
      child: _draggable(entry, child),
    ),
  );

  Widget _thumbnail(AssetEntry entry, double size) {
    // A kind that draws its own picture (a module's: a 3-D model's render).
    final preview = entry.kind.preview?.call(context, _index, entry, size);
    if (preview != null) return preview;
    final image = thumbnailOf(_index, entry);
    if (image == null) {
      return Icon(
        assetIcon(entry.kind),
        size: size * 0.5,
        color: assetColor(entry.kind),
      );
    }
    final modified = _index.entryAt(image)?.modified;
    return Image(
      // Read again when it changed, so a re-saved sheet is not the cached one.
      image: ResizeImage.resizeIfNeeded(
        (size * 2).round(),
        null,
        fileImage(_index.absolute(image), version: modified),
      ),
      key: ValueKey('$image@$modified'),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
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
              if (!entry.isPackage)
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

/// The open folder's actions on its row in the tree: a button each when
/// they fit in [room], else one button that lists them, so a narrow tree
/// or many modules' "New ..." never push the row past its edge.
class _FolderActions extends StatelessWidget {
  const _FolderActions({
    required this.actions,
    required this.room,
    required this.run,
  });

  final List<AssetAction> actions;
  final double room;
  final void Function(AssetAction action) run;

  @override
  Widget build(BuildContext context) {
    if (actions.length * EditorMetrics.controlSm <= room) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in actions)
            EditorIconButton(
              icon: a.icon,
              tooltip: a.label,
              onTap: () => run(a),
            ),
        ],
      );
    }
    return Builder(
      builder: (context) => EditorIconButton(
        icon: Icons.more_horiz_rounded,
        tooltip: 'What this folder can do',
        onTap: () async {
          final box = context.findRenderObject()! as RenderBox;
          final chosen = await showEditorMenu<AssetAction>(
            context,
            box.localToGlobal(box.size.bottomLeft(Offset.zero)),
            [
              for (final a in actions)
                editorMenuItem<AssetAction>(a, a.label, icon: a.icon),
            ],
          );
          if (chosen != null) run(chosen);
        },
      ),
    );
  }
}
