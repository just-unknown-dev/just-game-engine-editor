import 'dart:ui' show Offset;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';

import 'package:just_editor_core/host.dart';
import 'face_handles.dart';

/// Size handles on a selected 3-D shape's faces: pull a face and the shape
/// grows or shrinks that way while the face opposite stays put — its
/// width, height or depth; a ball's or a cylinder's radius; a ring's
/// size and thickness; an arch's span; a polygon's height and spread. One
/// undo step of the shape and where its entity stands; Ctrl snaps to the
/// move step. Off in the Collision view, where the colliders' are.
final class ShapeSizeHandles extends ViewportHandles {
  @override
  String get id => 'shapes.size';

  @override
  List<ViewportHandle> handlesOf(Entity entity, EditorScope scope) {
    final shape = entity.getComponent<Primitive3D>();
    final transform = entity.getComponent<TransformComponent>();
    if (shape == null || transform == null) return const [];
    if (scope.designer3D.viewMode.value == ViewMode3D.collision) return const [];
    final axes = axesOf(shape);
    if (axes.isEmpty) return const [];
    final frame = Matrix4.identity();
    transform.localToWorldInto(frame);
    return FaceHandles.build(
      frame: frame,
      boundsOf: () => Aabb3()..also(shape.boundsInto),
      axes: axes,
      moveTo: (origin) => scope.sceneState.setPosition3(entity, origin),
      component: shape,
      alsoEdits: [transform],
      what: shape.runtimeType.toString(),
    );
  }

  /// How [shape]'s size is set along each of its axes; empty for a shape
  /// it does not know.
  static List<FaceAxis> axesOf(Primitive3D shape) {
    FaceAxis axis(int a, double Function() get, void Function(double v) set) =>
        FaceAxis(a, set);
    // A round shape's radius, from its size across.
    List<FaceAxis> across(double Function() radius, void Function(double r) set) => [
      for (final a in const [0, 2]) axis(a, () => radius() * 2, (v) => set(v / 2)),
    ];
    return switch (shape) {
      Cube3D s => [
        axis(0, () => s.width, (v) => s.width = v),
        axis(1, () => s.height, (v) => s.height = v),
        axis(2, () => s.depth, (v) => s.depth = v),
      ],
      Ramp3D s => [
        axis(0, () => s.width, (v) => s.width = v),
        axis(1, () => s.height, (v) => s.height = v),
        axis(2, () => s.depth, (v) => s.depth = v),
      ],
      Stairs3D s => [
        axis(0, () => s.width, (v) => s.width = v),
        axis(1, () => s.height, (v) => s.height = v),
        axis(2, () => s.depth, (v) => s.depth = v),
      ],
      Plane3D s => [
        axis(0, () => s.width, (v) => s.width = v),
        axis(2, () => s.depth, (v) => s.depth = v),
      ],
      Sphere3D s => [
        for (final a in const [0, 1, 2])
          axis(a, () => s.radius * 2, (v) => s.radius = v / 2),
      ],
      Cylinder3D s => [
        ...across(() => s.radius, (r) => s.radius = r),
        axis(1, () => s.height, (v) => s.height = v),
      ],
      Cone3D s => [
        ...across(() => s.radius, (r) => s.radius = r),
        axis(1, () => s.height, (v) => s.height = v),
      ],
      Capsule3D s => [
        ...across(() => s.radius, (r) => s.radius = r),
        axis(1, () => s.height, (v) => s.height = v),
      ],
      // Across: the ring's size, its tube kept; up: the tube.
      Torus3D s => [
        for (final a in const [0, 2])
          axis(
            a,
            () => (s.radius + s.tubeRadius) * 2,
            (v) => s.radius = (v / 2 - s.tubeRadius).clamp(0.01, double.infinity),
          ),
        axis(1, () => s.tubeRadius * 2, (v) => s.tubeRadius = v / 2),
      ],
      // Across and up: the whole arch, in proportion; along: its depth.
      Arch3D s => [
        for (final a in const [0, 1])
          axis(a, () => _extentOf(s, a), (v) {
            final ratio = v / _extentOf(s, a);
            s
              ..radius *= ratio
              ..thickness *= ratio;
          }),
        axis(2, () => s.depth, (v) => s.depth = v),
      ],
      // Across: its outline spread or drawn in; up: its height.
      Polygon3D s => [
        for (final a in const [0, 2])
          axis(a, () => _extentOf(s, a), (v) {
            final ratio = v / _extentOf(s, a);
            final box = Aabb3()..also(s.boundsInto);
            final mid = a == 0 ? (box.min.x + box.max.x) / 2 : (box.min.z + box.max.z) / 2;
            s.points = [
              for (final p in s.points)
                a == 0
                    ? Offset(mid + (p.dx - mid) * ratio, p.dy)
                    : Offset(p.dx, mid + (p.dy - mid) * ratio),
            ];
          }),
        axis(1, () => s.height, (v) => s.height = v),
      ],
      _ => const [],
    };
  }

  static double _extentOf(Primitive3D shape, int axis) {
    final box = Aabb3()..also(shape.boundsInto);
    final e = switch (axis) {
      0 => box.max.x - box.min.x,
      1 => box.max.y - box.min.y,
      _ => box.max.z - box.min.z,
    };
    return e <= 1e-9 ? 1e-9 : e;
  }
}

extension on Aabb3 {
  /// Filled by [fill].
  void also(void Function(Aabb3 out) fill) => fill(this);
}
