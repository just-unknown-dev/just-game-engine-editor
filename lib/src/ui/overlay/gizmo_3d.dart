import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';
import 'gizmo_painter.dart';

/// X, Y and Z.
const List<Color> gizmoAxisColors = [Color(0xFFE5484D), Color(0xFF30A46C), Color(0xFF3E8EDE)];

const List<GizmoHandle> _moveHandles = [GizmoHandle.translateX, GizmoHandle.translateY, GizmoHandle.translateZ];
const List<GizmoHandle> _turnHandles = [GizmoHandle.rotateX, GizmoHandle.rotateY, GizmoHandle.rotate];
const List<GizmoHandle> _scaleHandles = [GizmoHandle.scaleX, GizmoHandle.scaleY, GizmoHandle.scaleZ];
const List<(int, int, GizmoHandle)> _planes = [
  (0, 1, GizmoHandle.translateXY),
  (0, 2, GizmoHandle.translateXZ),
  (1, 2, GizmoHandle.translateYZ),
];

/// Where a 3-D gizmo's handles are on screen for one entity, this frame.
///
/// The gizmo keeps a steady size on screen: its arms are [length] metres,
/// worked out from how big a metre looks where the entity is. Its axes are
/// the world's — X right, Y up (the engine's -Y), Z ahead — or the
/// entity's own ([local]). Anything behind the viewer is left out.
final class Gizmo3D {
  Gizmo3D._(this.view, this.position, this.origin, this.axes, this.length, this.tips);

  /// The gizmo of [entity] seen through [view], or null when it has no
  /// transform or sits behind the viewer. At [pivot] when given — the
  /// middle or the base of a selection — else at the entity.
  static Gizmo3D? of(
    Entity entity,
    EditorView view, {
    bool local = false,
    double pixels = 90,
    Vector3? pivot,
  }) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return null;
    Quaternion? turn;
    if (local) {
      turn = Quaternion.identity();
      transform.rotationInto(turn);
    }
    return at(pivot ?? transform.position, view, turn: turn, pixels: pixels);
  }

  /// A gizmo at [position] seen through [view], its axes the world's or
  /// turned by [turn]; null behind the viewer.
  static Gizmo3D? at(
    Vector3 position,
    EditorView view, {
    Quaternion? turn,
    double pixels = 90,
  }) {
    position = Vector3.copy(position);
    final origin = view.projectToScreen(position);
    if (origin == null) return null;
    final axes = [Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)];
    if (turn != null) {
      for (final a in axes) {
        turn.rotate(a);
      }
    }
    // How many pixels a metre spans here: the longest of the three axes.
    var perMetre = 0.0;
    for (final a in axes) {
      final p = view.projectToScreen(position + a);
      if (p != null) perMetre = math.max(perMetre, (p - origin).distance);
    }
    final length = perMetre > 1e-6 ? pixels / perMetre : 1.0;
    final tips = [for (final a in axes) view.projectToScreen(position + a * length)];
    return Gizmo3D._(view, position, origin, axes, length, tips);
  }

  /// The view it is seen through.
  final EditorView view;

  /// The entity's position.
  final Vector3 position;

  /// [position] on screen.
  final Offset origin;

  /// Its three axes in world space (unit length).
  final List<Vector3> axes;

  /// How long an arm is, metres.
  final double length;

  /// Where each arm ends on screen, or null behind the viewer.
  final List<Offset?> tips;

  /// The outer ring's radius on screen, pixels: it turns about the way the
  /// view looks.
  static const double viewRingRadius = 104;

  /// The ring turning about axis [i], as screen polylines (broken where
  /// it passes behind the viewer).
  List<List<Offset>> ring(int i) {
    final u = axes[(i + 1) % 3], v = axes[(i + 2) % 3];
    final radius = length * 0.85;
    final out = <List<Offset>>[];
    var run = <Offset>[];
    for (var k = 0; k <= 48; k++) {
      final a = k / 48 * 2 * math.pi;
      final p = view.projectToScreen(position + u * (math.cos(a) * radius) + v * (math.sin(a) * radius));
      if (p == null) {
        if (run.length > 1) out.add(run);
        run = <Offset>[];
      } else {
        run.add(p);
      }
    }
    if (run.length > 1) out.add(run);
    return out;
  }

  /// The small square for moving in the plane of axes [a] and [b], on
  /// screen; null when part of it is behind the viewer.
  List<Offset>? plane(int a, int b) {
    final near = length * 0.18, far = length * 0.38;
    final corners = [
      position + axes[a] * near + axes[b] * near,
      position + axes[a] * far + axes[b] * near,
      position + axes[a] * far + axes[b] * far,
      position + axes[a] * near + axes[b] * far,
    ];
    final out = <Offset>[];
    for (final c in corners) {
      final p = view.projectToScreen(c);
      if (p == null) return null;
      out.add(p);
    }
    return out;
  }

  /// The handle under [screen] for [mode], or [GizmoHandle.none].
  GizmoHandle handleAt(Offset screen, TransformMode mode) {
    const grab = 8.0;
    final moves = mode == TransformMode.move || mode == TransformMode.all;
    final turns = mode == TransformMode.rotate || mode == TransformMode.all;
    final scales = mode == TransformMode.scale || mode == TransformMode.all;
    if (scales && (screen - origin).distance <= grab) return GizmoHandle.scaleUniform;
    if (moves) {
      for (final (a, b, handle) in _planes) {
        final quad = plane(a, b);
        if (quad != null && _inQuad(screen, quad)) return handle;
      }
    }
    var best = GizmoHandle.none;
    var bestDistance = grab;
    for (var i = 0; i < 3; i++) {
      final tip = tips[i];
      if (tip == null) continue;
      final d = _toSegment(screen, origin, tip);
      if (d < bestDistance && (moves || (scales && mode == TransformMode.scale))) {
        bestDistance = d;
        best = moves ? _moveHandles[i] : _scaleHandles[i];
      }
    }
    if (best != GizmoHandle.none) return best;
    if (turns &&
        ((screen - origin).distance - viewRingRadius).abs() <= grab) {
      return GizmoHandle.rotateView;
    }
    if (turns) {
      for (var i = 0; i < 3; i++) {
        for (final run in ring(i)) {
          for (var k = 1; k < run.length; k++) {
            final d = _toSegment(screen, run[k - 1], run[k]);
            if (d < bestDistance) {
              bestDistance = d;
              best = _turnHandles[i];
            }
          }
        }
      }
    }
    return best;
  }

  static double _toSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final length2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (length2 < 1e-9) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / length2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  static bool _inQuad(Offset p, List<Offset> q) {
    // Same side of every edge (either winding).
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = q[i], b = q[(i + 1) % 4];
      final cross = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
      final s = cross > 0 ? 1 : (cross < 0 ? -1 : 0);
      if (s == 0) continue;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }
}

