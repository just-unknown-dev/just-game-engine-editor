import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_editor_core/host.dart';
import 'built_in_lighting_2d_contributions.dart';

/// In a 2-D scene: how far a selected light reaches — a ring, and a spot's
/// cone — and the outline of a selected shadow caster.
class Light2DOverlay extends ViewportOverlay {
  // How far a selected light reaches.
  @override
  GizmoKind get gizmoKind => GizmoKind.reach;

  @override
  String get id => 'lighting.lights2D';

  @override
  String get label => '2-D light reach';

  @override
  void paint(ViewportOverlayContext context) {
    if (!context.view.isPlanar) return;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = BuiltInLighting2DContributions.color.withValues(alpha: 0.9);
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = BuiltInLighting2DContributions.color.withValues(alpha: 0.45);
    for (final entity in context.world.query([
      jge.TransformComponent,
      jge.Light2DComponent,
    ])) {
      if (!context.isShown(entity) || !context.isSelected(entity)) continue;
      final light = entity.getComponent<jge.Light2DComponent>()!;
      final t = entity.getComponent<jge.TransformComponent>()!;
      final centre = t.position;
      if (light.kind == jge.Light2DKind.spot) {
        final half = light.coneAngle * math.pi / 360;
        _arc(
          context,
          centre,
          light.radius,
          t.angle - half,
          t.angle + half,
          ring,
        );
        for (final a in [t.angle - half, t.angle + half]) {
          _line(context, centre, light.radius, a, ring);
        }
        _line(context, centre, light.radius, t.angle, faint);
      } else {
        _arc(context, centre, light.radius, 0, 2 * math.pi, ring);
      }
    }
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF90A4AE);
    for (final entity in context.world.query([
      jge.ShadowCaster2DComponent,
      jge.RenderableComponent,
    ])) {
      if (!context.isShown(entity) || !context.isSelected(entity)) continue;
      final renderable = entity
          .getComponent<jge.RenderableComponent>()!
          .renderable;
      var bounds = renderable.bounds;
      if (bounds == null) continue;
      if (!renderable.boundsAreWorldSpace) {
        bounds = bounds.shift(
          Offset(renderable.position.x, renderable.position.y),
        );
      }
      final corners = [
        bounds.topLeft,
        bounds.topRight,
        bounds.bottomRight,
        bounds.bottomLeft,
      ];
      Offset? first, last;
      for (final c in corners) {
        final p = context.project(jge.Vector3(c.dx, c.dy, 0));
        if (p == null) continue;
        first ??= p;
        if (last != null) context.canvas.drawLine(last, p, outline);
        last = p;
      }
      if (first != null && last != null) {
        context.canvas.drawLine(last, first, outline);
      }
    }
  }

  static const int _steps = 48;

  static void _arc(
    ViewportOverlayContext context,
    jge.Vector3 centre,
    double radius,
    double from,
    double to,
    Paint paint,
  ) {
    final point = jge.Vector3.zero();
    Offset? last;
    final steps = math.max(4, (_steps * (to - from) / (2 * math.pi)).ceil());
    for (var i = 0; i <= steps; i++) {
      final a = from + (to - from) * i / steps;
      point.setValues(
        centre.x + math.cos(a) * radius,
        centre.y + math.sin(a) * radius,
        0,
      );
      final screen = context.project(point);
      if (screen != null && last != null) {
        context.canvas.drawLine(last, screen, paint);
      }
      last = screen;
    }
  }

  static void _line(
    ViewportOverlayContext context,
    jge.Vector3 centre,
    double radius,
    double angle,
    Paint paint,
  ) {
    final from = context.project(centre);
    final to = context.project(
      jge.Vector3(
        centre.x + math.cos(angle) * radius,
        centre.y + math.sin(angle) * radius,
        0,
      ),
    );
    if (from != null && to != null) context.canvas.drawLine(from, to, paint);
  }
}
