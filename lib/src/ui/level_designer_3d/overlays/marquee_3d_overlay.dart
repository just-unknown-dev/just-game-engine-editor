import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

/// The 3-D Select's marquee: the rectangle being dragged on the screen,
/// whatever is drawn under it.
class Marquee3DOverlay extends DesignerOverlay {
  @override
  String get id => 'designer3d.marquee';

  @override
  String get label => 'Marquee';

  @override
  IconData get icon => Icons.highlight_alt;

  @override
  jge.Dimensions get dimensions => jge.Dimensions.threeD;

  @override
  int get order => OverlayOrder.selection;

  @override
  void paint(OverlayPaintContext context) {
    final rect = context.controller.screenRect.value;
    if (rect == null) return;
    final canvas = context.draw.canvas;
    canvas
      ..drawRect(
        rect,
        Paint()..color = EditorTheme.primary.withValues(alpha: 0.12),
      )
      ..drawRect(
        rect,
        Paint()
          ..color = EditorTheme.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }
}
