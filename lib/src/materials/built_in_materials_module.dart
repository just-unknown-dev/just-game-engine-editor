import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'map_pictures.dart';
import 'material_checks.dart';
import 'material_overrides_editor.dart';
import 'model_materials.dart';
import 'normal_maps.dart';
import 'texture_sets.dart';
import 'material_2d_pictures.dart';
import 'material_2d_users.dart';
import 'material_2d_workspace.dart';
import 'material_pictures.dart';
import 'material_workspace.dart';

/// Materials in the editor, 3-D and 2-D.
///
/// - **3-D materials** (`.material.json`) in the Assets dock, pictured on
///   a ball ([MaterialPictures]); opened, a material shows in a workspace of
///   its look with a live preview ([MaterialWorkspace]); dropped on a shape
///   or a model in the viewport, it draws it (one undo step).
/// - **2-D materials** (`.material2d.json`), for sprites, shapes and tile
///   layers or for the whole frame, pictured as the game draws them
///   ([Material2DPictures]) and opened in a workspace of their effects with
///   a live preview ([Material2DWorkspace]).
/// - A folder's menu makes a new one of each; a material's makes a
///   variant of it.
///
/// The engine draws the materials and reads a changed one again; the
/// editor tells it when a file changes.
///
/// One of the editor's own modules, so materials can always be made and
/// edited; an add-on (`just_material_editor`) adds to its windows through
/// `EditorModule.workspaceContributions` (their ids: [WorkspaceIds]).
class BuiltInMaterialsModule extends EditorModule {
  /// The module for the project at [root] (the working directory when
  /// null).
  BuiltInMaterialsModule({this.root, MaterialPictures? pictures})
    : _pictures = pictures;

  /// The module for [scope]: how the editor makes its built-ins.
  static EditorModule make(EditorScope scope) => BuiltInMaterialsModule();

  /// Its id.
  static const String moduleId = 'materials';

  /// The project folder.
  final String? root;

  MaterialPictures? _pictures;
  Material2DPictures? _pictures2D;

