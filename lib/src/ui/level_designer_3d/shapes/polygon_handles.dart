import 'dart:ui' show Offset;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';

import 'package:just_editor_core/host.dart';

/// A selected [Polygon3D]'s corners, on its top face, to drag along it —
/// Ctrl snaps to the grid. Between each two a "+": click it for a corner
/// there, or drag it to place one. Alt-click a corner to remove it (three
/// always stay).
final class PolygonHandles extends ViewportHandles {
  @override
  String get id => 'shapes.polygon';

  @override
  List<ViewportHandle> handlesOf(Entity entity, EditorScope scope) {
    final polygon = entity.getComponent<Primitive3D>();
    final transform = entity.getComponent<TransformComponent>();
    if (polygon is! Polygon3D || transform == null) return const [];
    final world = Matrix4.identity();
    transform.localToWorldInto(world);
    final inverse = Matrix4.identity();
    if (inverse.copyInverse(world) == 0) return const [];
    final top = -Primitive3D.size(polygon.height) / 2;

    Vector3 toWorld(Offset p) {
      final out = Vector3.zero();
      world.transformPointInto(Vector3(p.dx, top, p.dy), out);
      return out;
    }

    // The top face's plane, in the world.
    final origin = toWorld(Offset.zero);
    final up = Vector3.zero();
    world.transformDirectionInto(Vector3(0, -1, 0), up);
    if (up.lengthSquared == 0) return const [];
    up.normalize();

    /// Where the pointer is on the outline's plane, as a point of it.
    Offset? onOutline(HandleDrag drag) {
      final hit = drag.onPlane(origin, up);
      if (hit == null) return null;
      final local = Vector3.zero();
      inverse.transformPointInto(hit, local);
      return Offset(drag.snapped(local.x), drag.snapped(local.z));
    }

    void set(int index, Offset point) =>
        polygon.points = [...polygon.points]..[index] = point;

    final points = polygon.points;
    final n = points.length;
    return [
      for (var i = 0; i < n; i++)
        ViewportHandle(
          position: toWorld(points[i]),
          component: polygon,
          tooltip: 'Drag to move this corner; Alt-click to remove it',
          onDrag: (drag) {
            final p = onOutline(drag);
            if (p != null && i < polygon.points.length) set(i, p);
          },
          onClick: (click) {
            if (click.alt && polygon.points.length > 3) {
              polygon.points = [...polygon.points]..removeAt(i);
            }
          },
        ),
      for (var i = 0; i < n && n >= 2; i++)
        _between(polygon, i, toWorld, onOutline, set),
    ];
  }

  /// The "+" between corner [i] and the next: it becomes a corner when
  /// clicked or dragged.
  static ViewportHandle _between(
    Polygon3D polygon,
    int i,
    Vector3 Function(Offset p) toWorld,
    Offset? Function(HandleDrag drag) onOutline,
    void Function(int index, Offset point) set,
  ) {
    final points = polygon.points;
    final middle = (points[i] + points[(i + 1) % points.length]) / 2;
    var added = false;
    void add() {
      if (added) return;
      added = true;
      polygon.points = [...polygon.points]..insert(i + 1, middle);
    }

    return ViewportHandle(
      position: toWorld(middle),
      component: polygon,
      style: ViewportHandleStyle.add,
      tooltip: 'Click or drag for a corner here',
      onDrag: (drag) {
        add();
        final p = onOutline(drag);
        if (p != null) set(i + 1, p);
      },
      onClick: (_) => add(),
    );
  }
}
