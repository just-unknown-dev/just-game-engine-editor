import 'package:just_editor_core/host.dart';

import 'level_map_documents.dart';
import 'level_map_provision.dart';
import 'tile_edit_state.dart';

/// The Level Map's services, on the scope they belong to: each made the
/// first time it is asked for, in the scope's container, so it is disposed
/// with the scope — whoever made it: the editor's plugin, or a test.
extension ScopeLevelMaps on EditorScope {
  /// The tile maps being edited: in the scene or in their own files, what
  /// has changed, saving. On the scope because tools, panels, the inspector
  /// and the save all reach it.
  LevelMapDocuments get mapDocs => service(
    () => LevelMapDocuments(
      world: () => world,
      sceneState: sceneState,
      projectRoot: projectRoot,
    ),
    dispose: (d) => d.dispose(),
  );

  /// The tile tools' shared state: the map and layer being painted, the
  /// brush, the modes.
  TileEditState get tiles => service(
    () => TileEditState(sceneState: sceneState, docs: mapDocs),
    dispose: (t) => t.dispose(),
  );

  /// Makes the scene's Level Map when something is first drawn on it.
  LevelMapProvision get mapProvision => service(() => LevelMapProvision(this));
}
