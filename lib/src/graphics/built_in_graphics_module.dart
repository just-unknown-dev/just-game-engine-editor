import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'graphics_inspectors.dart';
import 'graphics_overlays.dart';
import 'model_cooking.dart';
import 'model_expansion.dart';
import 'model_ray_test.dart';
import 'model_thumbnails.dart';
import 'model_workspace.dart';

/// The editor's 3-D graphics: models, lights and the environment.
///
/// It adds:
/// - **models** (`.glb`, `.gltf`) to the Assets dock, pictured by a render
///   of each ([ModelThumbnails]), and dropped on the viewport of a 3-D
///   scene as an entity with a [ModelComponent] where the pointer meets
///   the ground;
/// - **picking by triangles** once a model has loaded ([ModelRayTest]);
/// - **viewport aids** in 3-D scenes: a marker on every light, a selected
///   light's reach ([LightReachOverlay]) and a selected camera's frustum
///   ([CameraFrustumOverlay]);
/// - **inspector sections** for Model, Light and Environment
///   ([GraphicsInspectors]);
/// - **importing**: a model opens in a workspace of its settings and
///   materials with a live preview ([ModelWorkspace]); saved, it is cooked
///   ([ModelCooking]) and the game loads the cooked copy. Models with
///   settings are cooked again when their file changes. The Assets dock
///   offers to cook, to stop using the cooked copy, and to place a model
///   with its lights and sockets as entities of their own
///   ([ModelExpansion]).
///
/// While the editor runs, the game reads models from the project's files
/// rather than the app's bundle, so a model added or cooked since the app
/// was built loads.
///
/// One of the editor's own modules, for a game with 3-D graphics only
/// ([isFor]): a 2-D game can't draw a model, so it is not offered one.
class BuiltInGraphicsModule extends EditorModule {
  /// The module for the project at [root] (the working directory when
  /// null).
  BuiltInGraphicsModule({this.root, ModelThumbnails? thumbnails})
    : _thumbnails = thumbnails;

  /// The module for [scope]: how the editor makes its built-ins.
  static EditorModule make(EditorScope scope) => BuiltInGraphicsModule();

  /// Whether the editor has this module for [engine]'s game: when it has
  /// 3-D graphics (`EngineConfig(graphics3D: Graphics3D())`).
  static bool isFor(Engine engine) => engine.graphics3D != null;

  /// Its id.
  static const String moduleId = 'graphics';

  /// The project folder.
  final String? root;

  ModelThumbnails? _thumbnails;

