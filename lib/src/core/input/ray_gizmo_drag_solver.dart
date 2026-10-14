import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../ui/overlay/gizmo_painter.dart';
import '../state/editor_scene_state.dart';
import '../view/editor_view.dart';
import 'gizmo_drag_solver.dart';

/// Turns a drag of a 3-D gizmo handle into an edit, with rays.
///
/// - Moving along an axis follows the point on the axis nearest the
///   pointer's ray; in a plane, where the ray meets the plane.
/// - Turning about an axis follows the angle the pointer sweeps in the
///   ring's plane.
/// - Scaling along an axis follows how far along it the pointer is,
///   against where it started; [GizmoHandle.scaleUniform] by the pointer's
///   distance from the gizmo on screen.
///
/// Everything is measured from where the drag began, so snapping (metres,
/// degrees, scale steps; see [EditorSceneState.snapLength]) steps cleanly.
/// The axes are the world's (X, up, Z) or the entity's own while
/// [EditorSceneState.localGizmo] is on. Shift keeps a plane move to its
/// stronger axis.
class RayGizmoDragSolver implements GizmoDragSolver {
  /// A solver writing through [sceneState].
  RayGizmoDragSolver(this.sceneState);

  /// Where edits go.
  final EditorSceneState sceneState;

  final Vector3 _position = Vector3.zero();
  final Quaternion _rotation = Quaternion.identity();
  final Vector3 _scale = Vector3(1, 1, 1);
  Offset _screen = Offset.zero;
  List<Vector3> _axes = const [];
  final Ray3 _ray = Ray3();
  final Ray3 _startRay = Ray3();

  @override
  void begin(Entity entity, Offset screen) {
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    _position.setFrom(transform.position);
    transform.rotationInto(_rotation);
    _scale.setFrom(transform.scale);
    _screen = screen;
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
    if (_axes.isEmpty) return;
    view
      ..screenToRay(screen, _ray)
      ..screenToRay(_screen, _startRay);
    final axes = [
      for (var i = 0; i < 3; i++)
        if (handle.uses(1 << i)) i,
    ];
    switch (handle.op) {
      case GizmoOp.translate:
        final moved = axes.length == 1 ? _alongAxis(axes.single) : _inPlane(axes, constrain);
        if (moved != null) sceneState.setPosition3(entity, moved);
      case GizmoOp.rotate:
        final turned = _turned(axes.single, view, screen);
        if (turned != null) sceneState.setRotation3(entity, turned);
      case GizmoOp.scale:
        final scaled = handle == GizmoHandle.scaleUniform
            ? _scaledUniform(view, screen)
            : _scaledAlong(axes.single);
        if (scaled != null) sceneState.setScale3(entity, scaled);
      case GizmoOp.none:
        break;
    }
  }

  @override
  void end() => _axes = const [];

  Vector3? _alongAxis(int i) {
    final a = _axes[i];
    final s0 = closestAlong(_position, a, _startRay), s1 = closestAlong(_position, a, _ray);
    if (s0 == null || s1 == null) return null;
    final d = sceneState.snapLength(s1 - s0);
    return _position + a * d;
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
    return _position + a * da + b * db;
  }

  Quaternion? _turned(int i, EditorView view, Offset screen) {
    final a = _axes[i];
    final h0 = _hitPlane(_startRay, a), h1 = _hitPlane(_ray, a);
    double angle;
    if (h0 != null && h1 != null) {
      final v0 = h0 - _position, v1 = h1 - _position;
      angle = math.atan2(a.dot(v0.cross(v1)), v0.dot(v1));
    } else {
      // Seen edge-on: turn by how far the pointer went round on screen.
      final centre = view.projectToScreen(_position);
      if (centre == null) return null;
      final s0 = _screen - centre, s1 = screen - centre;
      angle = math.atan2(s1.dy, s1.dx) - math.atan2(s0.dy, s0.dx);
    }
    angle = sceneState.snapRotation(angle);
    return Quaternion.axisAngle(a, angle)..multiply(_rotation);
  }

  Vector3? _scaledAlong(int i) {
    final a = _axes[i];
    final s0 = closestAlong(_position, a, _startRay), s1 = closestAlong(_position, a, _ray);
    if (s0 == null || s1 == null || s0.abs() < 1e-6) return null;
    final out = Vector3.copy(_scale);
    final ratio = s1 / s0;
    switch (i) {
      case 0:
        out.x = sceneState.snapScale(_scale.x * ratio);
      case 1:
        out.y = sceneState.snapScale(_scale.y * ratio);
      default:
        out.z = sceneState.snapScale(_scale.z * ratio);
    }
    return out;
  }

  Vector3? _scaledUniform(EditorView view, Offset screen) {
    final centre = view.projectToScreen(_position);
    if (centre == null) return null;
    final d0 = (_screen - centre).distance;
    if (d0 < 1) return null;
    final ratio = (screen - centre).distance / d0;
    return Vector3(
      sceneState.snapScale(_scale.x * ratio),
      sceneState.snapScale(_scale.y * ratio),
      sceneState.snapScale(_scale.z * ratio),
    );
  }

  Vector3? _hitPlane(Ray3 ray, Vector3 normal) {
    final denom = normal.dot(ray.direction);
    if (denom.abs() < 1e-9) return null;
    final t = normal.dot(_position - ray.origin) / denom;
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
