import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../core/scope/editor_scope.dart';

/// Points a module lets the author drag in the viewport to edit the
/// selected entity: a polygon's corners, a shape's size.
///
/// The editor draws them over the selection, picks them before the
/// transform gizmo, and records each drag or click as one undo step of
/// whatever it changed in the handle's component.
abstract class ViewportHandles {
  /// Names it.
  String get id;

  /// Which scene modes it offers handles in.
  jge.Dimensions get dimensions => jge.Dimensions.threeD;

  /// The handles [entity] — selected, on its own — has now; empty for none.
  List<ViewportHandle> handlesOf(jge.Entity entity, EditorScope scope);
}

/// How a [ViewportHandle] is drawn.
enum ViewportHandleStyle {
  /// A point of the thing: a polygon's corner.
  point,

  /// Where a point can be added: a small "+" between two corners.
  add,

  /// A size: a diamond on a face.
  size,
}

/// One point the author can drag.
final class ViewportHandle {
  /// A handle at [position] editing [component] as [onDrag] says.
  const ViewportHandle({
    required this.position,
    required this.component,
    required this.onDrag,
    this.onClick,
    this.style = ViewportHandleStyle.point,
    this.tooltip,
  });

  /// Where it is, in the world.
  final jge.Vector3 position;

  /// What a drag or click changes: its saved fields are recorded for undo.
  final jge.Component component;

  /// Called as it is dragged; changes [component].
  final void Function(HandleDrag drag) onDrag;

  /// Called on a click without a drag ([HandleClick.alt] with Alt held) —
  /// adding the point a "+" stands for, removing a corner; null for none.
  final void Function(HandleClick click)? onClick;

  /// How it is drawn.
  final ViewportHandleStyle style;

  /// What hovering it says.
  final String? tooltip;
}

/// Where the pointer is in a drag of a [ViewportHandle].
final class HandleDrag {
  /// The pointer's [ray] in a drag that began with the handle at [start].
  HandleDrag({
    required this.ray,
    required this.start,
    required this.snap,
    required this.grid,
  });

  /// From the eye through the pointer, in the world.
  final jge.Ray3 ray;

  /// Where the handle was when the drag began, in the world.
  final jge.Vector3 start;

  /// Whether to snap (Ctrl held).
  final bool snap;

  /// The grid step to snap to.
  final double grid;

  /// Where [ray] meets the plane through [point] facing [normal], or null
  /// when it runs along it or away.
  jge.Vector3? onPlane(jge.Vector3 point, jge.Vector3 normal) {
    final d = ray.direction, o = ray.origin;
    final denom = d.dot(normal);
    if (denom.abs() < 1e-9) return null;
    final t = (point - o).dot(normal) / denom;
    if (t < 0) return null;
    return o + d * t;
  }

  /// How far along the line through [point] in [direction] (unit length)
  /// the point nearest [ray] is; null when they run side by side.
  double? alongLine(jge.Vector3 point, jge.Vector3 direction) {
    final d = ray.direction, w = ray.origin - point;
    final a = direction.dot(direction), b = direction.dot(d), c = d.dot(d);
    final e = direction.dot(w), f = d.dot(w);
    final denom = a * c - b * b;
    if (denom.abs() < 1e-9) return null;
    return (c * e - b * f) / denom;
  }

  /// [value] on the grid when snapping.
  double snapped(double value) => snap && grid > 0 ? (value / grid).roundToDouble() * grid : value;
}

/// A click on a [ViewportHandle] that did not drag.
final class HandleClick {
  /// A click, [alt] when Alt was held.
  const HandleClick({required this.alt});

  /// Whether Alt was held: remove rather than add.
  final bool alt;
}

/// Draws [handles] where [project] puts them; the one at [activeIndex] is
/// held.
void paintViewportHandles(
  Canvas canvas,
  List<ViewportHandle> handles,
  Offset? Function(jge.Vector3 world) project, {
  int activeIndex = -1,
}) {
  final fill = Paint()..color = const Color(0xFFFFFFFF);
  final held = Paint()..color = const Color(0xFFFFC107);
  final edge = Paint()
    ..color = const Color(0xFF1E1E1E)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  final faint = Paint()..color = const Color(0x99FFFFFF);
  for (final (i, handle) in handles.indexed) {
    final at = project(handle.position);
    if (at == null) continue;
    final active = i == activeIndex;
    final paint = active ? held : fill;
    switch (handle.style) {
      case ViewportHandleStyle.point:
        canvas
          ..drawCircle(at, 5, paint)
          ..drawCircle(at, 5, edge);
      case ViewportHandleStyle.add:
        canvas
          ..drawCircle(at, 4, active ? held : faint)
          ..drawLine(at - const Offset(2.5, 0), at + const Offset(2.5, 0), edge)
          ..drawLine(at - const Offset(0, 2.5), at + const Offset(0, 2.5), edge);
      case ViewportHandleStyle.size:
        final path = Path()
          ..moveTo(at.dx, at.dy - 6)
          ..lineTo(at.dx + 6, at.dy)
          ..lineTo(at.dx, at.dy + 6)
          ..lineTo(at.dx - 6, at.dy)
          ..close();
        canvas
          ..drawPath(path, paint)
          ..drawPath(path, edge);
    }
  }
}
