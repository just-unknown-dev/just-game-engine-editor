import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_editor_core/host.dart';
import 'built_in_audio_contributions.dart';

/// How far a selected 3-D sound carries: a ring at the distance it starts
/// to fade from full volume, and a fainter one where it falls silent — in
/// a 3-D scene three of each, round the three axes.
class AudioRangeOverlay extends ViewportOverlay {
  // How far a selected sound carries.
  @override
  GizmoKind get gizmoKind => GizmoKind.reach;

  @override
  String get id => 'audio.ranges';

  @override
  String get label => 'Sound ranges';

  @override
  void paint(ViewportOverlayContext context) {
    final near = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = BuiltInAudioContributions.color.withValues(alpha: 0.95);
    final far = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = BuiltInAudioContributions.color.withValues(alpha: 0.45);
    for (final entity in context.world.query([
      jge.TransformComponent,
      jge.AudioSourceComponent,
    ])) {
      if (!context.isShown(entity) || !context.isSelected(entity)) continue;
      final source = entity.getComponent<jge.AudioSourceComponent>()!;
      if (!source.is3D) continue;
      final centre = entity.getComponent<jge.TransformComponent>()!.position;
      final spatial = source.spatial;
      _rings(context, centre, spatial.minDistance, near);
      _rings(context, centre, spatial.maxDistance, far);
    }
  }

  static const int _steps = 48;

  /// Circles of [radius] round [centre]: one in the screen's plane in 2-D,
  /// one round each axis in 3-D.
  static void _rings(
    ViewportOverlayContext context,
    jge.Vector3 centre,
    double radius,
    Paint paint,
  ) {
    // Each plane by two of its axes, as (x, y, z).
    const xy = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0));
    const xz = ((1.0, 0.0, 0.0), (0.0, 0.0, 1.0));
    const yz = ((0.0, 1.0, 0.0), (0.0, 0.0, 1.0));
    final planes = context.view.isPlanar ? const [xy] : const [xy, xz, yz];
    final point = jge.Vector3.zero();
    for (final (u, v) in planes) {
      Offset? last;
      for (var i = 0; i <= _steps; i++) {
        final angle = i / _steps * 2 * math.pi;
        final c = math.cos(angle) * radius, s = math.sin(angle) * radius;
        point.setValues(
          centre.x + u.$1 * c + v.$1 * s,
          centre.y + u.$2 * c + v.$2 * s,
          centre.z + u.$3 * c + v.$3 * s,
        );
        final screen = context.project(point);
        // A point behind the viewer breaks the ring there.
        if (screen != null && last != null) {
          context.canvas.drawLine(last, screen, paint);
        }
        last = screen;
      }
    }
  }
}
