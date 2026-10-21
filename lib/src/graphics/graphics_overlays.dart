import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';

/// Draws the 3-D line from [a] to [b] in [context], in pieces so a line
/// passing behind the viewer keeps the part in front.
void _line(
  ViewportOverlayContext context,
  Vector3 a,
  Vector3 b,
  Paint paint, {
  int pieces = 8,
}) {
  Offset? last;
  final p = Vector3.zero();
  for (var k = 0; k <= pieces; k++) {
    final t = k / pieces;
    p.setValues(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
    );
    final at = context.project(p);
    if (at != null && last != null) context.canvas.drawLine(last, at, paint);
    last = at;
  }
}

/// The circle of [radius] about [centre] in the plane across [u] and [v]
/// (unit, square to each other), drawn where it is in front of the viewer.
void _circle(
  ViewportOverlayContext context,
  Vector3 centre,
  Vector3 u,
  Vector3 v,
  double radius,
  Paint paint,
) {
  const steps = 48;
  final run = <Offset>[];
  final p = Vector3.zero();
  for (var k = 0; k <= steps; k++) {
    final a = k / steps * math.pi * 2;
    final c = math.cos(a) * radius, s = math.sin(a) * radius;
    p.setValues(
      centre.x + u.x * c + v.x * s,
      centre.y + u.y * c + v.y * s,
      centre.z + u.z * c + v.z * s,
    );
    final at = context.project(p);
    if (at == null) {
      if (run.length > 1) {
        context.canvas.drawPoints(PointMode.polygon, run, paint);
      }
      run.clear();
    } else {
      run.add(at);
    }
  }
  if (run.length > 1) context.canvas.drawPoints(PointMode.polygon, run, paint);
}

/// Two unit vectors square to [axis] and to each other.
(Vector3, Vector3) _across(Vector3 axis) {
  final helper = axis.y.abs() < 0.9 ? Vector3(0, -1, 0) : Vector3(1, 0, 0);
  final u = axis.cross(helper)..normalize();
  final v = axis.cross(u)..normalize();
  return (u, v);
}

/// The way an entity faces: its forward (+Z) axis, turned by its rotation.
Vector3 _forwardOf(TransformComponent transform) {
  final q = Quaternion.identity();
  transform.rotationInto(q);
  final f = Vector3(0, 0, 1);
  q.rotate(f);
  return f..normalize();
}

/// Where a selected light reaches: a point light's range as three rings,
/// a spot's cone, a directional light's direction as an arrow.
final class LightReachOverlay extends ViewportOverlay {
  // How far a selected light reaches.
  @override
  GizmoKind get gizmoKind => GizmoKind.reach;

  @override
  String get id => 'graphics.lightReach';

  @override
  String get label => 'Light reach';

  @override
  Dimensions get dimensions => Dimensions.threeD;

  @override
  void paint(ViewportOverlayContext context) {
    for (final entity in context.world.query([
      TransformComponent,
      LightComponent,
    ])) {
      if (!context.isShown(entity) || !context.isSelected(entity)) continue;
      final light = entity.getComponent<LightComponent>()!;
      final transform = entity.getComponent<TransformComponent>()!;
      final at = Vector3.copy(transform.position);
      final colour = light.color.withValues(alpha: 1);
      final paint = Paint()
        ..color = Color.lerp(
          colour,
          const Color(0xFFFFFFFF),
          0.4,
        )!.withValues(alpha: 0.9)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      switch (light.kind) {
        case LightKind.point:
          final r = light.range > 0 ? light.range : 1.0;
          _circle(context, at, Vector3(1, 0, 0), Vector3(0, 0, 1), r, paint);
          _circle(context, at, Vector3(1, 0, 0), Vector3(0, 1, 0), r, paint);
          _circle(context, at, Vector3(0, 1, 0), Vector3(0, 0, 1), r, paint);
        case LightKind.spot:
          final f = _forwardOf(transform);
          final reach = light.range > 0 ? light.range : 5.0;
          final (u, v) = _across(f);
          for (final (angle, alpha) in [
            (light.outerConeAngle, 0.9),
            (light.innerConeAngle, 0.45),
          ]) {
            if (angle <= 0) continue;
            final radius = reach * math.tan(angle.clamp(0.0, 1.5));
            final end = at + f * reach;
            final ring = Paint()
              ..color = paint.color.withValues(alpha: alpha)
              ..strokeWidth = paint.strokeWidth
              ..style = PaintingStyle.stroke;
            _circle(context, end, u, v, radius, ring);
            if (alpha < 0.9) continue;
            for (final side in [u, -u, v, -v]) {
              _line(context, at, end + side * radius, ring);
            }
          }
        case LightKind.directional:
          final f = _forwardOf(transform);
          final (u, v) = _across(f);
          for (final offset in [
            Vector3.zero(),
            u * 0.3,
            -u * 0.3,
            v * 0.3,
            -v * 0.3,
          ]) {
            final start = at + offset;
            _line(context, start, start + f * 2, paint, pieces: 2);
          }
      }
    }
  }
}

