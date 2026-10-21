import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

/// Draws the Level Designer's overlays onto the game canvas.
///
/// This is now only a dispatcher: it builds the shared [DesignerCanvas] and
/// walks [OverlayRegistry] in paint order, skipping anything [isDrawn] says
/// is not: toggled off by the author, or a gizmo of a kind not shown.
/// What actually gets drawn is entirely a matter of which overlays are
/// registered, so a project's overlay is a first-class citizen rather than
/// something bolted onto a hardcoded list.
class LevelDesignerPainter {
  /// Paints every overlay [isDrawn] lets through, back to front.
  void paint(
    Canvas canvas,
    Size canvasSize,
    EditorView camera,
    jge.World world,
    LevelDesignerController controller,
    List<DesignerOverlay> overlays, {
    required bool Function(DesignerOverlay overlay) isDrawn,
    bool Function(GizmoKind kind)? showsGizmo,
  }) {
    if (canvasSize.isEmpty) return;

    final context = OverlayPaintContext(
      draw: DesignerCanvas(canvas: canvas, size: canvasSize, camera: camera),
      world: world,
      controller: controller,
      showsGizmo: showsGizmo ?? (_) => true,
    );

    for (final overlay in overlays) {
      if (!isDrawn(overlay)) continue;
      overlay.paint(context);
    }
  }
}
