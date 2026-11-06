import 'package:just_editor_core/host.dart';

import 'prefab_instances.dart';

/// Prefab files and their instances, on the scope they belong to: made the
/// first time they are asked for, in the scope's container, so they are
/// disposed with the scope.
extension ScopePrefabs on EditorScope {
  /// Prefab files and their instances in the scene: placing, making again,
  /// Apply and Revert.
  PrefabInstances get prefabInstances =>
      service(() => PrefabInstances(this), dispose: (p) => p.dispose());
}
