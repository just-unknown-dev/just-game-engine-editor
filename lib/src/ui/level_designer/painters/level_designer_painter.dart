import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../overlays/designer_overlay.dart';
import '../state/level_designer_controller.dart';
import 'designer_canvas.dart';

/// Draws the Level Designer's overlays onto the game canvas.
///
/// This is now only a dispatcher: it builds the shared [DesignerCanvas] and
/// walks [OverlayRegistry] in paint order, skipping anything the author has
/// toggled off. What actually gets drawn is entirely a matter of which
/// overlays are registered, so a project's overlay is a first-class citizen
/// rather than something bolted onto a hardcoded list.
class LevelDesignerPainter {
  /// Paints every visible overlay, back to front.
  void paint(
    Canvas canvas,
    Size canvasSize,
    jge.Camera camera,
    jge.World world,
    LevelDesignerController controller,
    List<DesignerOverlay> overlays,
  ) {
    if (canvasSize.isEmpty) return;

    final context = OverlayPaintContext(
      draw: DesignerCanvas(canvas: canvas, size: canvasSize, camera: camera),
      world: world,
      controller: controller,
    );

    for (final overlay in overlays) {
      if (!controller.isOverlayVisible(overlay.id)) continue;
      overlay.paint(context);
    }
  }
}