  String get _root => (root ?? Directory.current.path).replaceAll(r'\', '/');

  /// The pictures of models the Assets dock shows.
  ModelThumbnails get thumbnails => _thumbnails ??= ModelThumbnails(
    root: _root,
    cacheFolder: '$_root/.dart_tool/just_game_engine_editor/model_pictures',
  );

  /// Import settings and cooking for the project's models.
  late final ModelCooking cooking = ModelCooking(root: _root);

  /// The model workspace's id.
  static const String workspaceId = 'graphics.model';

  /// The Place with its lights and sockets action's id.
  static const String placeId = 'graphics.place';

  /// The scenes models go in: 3-D ones. What the viewport takes a model
  /// dropped into, and where the Assets dock offers to place one.
  static const Dimensions modelScenes = Dimensions.threeD;

  GraphicsModels? _models;
  bool _cookedOnce = false;

  EditorScope? _scope;

  @override
  String get id => moduleId;

  @override
  String get name => '3D Graphics';

  @override
  IconData? get icon => Icons.view_in_ar;

  @override
  void onRegister(EditorModuleContext context) => _scope = context.scope;

  @override
  void onUpdate(double dt) => _attach();

  // Once the game's 3-D service is up: models read from the project's
  // files, and those with settings cooked if their file changed.
  void _attach() {
    final service = _scope?.engine?.services.maybe<Graphics3D>();
    if (service == null || !service.isStarted) return;
    final models = service.models;
    if (identical(models, _models)) return;
    _models = models;
    models.readOverride = readProjectFile;
    if (_cookedOnce) return;
    _cookedOnce = true;
    _cookStale(cooking.modelsUnder('assets'));
  }

  /// The bytes of the project's file at [path], or null when it isn't
  /// there (a package's asset: the bundle has it).
  Future<Uint8List?> readProjectFile(String path) async {
    final file = File('$_root/$path');
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> _cookStale(Iterable<String> paths) async {
    final (cooked, failed) = await cooking.cookStale(paths);
    for (final path in cooked) {
      _reload(path);
      _log('Cooked $path again: it or its settings changed.');
    }
    for (final MapEntry(:key, :value) in failed.entries) {
      _log('Could not cook $key: $value', warn: true);
    }
  }

  void _reload(String path) => _models?.reload(path);

  void _log(String message, {bool warn = false}) => _scope?.log.log(
    message,
    source: 'graphics',
    level: warn ? DebuggerLogLevel.warning : DebuggerLogLevel.info,
  );

  // Whether the actions that write files may run on [path]: not on a
  // package's assets (`packages/<name>/…`), which are the package's — in
  // pub's shared cache, or an Asset Store item.
  static bool _ownFile(String path) =>
      path != 'packages' && !path.startsWith('packages/');

  // Whether the open scene is one models go in.
  bool get _inModelScene {
    final state = _scope?.sceneState;
    return state != null &&
        state.hasScene &&
        modelScenes.allows(state.editingMode);
  }

  @override
  List<WorkspaceDefinition> get workspaces => [
    WorkspaceDefinition(
      id: workspaceId,
      label: 'Model',
      icon: Icons.view_in_ar,
      fileExtensions: const ['glb', 'gltf'],
      build: (context, workspace) => ModelWorkspace(
        path: workspace.path!,
        cooking: cooking,
        thumbnails: thumbnails,
        workspace: workspace,
        onCooked: _reload,
      ),
    ),
  ];

  /// A file changed: a picture a shape is drawn with is read again by the
  /// game's renderer. (The editor has materials read again itself.)
  @override
  void onAssetChanged(String path) {
    final service = _scope?.engine?.services.maybe<Graphics3D>();
    if (service == null || !service.isStarted) return;
    service.sceneRenderer.shapes.reloadTexture(path);
  }

  @override
  List<AssetAction> get assetActions => [
    AssetAction(
      id: 'graphics.cook',
      label: 'Cook',
      icon: Icons.local_fire_department_outlined,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory && ModelCooking.isModel(path) && _ownFile(path),
      run: (scope, path) async {
        try {
          final result = await cooking.cook(path);
          _reload(path);
          scope.reloadAssets([ModelImportSettings.cookedOf(path)]);
          _log(['Cooked $path.', ...result.warnings].join(' '));
        } on Object catch (error) {
          _log('Could not cook $path: $error', warn: true);
        }
      },
    ),
    AssetAction(
      id: 'graphics.uncook',
      label: 'Use the file, not its cooked copy',
      icon: Icons.restart_alt,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory &&
          ModelCooking.isModel(path) &&
          _ownFile(path) &&
          cooking.isCooked(path),
      run: (scope, path) async {
        await cooking.uncook(path);
        _reload(path);
        scope.reloadAssets([ModelImportSettings.cookedOf(path)]);
        _log('$path loads from the file again.');
      },
    ),
    AssetAction(
      id: placeId,
      label: 'Place with its lights and sockets',
      icon: Icons.account_tree_outlined,
      // Offered while a scene models go in is open.
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory && ModelCooking.isModel(path) && _inModelScene,
      run: (scope, path) async {
        if (!_inModelScene) {
          _log('Models go in 3D scenes: open one to place $path.', warn: true);
          return;
        }
        try {
          final file = File('$_root/$path');
          final folder = file.parent.path;
          final data = cooking
              .settingsOf(path)
              .apply(
                await loadModelData(
                  await file.readAsBytes(),
                  name: path,
                  fetch: (uri) => File('$folder/$uri').readAsBytes(),
                ),
              );
          ModelExpansion.place(
            scope,
            ModelExpansion.partsOf(data, path, scope.editorView.focus),
          );
        } on Object catch (error) {
          _log('Could not place $path: $error', warn: true);
        }
      },
    ),
    AssetAction(
      id: 'graphics.cookFolder',
      label: 'Cook changed models',
      icon: Icons.local_fire_department_outlined,
      appliesTo: (path, {required isDirectory}) =>
          isDirectory && _ownFile(path),
      run: (scope, path) => _cookStale(cooking.modelsUnder(path)),
    ),
  ];

  /// The model kind: `.glb` and `.gltf`, with a picture, and a drop in a
  /// 3-D scene ([modelScenes]).
  late final AssetKind modelKind = AssetKind(
    'model',
    'Models',
    icon: Icons.view_in_ar_outlined,
    color: const Color(0xFFB39DDB),
    endings: const ['.glb', '.gltf'],
    filterable: true,
    preview: (context, index, entry, size) => _ModelPicture(
      thumbnails: thumbnails,
      path: entry.path,
      modified: entry.modified,
      size: size,
    ),
    drop: dropModel,
    dropsIn: modelScenes,
  );

  /// Makes an entity showing the model [drop] carries, where it landed.
  static Entity? dropModel(AssetDrop drop) {
    final slash = drop.path.lastIndexOf('/');
    final dot = drop.path.lastIndexOf('.');
    final stem = drop.path.substring(
      slash + 1,
      dot > slash ? dot : drop.path.length,
    );
    return drop.place([ModelComponent(model: drop.path)], name: stem);
  }

  /// Cooked copies (`.jmodel`): listed, not dropped — drop the model.
  static const AssetKind cookedKind = AssetKind(
    'cookedModel',
    'Cooked models',
    icon: Icons.inventory_2_outlined,
    color: Color(0xFF8E7CC3),
    endings: [ModelImportSettings.cookedExtension],
  );

  @override
  List<AssetKind> get assetKinds => [modelKind, cookedKind];

  // Asked for before [onRegister] hands over the scope, so it looks the
  // scope up when it picks.
  late final ModelRayTest _rayTest = ModelRayTest(
    (path) => loadedModel(_scope, path),
  );

  @override
  List<EntityRayTest> get pickTests => [_rayTest];

  /// The parsed model at [path] if [scope]'s engine has loaded it.
  static ModelData? loadedModel(EditorScope? scope, String path) {
    final service = scope?.engine?.services.maybe<Graphics3D>();
    if (service == null) return null;
    try {
      return service.models.dataOf(path);
    } on StateError {
      return null;
    }
  }

  @override
  List<EditorMarker> get markers => [lightMarker];

  @override
  List<ViewportOverlay> get viewportOverlays => [
    LightReachOverlay(),
    CameraFrustumOverlay(),
  ];

  @override
  List<InspectorSection> get inspectorSections => GraphicsInspectors.all(
    (scope) =>
        (path) => loadedModel(scope, path),
  );
}

/// A model's picture in the Assets dock: its render once ready, its icon
/// until then (and for good where there is no GPU).
class _ModelPicture extends StatelessWidget {
  const _ModelPicture({
    required this.thumbnails,
    required this.path,
    required this.modified,
    required this.size,
  });

  final ModelThumbnails thumbnails;
  final String path;
  final DateTime? modified;
  final double size;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: thumbnails.revision,
    builder: (context, _, _) {
      final image = thumbnails.peek(path, modified: modified);
      if (image == null) {
        return Icon(
          Icons.view_in_ar_outlined,
          size: size * 0.5,
          color: const Color(0xFFB39DDB),
        );
      }
      return RawImage(
        image: image,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    },
  );
}
