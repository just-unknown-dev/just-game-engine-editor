import 'package:flutter/material.dart';

import '../state/designer_geometry.dart';
import 'level_tool.dart';
import 'tool_registry.dart';

/// Measures a distance in world units.
///
/// Level design is full of questions like "can the player clear this gap?",
/// which are answered by a number, not by eyeballing. Jump reach is a fixed
/// distance; being able to check a gap against it turns guesswork into
/// arithmetic.
class MeasureTool extends LevelToolHandler {
  @override
  String get id => BuiltInTools.measure;

  @override
  String get label => 'Measure';

  @override
  IconData get icon => Icons.straighten;

  @override
  String? get shortcut => 'M';

  @override
  String? get description => 'Distance in world units — is that gap jumpable?';

  @override
  int get order => 90;

  Offset? _start;

  /// The measurement currently being dragged, for the painter to draw.
  ({Offset from, Offset to})? get measurement {
    final start = _start;
    final end = _end;
    if (start == null || end == null) return null;
    return (from: start, to: end);
  }

  Offset? _end;

  @override
  bool onPointerDown(ToolContext context) {
    _start = context.snapPoint(context.worldPosition);
    _end = _start;
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final start = _start;
    if (start == null) return;

    _end = context.snapPoint(context.worldPosition);
    final distance = DesignerGeometry.distance(start, _end!);
    final angle = DesignerGeometry.angleDegrees(start, _end!);
    final delta = _end! - start;

    context.controller.setStatus(
      '${distance.toStringAsFixed(1)} units  '
      '(dx ${delta.dx.toStringAsFixed(0)}, dy ${delta.dy.toStringAsFixed(0)})  '
      '${angle.toStringAsFixed(1)}°',
    );
  }

  @override
  void onPointerUp(ToolContext context) {
    // The measurement stays on screen after release so it can be read and
    // compared without having to hold the mouse button down.
  }

  @override
  void onCancel() {
    _start = null;
    _end = null;
  }

  /// Clears the displayed measurement.
  void clear() {
    _start = null;
    _end = null;
  }
}