/// Draws [gizmo] for [mode]: arrows and plane squares to move, rings to
/// turn, boxes to scale; [active] (being dragged or hovered) in yellow.
void paintGizmo3D(
  Canvas canvas,
  Gizmo3D gizmo, {
  required TransformMode mode,
  GizmoHandle active = GizmoHandle.none,
}) {
  const highlight = Color(0xFFFFD43B);
  final moves = mode == TransformMode.move || mode == TransformMode.all;
  final turns = mode == TransformMode.rotate || mode == TransformMode.all;
  final scales = mode == TransformMode.scale || mode == TransformMode.all;
  Paint stroke(Color c, double w) => Paint()
    ..color = c
    ..strokeWidth = w
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  if (turns) {
    // The outer ring: a turn about the way the view looks.
    canvas.drawCircle(
      gizmo.origin,
      Gizmo3D.viewRingRadius,
      stroke(
        active == GizmoHandle.rotateView
            ? highlight
            : const Color(0xFFE6E6E6).withValues(alpha: 0.6),
        1.5,
      ),
    );
    for (var i = 0; i < 3; i++) {
      final paint = stroke(active == _turnHandles[i] ? highlight : gizmoAxisColors[i].withValues(alpha: 0.85), 2);
      for (final run in gizmo.ring(i)) {
        canvas.drawPoints(PointMode.polygon, run, paint);
      }
    }
  }
  if (moves) {
    for (final (a, b, handle) in _planes) {
      final quad = gizmo.plane(a, b);
      if (quad == null) continue;
      final colour = active == handle ? highlight : gizmoAxisColors[3 - a - b];
      final path = Path()..addPolygon(quad, true);
      canvas
        ..drawPath(path, Paint()..color = colour.withValues(alpha: 0.35))
        ..drawPath(path, stroke(colour, 1));
    }
  }
  for (var i = 0; i < 3; i++) {
    final tip = gizmo.tips[i];
    if (tip == null) continue;
    if (moves || (scales && mode == TransformMode.scale)) {
      final handle = moves ? _moveHandles[i] : _scaleHandles[i];
      final colour = active == handle ? highlight : gizmoAxisColors[i];
      canvas.drawLine(gizmo.origin, tip, stroke(colour, 2.5));
      final dir = tip - gizmo.origin;
      final length = dir.distance;
      if (length < 1e-6) continue;
      final unit = dir / length, side = Offset(-unit.dy, unit.dx);
      if (moves) {
        final head = Path()
          ..moveTo(tip.dx + unit.dx * 12, tip.dy + unit.dy * 12)
          ..lineTo(tip.dx + side.dx * 5, tip.dy + side.dy * 5)
          ..lineTo(tip.dx - side.dx * 5, tip.dy - side.dy * 5)
          ..close();
        canvas.drawPath(head, Paint()..color = colour);
      } else {
        canvas.drawRect(Rect.fromCenter(center: tip, width: 9, height: 9), Paint()..color = colour);
      }
    }
  }
  if (scales) {
    final colour = active == GizmoHandle.scaleUniform ? highlight : const Color(0xFFE6E6E6);
    canvas.drawRect(Rect.fromCenter(center: gizmo.origin, width: 10, height: 10), Paint()..color = colour);
  } else {
    canvas.drawCircle(gizmo.origin, 3, Paint()..color = const Color(0xFFE6E6E6));
  }
}

