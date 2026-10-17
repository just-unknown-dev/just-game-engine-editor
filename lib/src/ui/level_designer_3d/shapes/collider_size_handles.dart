import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';

import 'package:just_editor_core/host.dart';
import 'face_handles.dart';

/// Size handles on a selected [Collider3D]'s faces — a solid's or a
/// trigger's: a box's width, height and depth, a ball's radius, a capsule's
/// or a cylinder's radius and height. The face opposite stays put (the
/// collider's offset moves); one undo step; Ctrl snaps to the move step.
///
/// Shown for a collider with nothing drawn on its entity — a trigger, an
/// invisible wall — and for every collider in the Collision view. A
/// collider matching its shape follows the shape's handles instead.
final class ColliderSizeHandles extends ViewportHandles {
  @override
  String get id => 'physics3d.colliderSize';

  @override
  List<ViewportHandle> handlesOf(Entity entity, EditorScope scope) {
    final collider = entity.getComponent<Collider3D>();
    final transform = entity.getComponent<TransformComponent>();
    if (collider == null || transform == null) return const [];
    final drawn = entity.components.any(
      (c) => scope.definitions.definitionFor(c)?.extent != null && c is! Collider3D,
    );
    if (drawn && scope.designer3D.viewMode.value != ViewMode3D.collision) {
      return const [];
    }
    final axes = axesOf(collider);
    if (axes.isEmpty) return const [];
    final body = Matrix4.identity();
    transform.localToWorldInto(body);
    final own = Matrix4.identity()
      ..setFromTrs(
        collider.offset,
        Quaternion.euler(collider.rotation.x, collider.rotation.y, collider.rotation.z),
        collider.scale,
      );
    final frame = Matrix4.identity()..setProduct(body, own);
    final bodyInverse = Matrix4.identity();
    if (bodyInverse.copyInverse(body) == 0) return const [];
    return FaceHandles.build(
      frame: frame,
      boundsOf: () => boundsOf(collider),
      axes: axes,
      moveTo: (origin) {
        final offset = Vector3.zero();
        bodyInverse.transformPointInto(origin, offset);
        collider.offset = offset;
      },
      component: collider,
      what: 'collider',
    );
  }

  /// [collider]'s box about its own origin, before its offset, turn and
  /// scale.
  static Aabb3 boundsOf(Collider3D collider) {
    final s = collider.naturalSize;
    return Aabb3()..setValues(-s.x / 2, -s.y / 2, -s.z / 2, s.x / 2, s.y / 2, s.z / 2);
  }

  /// How [collider]'s size is set along each of its axes; empty for a
  /// shape that is not sized by hand (a hull, a mesh, a height field, one
  /// matching its entity's shape).
  static List<FaceAxis> axesOf(Collider3D collider) => switch (collider.shape) {
    ColliderShape3D.box => [
      FaceAxis(0, (v) => collider.size = Vector3(v, collider.size.y, collider.size.z)),
      FaceAxis(1, (v) => collider.size = Vector3(collider.size.x, v, collider.size.z)),
      FaceAxis(2, (v) => collider.size = Vector3(collider.size.x, collider.size.y, v)),
    ],
    ColliderShape3D.sphere => [
      for (final a in const [0, 1, 2]) FaceAxis(a, (v) => collider.radius = v / 2),
    ],
    ColliderShape3D.capsule || ColliderShape3D.cylinder => [
      for (final a in const [0, 2]) FaceAxis(a, (v) => collider.radius = v / 2),
      FaceAxis(1, (v) => collider.height = v),
    ],
    _ => const [],
  };
}
