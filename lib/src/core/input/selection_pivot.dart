import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';

/// Where the 3-D gizmo sits on a selection ([PivotMode3D]): the middle of
/// its box, the first thing's own origin, or the middle of its box's
/// bottom (+Y is down: the largest Y).
abstract final class SelectionPivot {
  /// [entities]' pivot for [mode]; the origin when there is nothing.
  static Vector3 of(List<Entity> entities, PivotMode3D mode) {
    if (entities.isEmpty) return Vector3.zero();
    if (mode == PivotMode3D.pivot) {
      final t = entities.first.getComponent<TransformComponent>();
      if (t != null) return Vector3.copy(t.position);
    }
    final box = Aabb3(), one = Aabb3();
    for (final e in entities) {
      if (RayEntityPicker.boundsOf(e, one)) box.addBox(one);
    }
    if (box.isEmpty) {
      final t = entities.first.getComponent<TransformComponent>();
      return t == null ? Vector3.zero() : Vector3.copy(t.position);
    }
    final centre = Vector3.zero();
    box.centerInto(centre);
    if (mode == PivotMode3D.base) centre.y = box.max.y;
    return centre;
  }
}
