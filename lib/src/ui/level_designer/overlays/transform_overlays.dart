import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import '../../overlay/transform_gizmo.dart';
import 'built_in_overlays.dart';

/// The selection's gizmo, as the Move, Scale and Rotate toolbar says:
/// arrows at its centre, the resize handles on its bounds, or a ring
/// around it.
///
/// Drawn only while the select tool is active — the only tool that responds
/// to them — and at the positions [SelectTool] hit-tests, in screen pixels so
/// they stay the same size at any zoom.
class SelectionHandlesOverlay extends DesignerOverlay {
  SelectionHandlesOverlay([this.layout = const SelectionHandleLayout()]);

  /// Where the knob and handles sit; the scope's, shared with the tool.
  final SelectionHandleLayout layout;

  @override
  String get id => 'selectionHandles';

  @override
  String get label => 'Transform handles';

  @override
  IconData get icon => Icons.open_with;

  @override
  int get order => OverlayOrder.selection + 10;

  @override
  void paint(OverlayPaintContext context) {
    if (context.controller.toolId.value != BuiltInTools.select) return;
    final entities = _selection(context);
    if (entities.isEmpty) return;
    final bounds = _bounds(entities);
    if (bounds == null) return;

    final draw = context.draw;
    final screen = draw.toScreenRect(bounds);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = OverlayColors.selection;
    draw.canvas.drawRect(screen, stroke);

    final centre = draw.toScreen(bounds.center);
    final available = TransformModes.forEntities(context.world, entities);
    final mode = TransformModes.shown(
      context.controller.view.transformMode.value,
      available,
    );
    final unitsPerPixel = 1 / draw.camera.zoom;
    switch (mode) {
      case TransformMode.all:
        // As it always was: a knob on a short stem above the top edge, and
        // the resize handles — what the selection can take.
        if (available.contains(TransformMode.rotate)) {
          final knob = draw.toScreen(
            layout.rotateKnobAt(bounds, unitsPerPixel),
          );
          draw.canvas
            ..drawLine(Offset(screen.center.dx, screen.top), knob, stroke)
            ..drawCircle(knob, 5, Paint()..color = Colors.white)
            ..drawCircle(knob, 5, stroke);
        }
        if (!available.contains(TransformMode.scale) ||
            bounds.width <= 0 ||
            bounds.height <= 0) {
          return;
        }
        _paintHandles(draw, bounds, stroke);
      case TransformMode.move:
        TransformGizmo.paintMove(draw.canvas, centre);
      case TransformMode.scale:
        // A point marker has nothing to resize.
        if (bounds.width <= 0 || bounds.height <= 0) return;
        _paintHandles(draw, bounds, stroke);
      case TransformMode.rotate:
        final zoom = draw.camera.zoom;
        // One thing shows which way it is turned; several, no one way.
        final angle = entities.length == 1
            ? entities.single.getComponent<jge.TransformComponent>()?.angle ??
                  0.0
            : 0.0;
        TransformGizmo.paintRotate(
          draw.canvas,
          centre,
          layout.ringRadius(bounds, 1 / zoom) * zoom,
          angle: angle,
        );
      case null:
        break;
    }
  }

  static void _paintHandles(DesignerCanvas draw, Rect bounds, Paint stroke) {
    final fill = Paint()..color = Colors.white;
    for (final handle in ResizeHandle.values) {
      final at = draw.toScreen(handle.on(bounds));
      final square = Rect.fromCenter(center: at, width: 8, height: 8);
      draw.canvas
        ..drawRect(square, fill)
        ..drawRect(square, stroke);
    }
  }

  static List<jge.Entity> _selection(OverlayPaintContext context) {
    final state = context.controller.sceneState;
    final ids = state.multiSelectedIds.value;
    if (ids.isNotEmpty) {
      return ids
          .map(context.world.getEntity)
          .whereType<jge.Entity>()
          .where((e) => e.isActive)
          .toList();
    }
    final selected = state.selectedEntity.value;
    return selected == null ? const [] : [selected];
  }

  static Rect? _bounds(List<jge.Entity> entities) {
    Rect? union;
    for (final entity in entities) {
      var b = DesignerGeometry.worldBounds(entity);
      if (b == null) {
        final t = entity.getComponent<jge.TransformComponent>();
        if (t == null) continue;
        b = Rect.fromLTWH(t.position.x, t.position.y, 0, 0);
      }
      union = union == null ? b : union.expandToInclude(b);
    }
    return union;
  }
}

/// The alignments and gaps of the drag in progress.
///
/// Lines where an edge or centre lines up with a neighbour, and the distance
/// to the nearest neighbour on each side — what the snap just did, visible,
/// so the author can trust it.
class SmartGuidesOverlay extends DesignerOverlay {
  /// Alignment lines.
  static const Color alignColor = Color(0xFFFF4081);

  /// Spacing readouts.
  static const Color spacingColor = Color(0xFFFFAB40);

  @override
  String get id => 'smartGuides';

  @override
  String get label => 'Smart guides';

  @override
  IconData get icon => Icons.align_horizontal_center;

  @override
  String get description => 'Alignment and spacing while dragging';

  @override
  int get order => OverlayOrder.guides + 10;

  @override
  void paint(OverlayPaintContext context) {
    final draw = context.draw;
    final controller = context.controller;
    for (final guide in controller.snapGuides) {
      final from = guide.vertical
          ? Offset(guide.position, guide.start)
          : Offset(guide.start, guide.position);
      final to = guide.vertical
          ? Offset(guide.position, guide.end)
          : Offset(guide.end, guide.position);
      draw.worldLine(from, to, alignColor, strokeWidth: 1);
    }
    for (final gap in controller.spacingGuides) {
      if (gap.distance < 0.5) continue;
      draw.worldLine(gap.from, gap.to, spacingColor, strokeWidth: 1);
      final mid = draw.toScreen(Offset.lerp(gap.from, gap.to, 0.5)!);
      draw.label(
        mid + const Offset(4, -14),
        gap.distance.toStringAsFixed(0),
        spacingColor,
      );
    }
  }
}