/// Hit-tests in 3-D: the selected entity's [Gizmo3D] handles first, then
/// the entity under the pointer by [picker] ([RayEntityPicker]).
class RayGizmoHitTester extends GizmoHitTester {
  /// A hit tester picking with [picker], with the gizmo in the entity's own
  /// axes while [local] says so.
  RayGizmoHitTester({
    EntityRayTestList? tests,
    bool Function()? local,
    this.pivot,
  }) : picker = RayEntityPicker(tests: tests),
       _local = local;

  /// Where the gizmo sits on the selection; the selected entity when null.
  final Vector3? Function()? pivot;

  /// What finds an entity under the pointer.
  final RayEntityPicker picker;

  final bool Function()? _local;

  @override
  GizmoHitResult hitTest(
    Offset screenPos,
    Entity? selected,
    List<Entity> entities,
    EditorView camera,
    Size canvasSize, {
    TransformMode mode = TransformMode.all,
    Set<TransformMode>? allows,
  }) {
    if (selected != null) {
      final gizmo = Gizmo3D.of(
        selected,
        camera,
        local: _local?.call() ?? false,
        pivot: pivot?.call(),
      );
      final handle = gizmo?.handleAt(screenPos, mode) ?? GizmoHandle.none;
      if (handle != GizmoHandle.none) return GizmoHitResult(handle, selected);
    }
    final entity = picker.pickAt(camera, screenPos, entities);
    return entity == null
        ? const GizmoHitResult(GizmoHandle.none, null)
        : GizmoHitResult(GizmoHandle.body, entity);
  }
}

/// Where the ray tests a picker uses come from (the scope's, which modules
/// add to).
typedef EntityRayTestList = List<EntityRayTest> Function();

/// The rectangle [entity]'s 3-D bounds cover on screen, or null when any
/// corner is behind the viewer.
Rect? screenBoundsOf3D(Entity entity, EditorView view) {
  final box = Aabb3();
  if (!RayEntityPicker.boundsOf(entity, box)) return null;
  double? left, top, right, bottom;
  for (var i = 0; i < 8; i++) {
    final p = view.projectToScreen(Vector3(
      i & 1 == 0 ? box.min.x : box.max.x,
      i & 2 == 0 ? box.min.y : box.max.y,
      i & 4 == 0 ? box.min.z : box.max.z,
    ));
    if (p == null) return null;
    left = math.min(left ?? p.dx, p.dx);
    top = math.min(top ?? p.dy, p.dy);
    right = math.max(right ?? p.dx, p.dx);
    bottom = math.max(bottom ?? p.dy, p.dy);
  }
  return Rect.fromLTRB(left!, top!, right!, bottom!);
}