  String get _root => (root ?? Directory.current.path).replaceAll(r'\', '/');

  /// The pictures of 3-D materials the Assets dock and the workspace show.
  @internal
  MaterialPictures get pictures => _pictures ??= MaterialPictures(
    root: _root,
    cacheFolder: '$_root/.dart_tool/just_game_engine_editor/material_pictures',
  );

  /// The pictures of 2-D materials the Assets dock shows.
  @internal
  Material2DPictures get pictures2D =>
      _pictures2D ??= Material2DPictures(root: _root);

  /// The pictures of the images materials' maps name.
  @internal
  late final MapPictures maps = MapPictures(root: _root);

  final StreamController<String> _changes = StreamController.broadcast();

  /// The 3-D material workspace's id.
  static const String workspaceId = WorkspaceIds.material;

  /// The 2-D material workspace's id.
  static const String workspace2DId = WorkspaceIds.material2D;

  /// The New material action's id.
  static const String newMaterialId = 'materials.new';

  /// The New 2D material action's id.
  static const String newMaterial2DId = 'materials.new2D';

  /// The New screen material action's id.
  static const String newScreenMaterialId = 'materials.newScreen';

  /// The New variant action's id.
  static const String newVariantId = 'materials.newVariant';

  /// The Make materials from texture sets action's id.
  static const String textureSetsId = 'materials.textureSets';

  /// The Extract materials action's id (on a model).
  static const String extractId = 'materials.extract';

  /// The id of the Assets dock's Generate normal map action for a sprite
  /// (rounded at its clear edges).
  static const String spriteNormalId = 'materials.normalSprite';

  /// The id of the Generate normal map action for a texture that repeats
  /// (its edges meet).
  static const String tilingNormalId = 'materials.normalTiling';

  /// What a 3-D material is drawn in, in the Assets dock.
  static const Color color = Color(0xFF4DB6AC);

  /// What a 2-D material is drawn in, in the Assets dock.
  static const Color color2D = Color(0xFFBA68C8);

  EditorScope? _scope;

  @override
  String get id => moduleId;

  @override
  String get name => 'Materials';

  @override
  IconData? get icon => Icons.texture;

  @override
  void onRegister(EditorModuleContext context) => _scope = context.scope;

  void _log(String message, {bool warn = false}) => _scope?.log.log(
    message,
    source: 'materials',
    level: warn ? DebuggerLogLevel.warning : DebuggerLogLevel.info,
  );

  static bool _isImage(String path) {
    final lower = path.toLowerCase();
    return TextureSets.imageEndings.any(lower.endsWith);
  }

  static bool _isModel(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.glb') || lower.endsWith('.gltf');
  }

  // Whether the actions that write files may run on [path]: not on a
  // package's assets (`packages/<name>/…`), which are the package's — in
  // pub's shared cache, or an Asset Store item — as the Assets dock leaves
  // them alone for Rename and Delete.
  static bool _ownFile(String path) =>
      path != 'packages' && !path.startsWith('packages/');

  @override
  List<WorkspaceDefinition> get workspaces => [
    WorkspaceDefinition(
      id: workspaceId,
      label: 'Material',
      icon: Icons.texture,
      fileExtensions: const ['material.json'],
      build: (context, workspace) => MaterialWorkspace(
        path: workspace.path!,
        root: _root,
        pictures: pictures,
        maps: maps,
        changes: _changes.stream,
        workspace: workspace,
      ),
    ),
    WorkspaceDefinition(
      id: workspace2DId,
      label: '2D material',
      icon: Icons.auto_awesome,
      fileExtensions: const ['material2d.json'],
      build: (context, workspace) => Material2DWorkspace(
        path: workspace.path!,
        root: _root,
        maps: maps,
        changes: _changes.stream,
        workspace: workspace,
      ),
    ),
  ];

  @override
  List<String> get dataFileSuffixes => const [
    MaterialFile.ending,
    Material2DFile.ending,
  ];

  @override
  List<AssetAction> get assetActions => [
    AssetAction(
      id: newMaterialId,
      label: 'New material',
      icon: Icons.texture,
      appliesTo: (path, {required isDirectory}) =>
          isDirectory && _ownFile(path),
      run: (scope, path) => _made(scope, newMaterial(path)),
    ),
    AssetAction(
      id: newMaterial2DId,
      label: 'New 2D material',
      icon: Icons.auto_awesome,
      appliesTo: (path, {required isDirectory}) =>
          isDirectory && _ownFile(path),
      run: (scope, path) =>
          _made(scope, newMaterial2D(path, kind: Material2DKind.sprite)),
    ),
    AssetAction(
      id: newScreenMaterialId,
      label: 'New screen material',
      icon: Icons.filter_frames_outlined,
      appliesTo: (path, {required isDirectory}) =>
          isDirectory && _ownFile(path),
      run: (scope, path) =>
          _made(scope, newMaterial2D(path, kind: Material2DKind.screen)),
    ),
    AssetAction(
      id: newVariantId,
      label: 'New variant',
      icon: Icons.call_split,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory &&
          _ownFile(path) &&
          (MaterialFile.isMaterialPath(path) ||
              Material2DFile.isMaterial2DPath(path)),
      run: (scope, path) => _made(scope, newVariant(path)),
    ),
    AssetAction(
      id: textureSetsId,
      label: 'Make materials from texture sets',
      icon: Icons.layers_outlined,
      appliesTo: (path, {required isDirectory}) =>
          isDirectory && _ownFile(path),
      run: importTextureSets,
    ),
    AssetAction(
      id: extractId,
      label: 'Extract materials',
      icon: Icons.texture,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory && _ownFile(path) && _isModel(path),
      run: extractMaterials,
    ),
    AssetAction(
      id: spriteNormalId,
      label: 'Generate normal map (sprite)',
      icon: Icons.auto_fix_high,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory && _ownFile(path) && _isImage(path),
      run: (scope, path) =>
          generateNormalMap(scope, path, const NormalMapOptions.sprite()),
    ),
    AssetAction(
      id: tilingNormalId,
      label: 'Generate normal map (tiling)',
      icon: Icons.auto_fix_high,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory && _ownFile(path) && _isImage(path),
      run: (scope, path) =>
          generateNormalMap(scope, path, const NormalMapOptions.tiling()),
    ),
  ];

  /// Makes a material of every texture set in [folder] — maps named
  /// alike (`brick_albedo.png`, `brick_normal.png`) — packing roughness,
  /// metal and occlusion into one map and turning DirectX normal maps
  /// over, and opens the first. Gives the materials made.
  @internal
  Future<List<String>> importTextureSets(
    EditorScope scope,
    String folder,
  ) async {
    final sets = TextureSets.inFolder(_root, folder);
    if (sets.isEmpty) {
      _log(
        'No texture sets in $folder: maps named alike, as brick_albedo.png '
        'and brick_normal.png.',
        warn: true,
      );
      return const [];
    }
    final made = <String>[];
    for (final set in sets) {
      try {
        final result = await TextureSets.make(_root, set);
        made
          ..add(result.material)
          ..addAll(result.made);
        _log(['Made ${result.material} from $set.', ...result.notes].join(' '));
      } on Object catch (error) {
        _log('Could not make a material of $set: $error', warn: true);
      }
    }
    if (made.isNotEmpty) {
      scope
        ..reloadAssets(made)
        ..openInWorkspace(made.first);
    }
    return made;
  }

  /// Writes the materials of the model at [path] as material files beside
  /// it, and opens the first. Gives the files made.
  @internal
  Future<List<String>> extractMaterials(EditorScope scope, String path) async {
    try {
      final made = await ModelMaterials.extract(_root, path);
      if (made.isEmpty) {
        _log('$path has no materials of its own.', warn: true);
        return made;
      }
      _log(
        'Extracted ${made.length} materials from $path: ${made.join(', ')}.',
      );
      scope
        ..reloadAssets(made)
        ..openInWorkspace(made.first);
      return made;
    } on Object catch (error) {
      _log('Could not extract the materials of $path: $error', warn: true);
      return const [];
    }
  }

  /// Makes the normal map of the image at [path] beside it, as [options]
  /// say. Gives its path, or null when it could not be made.
  @internal
  Future<String?> generateNormalMap(
    EditorScope scope,
    String path,
    NormalMapOptions options,
  ) async {
    try {
      final made = await NormalMaps.generate(_root, path, options: options);
      _log('Made $made, the normal map of $path.');
      scope.reloadAssets([made]);
      return made;
    } on Object catch (error) {
      _log('Could not make a normal map of $path: $error', warn: true);
      return null;
    }
  }

  Future<void> _made(EditorScope scope, Future<String> making) async {
    final String made;
    try {
      made = await making;
    } on Object catch (error) {
      // A folder that can't be written, a full disk: said, not thrown.
      _log('Could not make it: $error', warn: true);
      return;
    }
    scope
      ..reloadAssets([made])
      ..openInWorkspace(made);
    _log('Made $made.');
  }

  /// The 3-D material kind: `.material.json`, pictured on a ball, dropped
  /// on a shape or model to draw it with.
  @internal
  late final AssetKind materialKind = AssetKind(
    'material',
    'Materials',
    icon: Icons.texture,
    color: color,
    endings: const [MaterialFile.ending],
    filterable: true,
    preview: (context, index, entry, size) => _Picture(
      revision: pictures.revision,
      peek: () => pictures.peek(entry.path, modified: entry.modified),
      icon: Icons.texture,
      color: color,
      size: size,
    ),
    drop: dropMaterial,
  );

  /// The 2-D material kind: `.material2d.json`, pictured as the game draws
  /// it.
  @internal
  late final AssetKind material2DKind = AssetKind(
    'material2D',
    '2D materials',
    icon: Icons.auto_awesome,
    color: color2D,
    endings: const [Material2DFile.ending],
    filterable: true,
    preview: (context, index, entry, size) => _Picture(
      revision: pictures2D.revision,
      peek: () => pictures2D.peek(entry.path, modified: entry.modified),
      icon: Icons.auto_awesome,
      color: color2D,
      size: size,
    ),
    drop: dropMaterial2D,
  );

  @override
  List<SceneValidator> get validators => MaterialChecks.all;

  @override
  Map<String, FieldEditorBuilder> get fieldEditors =>
      MaterialOverrideEditors.forRoot(_root);

  /// The kind of the 2-D material at [path], its parents followed; null
  /// when it can't be read.
  @internal
  Material2DKind? kindOf2D(String path) {
    try {
      return MaterialChain.resolve2D(path, (p) {
        final f = File(PackageAssetPaths.of(_root).absolute(p));
        return f.existsSync()
            ? Material2DFile.parse(f.readAsStringSync())
            : null;
      }).value.kind;
    } on Object {
      return null;
    }
  }

  /// In a 2-D scene: a sprite material drawn on the sprite or shape it
  /// landed on; a screen material put on the scene's screen material (or
  /// a new one made for it). One undo step; nothing else is made.
  @internal
  Entity? dropMaterial2D(AssetDrop drop) {
    if (drop.surface != null) return null; // A 3-D scene.
    final scope = drop.scope;
    final path = drop.path;
    final kind = kindOf2D(path);
    if (kind == null) {
      _log("$path can't be read as a 2D material.", warn: true);
      return null;
    }
    if (kind == Material2DKind.screen) {
      ScreenMaterial? current;
      for (final e in scope.world.query(const [ScreenMaterial])) {
        final s = e.getComponent<ScreenMaterial>()!;
        if (current == null || s.order > current.order) current = s;
      }
      if (current == null) {
        return drop.place([ScreenMaterial(material: path)], name: 'Screen');
      }
      final edit = ComponentEdit.begin(scope, current);
      current
        ..material = path
        ..enabled = true;
      edit.commit('Screen material');
      return null;
    }
    final selectable = scope.sceneState.selectable.value;
    final onto = DesignerGeometry.topmostAt(
      scope.world,
      Offset(drop.at.x, drop.at.y),
      pickable: (e) =>
          (selectable?.call(e) ?? true) &&
          e.hasComponent<RenderableComponent>() &&
          !e.hasComponent<LevelMapComponent>(),
      markerReach: 0,
    );
    if (onto == null) {
      _log(
        'Drop a 2D material on a sprite or a shape to draw it with it; a '
        "Level Map layer takes one in its layer settings.",
      );
      return null;
    }
    final label = 'Paint ${onto.name ?? 'entity'}';
    final had = onto.getComponent<Material2D>();
    if (had != null) {
      final edit = ComponentEdit.begin(scope, had);
      had.material = path;
      edit.commit(label);
    } else {
      scope.history.push(
        CompositeCommand(
          label: label,
          commands: [
            AddComponentCommand(
              entity: onto,
              component: Material2D(material: path),
              sceneState: scope.sceneState,
            ),
          ],
        ),
      );
    }
    return null;
  }

  @override
  List<AssetKind> get assetKinds => [materialKind, material2DKind];

  /// Draws what [drop] landed on with the material it carries, as one
  /// undo step; makes nothing.
  @internal
  static Entity? dropMaterial(AssetDrop drop) {
    final onto = drop.surface?.onto;
    if (onto == null) return null;
    final holder = MaterialSlots.holderOf(onto);
    if (holder == null) return null;
    final edit = ComponentEdit.begin(drop.scope, holder);
    MaterialSlots.assign(onto, drop.path);
    edit.commit('Paint ${onto.name ?? 'entity'}');
    return null;
  }

  /// Makes a new material in [folder] (project-relative) — `material`,
  /// or `material_2` and on when that is taken — and gives its path.
  @internal
  Future<String> newMaterial(String folder) => _newFile(
    folder,
    'material',
    MaterialFile.ending,
    const MaterialFile(color: 0xFFD5D9DF).encode(),
  );

  /// Makes a new 2-D material of [kind] in [folder] — `material` (or
  /// `screen` for a screen material), `_2` and on when that is taken —
  /// and gives its path.
  @internal
  Future<String> newMaterial2D(
    String folder, {
    Material2DKind kind = Material2DKind.sprite,
  }) => _newFile(
    folder,
    kind == Material2DKind.screen ? 'screen' : 'material',
    Material2DFile.ending,
    Material2DFile(kind: kind).encode(),
  );

  /// Makes a variant of the material at [path] (3-D or 2-D) beside it —
  /// `<name>_variant`, then `_variant_2` and on — taking everything from
  /// it until it is given values of its own, and gives its path.
  @internal
  Future<String> newVariant(String path) {
    final slash = path.lastIndexOf('/');
    final dir = slash < 0 ? '' : path.substring(0, slash);
    final name = path.substring(slash + 1);
    final flat = Material2DFile.isMaterial2DPath(path);
    final ending = flat ? Material2DFile.ending : MaterialFile.ending;
    final stem = name.substring(0, name.length - ending.length);
    return _newFile(
      dir,
      '${stem}_variant',
      ending,
      flat
          ? Material2DFile(parent: path).encode()
          : MaterialFile(parent: path).encode(),
    );
  }

  Future<String> _newFile(
    String folder,
    String stem,
    String ending,
    String text,
  ) async {
    final dir = folder.endsWith('/')
        ? folder.substring(0, folder.length - 1)
        : folder;
    final at = dir.isEmpty ? '' : '$dir/';
    String pathOf(int n) => '$at$stem${n == 1 ? '' : '_$n'}$ending';
    var n = 1;
    while (await File('$_root/${pathOf(n)}').exists()) {
      n++;
    }
    final path = pathOf(n);
    // Whole or not at all, its folder made when missing.
    await ProjectFiles.writeString('$_root/$path', text);
    return path;
  }

  /// A file changed on disk: the pictures that show it are drawn again,
  /// and open workspaces read it again (a parent, a map, a layer).
  @override
  void onAssetChanged(String path) {
    _pictures?.forget(path);
    _pictures2D?.forget(path);
    maps.forget(path);
    // A scene or prefab: what is drawn with a 2-D material, read again.
    if (path.endsWith('.json')) Material2DUsers.forget(_root, path);
    _changes.add(path);
  }

  @override
  void dispose() {
    if (_changes.isClosed) return;
    _pictures?.dispose();
    _pictures = null;
    _pictures2D?.dispose();
    _pictures2D = null;
    maps.dispose();
    _changes.close();
  }
}

/// A material's picture in the Assets dock once drawn; its icon until then
/// (and for good where it can't be).
class _Picture extends StatelessWidget {
  const _Picture({
    required this.revision,
    required this.peek,
    required this.icon,
    required this.color,
    required this.size,
  });

  final ValueListenable<int> revision;
  final ui.Image? Function() peek;
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: revision,
    builder: (context, _, _) {
      final image = peek();
      if (image == null) return Icon(icon, size: size * 0.5, color: color);
      return RawImage(
        image: image,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    },
  );
}