/// What each selected virtual camera sees in a 3-D scene: a pyramid from
/// its eye, three metres deep, with a mark on its top edge.
final class CameraFrustumOverlay extends ViewportOverlay {
  // What a selected camera sees.
  @override
  GizmoKind get gizmoKind => GizmoKind.cameras;

  @override
  String get id => 'graphics.cameraFrustums';

  @override
  String get label => 'Camera frustums';

  @override
  Dimensions get dimensions => Dimensions.threeD;

  @override
  void paint(ViewportOverlayContext context) {
    final brain = context.scope.cameraBrain;
    if (brain == null) return;
    final paint = Paint()
      ..color = const Color(0xFF40E0D0)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final entity in context.world.query([
      TransformComponent,
      VirtualCameraComponent,
    ])) {
      if (!context.isShown(entity) || !context.isSelected(entity)) continue;
      final state = brain.stateOf(entity);
      if (state == null || state.lens.isOrthographic) continue;
      final corners = frustumCorners(
        state,
        depth: 3,
        aspect: _aspect(context.size),
      );
      final eye = Vector3(state.position.dx, state.position.dy, state.z);
      for (var i = 0; i < 4; i++) {
        _line(context, eye, corners[i], paint, pieces: 4);
        _line(context, corners[i], corners[(i + 1) % 4], paint, pieces: 4);
      }
      // A mark on the top edge, so which way is up reads at a glance.
      final top = (corners[0] + corners[1]) * 0.5;
      final up = (corners[0] - corners[3])..normalize();
      final width = corners[0].distanceTo(corners[1]);
      _line(
        context,
        corners[0] + (top - corners[0]) * 0.5,
        top + up * (width * 0.15),
        paint,
        pieces: 2,
      );
      _line(
        context,
        top + up * (width * 0.15),
        corners[1] + (top - corners[1]) * 0.5,
        paint,
        pieces: 2,
      );
    }
  }

  static double _aspect(Size size) =>
      size.height <= 0 ? 16 / 9 : size.width / size.height;

  /// The far corners of what a camera in [state] sees, [depth] metres out:
  /// top-left, top-right, bottom-right, bottom-left (up is -Y).
  static List<Vector3> frustumCorners(
    CameraState state, {
    double depth = 3,
    double aspect = 16 / 9,
  }) {
    final f = cameraForward(state.pitch, state.yaw);
    final r = Vector3(math.cos(state.yaw), 0, -math.sin(state.yaw));
    final u = r.cross(f)..normalize();
    final h = depth * math.tan(state.lens.safeFieldOfView / 2);
    final w = h * aspect;
    final centre =
        Vector3(state.position.dx, state.position.dy, state.z) + f * depth;
    return [
      centre + u * h - r * w,
      centre + u * h + r * w,
      centre - u * h + r * w,
      centre - u * h - r * w,
    ];
  }
}

/// Lights, marked where they are so a light can be found and picked.
final EditorMarker lightMarker = EditorMarker(
  id: 'light',
  components: const [LightComponent],
  icon: Icons.lightbulb_outline,
  color: const Color(0xFFFFD54F),
  label: (entity) => switch (entity.getComponent<LightComponent>()?.kind) {
    LightKind.directional => 'sun',
    LightKind.spot => 'spot',
    _ => null,
  },
);
