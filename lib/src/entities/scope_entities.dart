import 'package:just_editor_core/host.dart';

import 'entity_ops.dart';

/// The entity operations, on the scope they belong to: made the first time
/// they are asked for, in the scope's container, so they go with the scope
/// — whoever made it: the editor's plugin, or a test over a bare world.
extension ScopeEntities on EditorScope {
  /// Create, delete, group, re-parent and clipboard operations.
  ///
  /// On the scope because everything that edits the scene wants it, the
  /// interface editor in its own window included.
  EntityOps get entities => service(
    () => EntityOps(
      scope: this,
      world: () => world,
      sceneState: sceneState,
      camera: () => editorView,
      onChanged: sceneState.refresh,
    ),
  );
}
