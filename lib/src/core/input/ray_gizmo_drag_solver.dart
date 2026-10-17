import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../ui/overlay/gizmo_painter.dart';
import 'package:just_editor_core/host.dart';
import 'gizmo_drag_solver.dart';

/// Turns a drag of a 3-D gizmo handle into an edit, with rays.
///
/// - Moving along an axis follows the point on the axis nearest the
///   pointer's ray; in a plane, where the ray meets the plane.
/// - Turning about an axis follows the angle the pointer sweeps in the
///   ring's plane; [GizmoHandle.rotateView] turns about the way the view
///   looks, by the angle swept on screen.
/// - Scaling along an axis follows how far along it the pointer is,
///   against where it started; [GizmoHandle.scaleUniform] by the pointer's
///   distance from the gizmo on screen.
///
/// It edits every target it was begun with ([beginMany]) about one
/// pivot — the gizmo's — so several selected things move, turn and scale
/// together. Everything is measured from where the drag began, so snapping
/// (metres, degrees, scale steps; see [EditorSceneState.snapLength]) steps
/// cleanly, and a value typed while dragging ([exact]) sets the change
/// outright. The axes are the world's (X, up, Z) or the first target's own
/// while [EditorSceneState.localGizmo] is on. Shift keeps a plane move to
/// its stronger axis.
class RayGizmoDragSolver implements GizmoDragSolver {
  /// A solver writing through [sceneState].
  RayGizmoDragSolver(this.sceneState);

  /// Where edits go.
  final EditorSceneState sceneState;

  /// What a move's change becomes before it is applied: where snapping to
  /// surfaces, corners and boxes takes over. Given the change and the
  /// pointer's ray; null leaves it.
  Vector3 Function(Vector3 delta, Ray3 ray, Offset screen)? adjustMove;

  /// A value typed while dragging: metres for a move along one axis,
  /// degrees for a turn, a factor for a scale. Null follows the pointer.
  double? exact;

  // The pivot the gizmo sits on, and the first target's turn (its axes).
  final Vector3 _pivot = Vector3.zero();
  final Quaternion _rotation = Quaternion.identity();
  Offset _screen = Offset.zero;
  List<Vector3> _axes = const [];
  final Ray3 _ray = Ray3();
  final Ray3 _startRay = Ray3();
  final List<_Start> _targets = [];

  /// The pivot the drag turns and scales about.
  Vector3 get pivot => Vector3.copy(_pivot);

  /// What the drag edits.
  List<Entity> get targets => [for (final t in _targets) t.entity];