/// The spacing a grid seen through [view] is drawn at near [at]: [step]
/// metres when its lines stay at least [minPixels] apart on screen there,
/// else the first of a metre, ten, a hundred… that does.
double gridSpacing(EditorView view, Vector3 at, double step, {double minPixels = 8}) {
  final base = step > 0 ? step : 1.0;
  final eye = view.projectToScreen(at);
  final aside = view.projectToScreen(Vector3(at.x + 1, at.y, at.z)) ??
      view.projectToScreen(Vector3(at.x, at.y, at.z + 1));
  if (eye == null || aside == null) return base;
  final perMetre = (aside - eye).distance;
  if (perMetre <= 0) return base;
  if (base * perMetre >= minPixels) return base;
  var spacing = base < 1 ? 1.0 : base * 10;
  while (spacing * perMetre < minPixels && spacing < 1e5) {
    spacing *= 10;
  }
  return spacing;
}

/// A grid on [plane] — the ground at y = 0 unless the 3-D designer moved
/// or turned it — around where [view] looks: a line every [spacing]
/// metres (see [gridSpacing]) for 50 lines each way, every metre or every
/// tenth line brighter, the axes in their colours. Lines passing behind the viewer are drawn
/// only where they are in front.
void paintPlaneGrid(
  Canvas canvas,
  EditorView view, {
  WorkingPlane plane = WorkingPlane.ground,
  double step = 1,
}) {
  // The plane's two directions, as world axes: (u, v).
  final (u, v) = switch (plane.axis) {
    WorkingPlaneAxis.ground => (0, 2),
    WorkingPlaneAxis.front => (0, 1),
    WorkingPlaneAxis.side => (2, 1),
  };
  Vector3 point(double a, double b) {
    final c = [0.0, 0.0, 0.0];
    c[plane.axis.axis] = plane.offset;
    c[u] = a;
    c[v] = b;
    return Vector3(c[0], c[1], c[2]);
  }

  final focus = view.focus;
  final f = [focus.x, focus.y, focus.z];
  final centre = point(f[u], f[v]);
  final spacing = gridSpacing(view, centre, step);
  const cells = 50;
  // Centred on a major line, so the bright lines stay put as the view
  // moves.
  final block = spacing < 1 ? 1.0 : spacing * 10;
  final cu = (f[u] / block).roundToDouble() * block;
  final cv = (f[v] / block).roundToDouble() * block;
  final minor = Paint()
    ..color = const Color(0x22FFFFFF)
    ..strokeWidth = 1;
  final major = Paint()
    ..color = const Color(0x44FFFFFF)
    ..strokeWidth = 1;
  // A line of constant u runs along v, and is the v axis where u is 0.
  Paint axis(int which) => Paint()
    ..color = gizmoAxisColors[which].withValues(alpha: 0.8)
    ..strokeWidth = 1.5;
  final alongV = axis(v), alongU = axis(u);
  void line(Vector3 a, Vector3 b, Paint paint) {
    // In pieces, so a line reaching behind the viewer keeps its front part.
    const pieces = 10;
    Offset? last;
    for (var k = 0; k <= pieces; k++) {
      final t = k / pieces;
      final p = view.projectToScreen(Vector3(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
      ));
      if (p != null && last != null) canvas.drawLine(last, p, paint);
      last = p;
    }
  }

  // Lines under a metre apart are brighter every metre; others every ten.
  final majorEvery = spacing < 1 ? math.max(1, (1 / spacing).round()) : 10;
  final half = cells * spacing;
  for (var i = -cells; i <= cells; i++) {
    final a = cu + i * spacing, b = cv + i * spacing;
    final isMajor = (i % majorEvery) == 0;
    final paintA = a.abs() < spacing / 2 ? alongV : (isMajor ? major : minor);
    final paintB = b.abs() < spacing / 2 ? alongU : (isMajor ? major : minor);
    line(point(a, cv - half), point(a, cv + half), paintA);
    line(point(cu - half, b), point(cu + half, b), paintB);
  }
}
