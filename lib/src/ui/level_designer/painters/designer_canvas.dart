import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

/// Drawing helpers for everything painted onto the level designer's viewport.
///
/// All designer painting happens in **screen space**: the canvas handed to the
/// plugin's render hook has not had the camera transform applied, so every
/// world coordinate is converted here first. That is deliberate — it keeps
/// stroke widths, handle sizes and label text constant regardless of zoom, and
/// a selection outline that thins out as you zoom in is unusable.
///
/// Extensions get the same primitives the built-in overlays use, so a project's
/// overlay looks like it belongs rather than like it was bolted on.
class DesignerCanvas {
  DesignerCanvas({
    required this.canvas,
    required this.size,
    required this.camera,
  }) {
    // Set defensively on every construction: the game's own render pass may
    // have left a different viewport on the shared camera, and every
    // conversion below depends on it.
    camera.viewportSize = size;
  }

  /// The raw canvas, for anything these helpers do not cover.
  final Canvas canvas;

  /// Size of the viewport being drawn into.
  final Size size;

  /// Camera used for world/screen conversion.
  final jge.Camera camera;

  final Paint _stroke = Paint()..style = PaintingStyle.stroke;
  final Paint _fill = Paint()..style = PaintingStyle.fill;

  /// Converts a world point to screen space.
  Offset toScreen(Offset world) => camera.worldToScreen(world);

  /// Converts a screen point back to world space.
  Offset toWorld(Offset screen) => camera.screenToWorld(screen);

  /// Converts a world-space rectangle to screen space.
  Rect toScreenRect(Rect world) => Rect.fromPoints(
    camera.worldToScreen(world.topLeft),
    camera.worldToScreen(world.bottomRight),
  );

  /// Outlines a world-space rectangle.
  void strokeWorldRect(
    Rect world,
    Color color, {
    double strokeWidth = 1.5,
    double inflate = 0,
  }) {
    _stroke
      ..color = color
      ..strokeWidth = strokeWidth;
    canvas.drawRect(toScreenRect(world).inflate(inflate), _stroke);
  }

  /// Fills a world-space rectangle.
  void fillWorldRect(Rect world, Color color) {
    _fill.color = color;
    canvas.drawRect(toScreenRect(world), _fill);
  }

  /// Outlines a world-space rectangle with a dashed stroke.
  void dashWorldRect(Rect world, Color color, {double strokeWidth = 1}) {
    _stroke
      ..color = color
      ..strokeWidth = strokeWidth;
    final rect = toScreenRect(world);
    dashedLine(rect.topLeft, rect.topRight, _stroke);
    dashedLine(rect.topRight, rect.bottomRight, _stroke);
    dashedLine(rect.bottomRight, rect.bottomLeft, _stroke);
    dashedLine(rect.bottomLeft, rect.topLeft, _stroke);
  }

  /// Draws a line between two world points.
  void worldLine(
    Offset from,
    Offset to,
    Color color, {
    double strokeWidth = 1.5,
  }) {
    _stroke
      ..color = color
      ..strokeWidth = strokeWidth;
    canvas.drawLine(toScreen(from), toScreen(to), _stroke);
  }

  /// Draws a filled dot at a world point, sized in *screen* pixels so it stays
  /// grabbable at any zoom.
  void worldDot(Offset world, Color color, {double radius = 5}) {
    _fill.color = color;
    canvas.drawCircle(toScreen(world), radius, _fill);
  }

  /// Draws a dashed line between two screen points.
  void dashedLine(Offset from, Offset to, Paint paint) {
    const dash = 8.0;
    const gap = 6.0;
    final total = (to - from).distance;
    if (total <= 0) return;
    final direction = (to - from) / total;

    var travelled = 0.0;
    while (travelled < total) {
      final end = (travelled + dash).clamp(0.0, total);
      canvas.drawLine(
        from + direction * travelled,
        from + direction * end,
        paint,
      );
      travelled = end + gap;
    }
  }

  /// Draws a text label at a *screen* position.
  ///
  /// Shadowed rather than boxed: a label over busy level geometry has to stay
  /// readable without covering what it is labelling.
  void label(
    Offset screenPosition,
    String text,
    Color color, {
    double fontSize = 11,
  }) {
    TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..paint(canvas, screenPosition);
  }

  /// Draws a text label anchored to a world position.
  void worldLabel(
    Offset world,
    String text,
    Color color, {
    Offset screenOffset = const Offset(0, -18),
    double fontSize = 11,
  }) => label(toScreen(world) + screenOffset, text, color, fontSize: fontSize);
}
