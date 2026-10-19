import '../../ui/overlay/docks/dock_controller.dart';
import '../entity/entity_ops.dart';
import '../level_map/level_map_documents.dart';
import '../level_map/level_map_provision.dart';
import '../level_map/tile_edit_state.dart';
import '../prefabs/prefab_instances.dart';
import 'package:just_editor_core/host.dart';

/// The services only the editor itself uses, on the scope they belong to.
///
/// Each is made the first time it is asked for — in the scope's container,
/// so it is disposed with the scope — whoever made the scope: the editor's
/// plugin, or a test over a bare world.
extension EditorScopeServices on EditorScope {
  /// Which dock is open and how tall each one is.
  DockController get dockController =>
      _service(DockController.new, dispose: (d) => d.dispose());

  /// Create, delete, group, re-parent and clipboard operations.
  ///
  /// On the scope because everything that edits the scene wants it, the
  /// interface editor in its own window included.
  EntityOps get entities => _service(
    () => EntityOps(
      scope: this,
      world: () => world,
      sceneState: sceneState,
      camera: () => editorView,
      onChanged: sceneState.refresh,
    ),
  );

  /// The tile maps being edited: in the scene or in their own files, what
  /// has changed, saving. On the scope because tools, panels, the inspector
  /// and the save all reach it.
  LevelMapDocuments get mapDocs => _service(
    () => LevelMapDocuments(world: () => world, sceneState: sceneState),
    dispose: (d) => d.dispose(),
  );

  /// The tile tools' shared state: the map and layer being painted, the
  /// brush, the modes.
  TileEditState get tiles => _service(
    () => TileEditState(sceneState: sceneState, docs: mapDocs),
    dispose: (t) => t.dispose(),
  );

  /// Makes the scene's Level Map when something is first drawn on it.
  LevelMapProvision get mapProvision => _service(() => LevelMapProvision(this));

  /// Prefab files and their instances in the scene: placing, making again,
  /// Apply and Revert.
  PrefabInstances get prefabInstances =>
      _service(() => PrefabInstances(this), dispose: (p) => p.dispose());

  /// The project's asset files: scanned the first time it is asked for,
  /// then following the disk. Shared by the Assets dock and every panel
  /// that lists files (the 3-D designer's materials).
  AssetIndex get assetIndex => _service(
    () => AssetIndex(kinds: assetKinds)
      ..scan()
      ..startWatching(),
    dispose: (index) => index.dispose(),
  );

  T _service<T extends Object>(
    T Function() make, {
    void Function(T service)? dispose,
  }) {
    if (!container.isRegistered<T>()) {
      container.registerLazySingleton<T>(make, dispose: dispose);
    }
    return container.get<T>();
  }
}