  @override
  void begin(Entity entity, Offset screen) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    beginMany([entity], transform.position, screen);
  }

  /// A drag of the gizmo of [entities], sitting on [pivot], begins at
  /// [screen]. The first entity's turn gives the gizmo's own axes.
  void beginMany(List<Entity> entities, Vector3 pivot, Offset screen) {
    _targets.clear();
    for (final e in entities) {
      final t = e.getComponent<TransformComponent>();
      if (t == null) continue;
      final q = Quaternion.identity();
      t.rotationInto(q);
      _targets.add(_Start(e, Vector3.copy(t.position), q, Vector3.copy(t.scale)));
    }
    if (_targets.isEmpty) return;
    _pivot.setFrom(pivot);
    _rotation.setFrom(_targets.first.rotation);
    _screen = screen;
    exact = null;
    _axes = [Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)];
    if (sceneState.localGizmo) {
      for (final a in _axes) {
        _rotation.rotate(a);
      }
    }
  }

  @override
  void update(
    GizmoHandle handle,
    Entity entity,
    Offset screen,
    EditorView view, {
    bool constrain = false,
  }) {
    if (_axes.isEmpty || _targets.isEmpty) return;
    view
      ..screenToRay(screen, _ray)
      ..screenToRay(_screen, _startRay);
    final axes = [
      for (var i = 0; i < 3; i++)
        if (handle.uses(1 << i)) i,
    ];
    switch (handle.op) {
      case GizmoOp.translate:
        var delta = axes.length == 1
            ? _alongAxis(axes.single)
            : _inPlane(axes, constrain);
        if (delta == null) return;
        delta = adjustMove?.call(delta, _ray, screen) ?? delta;
        for (final t in _targets) {
          sceneState.setPosition3(t.entity, t.position + delta);
        }
      case GizmoOp.rotate:
        final turn = handle == GizmoHandle.rotateView
            ? _turnedOnScreen(view, screen)
            : _turned(axes.single, view, screen);
        if (turn == null) return;
        for (final t in _targets) {
          final offset = t.position - _pivot;
          turn.rotate(offset);
          sceneState
            ..setPosition3(t.entity, _pivot + offset)
            ..setRotation3(t.entity, Quaternion.copy(turn)..multiply(t.rotation));
        }
      case GizmoOp.scale:
        final ratio = handle == GizmoHandle.scaleUniform
            ? _ratioUniform(view, screen)
            : _ratioAlong(axes.single);
        if (ratio == null) return;
        final axis = handle == GizmoHandle.scaleUniform ? null : axes.single;
        for (final t in _targets) {
          final scaled = Vector3.copy(t.scale);
          final v = t.position - _pivot;
          if (axis == null) {
            scaled
              ..x = sceneState.snapScale(t.scale.x * ratio)
              ..y = sceneState.snapScale(t.scale.y * ratio)
              ..z = sceneState.snapScale(t.scale.z * ratio);
            v.scale(ratio);
          } else {
            switch (axis) {
              case 0:
                scaled.x = sceneState.snapScale(t.scale.x * ratio);
              case 1:
                scaled.y = sceneState.snapScale(t.scale.y * ratio);
              default:
                scaled.z = sceneState.snapScale(t.scale.z * ratio);
            }
            // Spread apart along the axis as their sizes grow.
            final a = _axes[axis];
            v.add(a * (v.dot(a) * (ratio - 1)));
          }
          sceneState.setScale3(t.entity, scaled);
          if (_targets.length > 1) sceneState.setPosition3(t.entity, _pivot + v);
        }
      case GizmoOp.none:
        break;
    }
  }

  @override
  void end() {
    _axes = const [];
    _targets.clear();
    exact = null;
  }

  /// How far the pivot moves along axis [i]: where the pointer's ray
  /// passes nearest the axis, against where it began; [exact] metres when
  /// typed.
  Vector3? _alongAxis(int i) {
    final a = _axes[i];
    final typed = exact;
    if (typed != null) return a * typed;
    final s0 = closestAlong(_pivot, a, _startRay), s1 = closestAlong(_pivot, a, _ray);
    if (s0 == null || s1 == null) return null;
    return a * sceneState.snapLength(s1 - s0);
  }

  Vector3? _inPlane(List<int> axes, bool constrain) {
    final a = _axes[axes[0]], b = _axes[axes[1]];
    final normal = a.cross(b)..normalize();
    final h0 = _hitPlane(_startRay, normal), h1 = _hitPlane(_ray, normal);
    if (h0 == null || h1 == null) return null;
    final delta = h1 - h0;
    var da = sceneState.snapLength(delta.dot(a));
    var db = sceneState.snapLength(delta.dot(b));
    if (constrain) {
      if (da.abs() >= db.abs()) {
        db = 0;
      } else {
        da = 0;
      }
    }
    return a * da + b * db;
  }

  /// The turn about axis [i] the pointer has made: the angle it swept in
  /// the ring's plane; [exact] degrees when typed.
  Quaternion? _turned(int i, EditorView view, Offset screen) {
    final a = _axes[i];
    final typed = exact;
    double angle;
    if (typed != null) {
      angle = typed * math.pi / 180;
    } else {
      final h0 = _hitPlane(_startRay, a), h1 = _hitPlane(_ray, a);
      if (h0 != null && h1 != null) {
        final v0 = h0 - _pivot, v1 = h1 - _pivot;
        angle = math.atan2(a.dot(v0.cross(v1)), v0.dot(v1));
      } else {
        // Seen edge-on: turn by how far the pointer went round on screen.
        final centre = view.projectToScreen(_pivot);
        if (centre == null) return null;
        final s0 = _screen - centre, s1 = screen - centre;
        angle = math.atan2(s1.dy, s1.dx) - math.atan2(s0.dy, s0.dx);
      }
      angle = sceneState.snapRotation(angle);
    }
    return Quaternion.axisAngle(a, angle);
  }

  /// The turn about the way the view looks: the angle swept on screen
  /// round the gizmo, clockwise as seen.
  Quaternion? _turnedOnScreen(EditorView view, Offset screen) {
    final centre = view.projectToScreen(_pivot);
    if (centre == null) return null;
    // The way the view looks: from the eye through the pivot.
    final through = view.screenToRay(centre);
    final axis = Vector3.copy(through.direction)..normalize();
    final typed = exact;
    double angle;
    if (typed != null) {
      angle = typed * math.pi / 180;
    } else {
      final s0 = _screen - centre, s1 = screen - centre;
      angle = sceneState.snapRotation(
        math.atan2(s1.dy, s1.dx) - math.atan2(s0.dy, s0.dx),
      );
    }
    return Quaternion.axisAngle(axis, angle);
  }

  double? _ratioAlong(int i) {
    final typed = exact;
    if (typed != null) return typed;
    final a = _axes[i];
    final s0 = closestAlong(_pivot, a, _startRay), s1 = closestAlong(_pivot, a, _ray);
    if (s0 == null || s1 == null || s0.abs() < 1e-6) return null;
    return s1 / s0;
  }

  double? _ratioUniform(EditorView view, Offset screen) {
    final typed = exact;
    if (typed != null) return typed;
    final centre = view.projectToScreen(_pivot);
    if (centre == null) return null;
    final d0 = (_screen - centre).distance;
    if (d0 < 1) return null;
    return (screen - centre).distance / d0;
  }

  Vector3? _hitPlane(Ray3 ray, Vector3 normal) {
    final denom = normal.dot(ray.direction);
    if (denom.abs() < 1e-9) return null;
    final t = normal.dot(_pivot - ray.origin) / denom;
    if (t < 0) return null;
    return ray.origin + ray.direction * t;
  }

  /// How far along the line through [point] in [direction] the point
  /// nearest [ray] is, or null when they run parallel.
  static double? closestAlong(Vector3 point, Vector3 direction, Ray3 ray) {
    final w0 = point - ray.origin;
    final a = direction.dot(direction), b = direction.dot(ray.direction), c = ray.direction.dot(ray.direction);
    final d = direction.dot(w0), e = ray.direction.dot(w0);
    final denom = a * c - b * b;
    if (denom.abs() < 1e-12) return null;
    return (b * e - c * d) / denom;
  }
}

/// A target's transform when the drag began.
final class _Start {
  _Start(this.entity, this.position, this.rotation, this.scale);

  final Entity entity;
  final Vector3 position;
  final Quaternion rotation;
  final Vector3 scale;
}
