import 'package:flutter/material.dart';

import 'package:just_editor_core/host.dart';
import '../tools/measure_tool.dart';
import 'built_in_overlays.dart';

/// Draws the measure tool's current readout.
///
/// A separate class rather than having [MeasureTool] implement
/// [DesignerOverlay] itself: both contracts define `order`, and they mean
/// different things — palette position versus paint depth. Splitting them
/// keeps each honest.
class MeasurementOverlay extends DesignerOverlay {
  MeasurementOverlay(this.tool);

  /// The tool whose measurement is being drawn.
  final MeasureTool tool;

  // What a tool in use draws: it stays with the gizmos hidden.
  @override
  GizmoKind? get gizmoKind => null;

  @override
  String get id => 'measurement';

  @override
  String get label => 'Measure';

  @override
  IconData get icon => Icons.straighten;

  @override
  int get order => OverlayOrder.measurement;

  @override
  void paint(OverlayPaintContext context) {
    final measurement = tool.measurement;
    if (measurement == null) return;

    final draw = context.draw;
    const color = OverlayColors.measurement;

    draw
      ..worldLine(measurement.from, measurement.to, color, strokeWidth: 2)
      ..worldDot(measurement.from, color, radius: 4)
      ..worldDot(measurement.to, color, radius: 4);

    final distance = DesignerGeometry.distance(
      measurement.from,
      measurement.to,
    );
    draw.label(
      Offset.lerp(
            draw.toScreen(measurement.from),
            draw.toScreen(measurement.to),
            0.5,
          )! +
          const Offset(8, -8),
      '${distance.toStringAsFixed(1)}u',
      color,
    );
  }
}
