import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../core/constants/editor_constants.dart';
import '../state/designer_geometry.dart';
import '../state/level_designer_controller.dart';
import '../state/editor_history.dart';
import '../tools/tool_registry.dart';
import 'designer_overlay.dart';

/// Palette shared by the built-in overlays.
abstract final class OverlayColors {
  /// Marquee, drag rectangle and selection outlines.
  static const Color selection = Color(0xFF5AC8FA);

  /// Alignment guides.
  static const Color guide = Color(0xFF00E5FF);

  /// Measurement readouts.
  static const Color measurement = Color(0xFFFFEB3B);
}

/// Outlines a multi-entity selection and its combined bounds.
///
/// Only draws for a multi-selection: a single selection already gets the base
/// editor's gizmos, and drawing both would just be two outlines on one entity.
class EntitySelectionOverlay extends DesignerOverlay {
  @override
  String get id => 'selection';

  @override
  String get label => 'Selection';

  @override
  IconData get icon => Icons.select_all;

  @override
  int get order => OverlayOrder.selection;

  @override
  void paint(OverlayPaintContext context) {
    final ids = context.controller.sceneState.multiSelectedIds.value;
    if (ids.length < 2) return;

    final entities = ids
        .map(context.world.getEntity)
        .whereType<jge.Entity>()
        .where((e) => e.isActive)
        .toList();

    for (final entity in entities) {
      final bounds = DesignerGeometry.worldBounds(entity);
      if (bounds == null) continue;
      context.draw.strokeWorldRect(
        bounds,
        OverlayColors.selection.withValues(alpha: 0.9),
        inflate: 2,
      );
    }

    final union = DesignerGeometry.unionBounds(entities);
    if (union == null) return;
    context.draw
      ..dashWorldRect(union, OverlayColors.selection.withValues(alpha: 0.5))
      ..worldLabel(
        union.topLeft,
        '${entities.length} selected',
        OverlayColors.selection,
      );
  }
}

/// The in-progress marquee or draw rectangle.
class DragRectOverlay extends DesignerOverlay {
  @override
  String get id => 'drag_rect';

  @override
  String get label => 'Drag';

  @override
  IconData get icon => Icons.crop_free;

  @override
  int get order => OverlayOrder.selection + 1;

  @override
  void paint(OverlayPaintContext context) {
    final rect = context.controller.dragRect.value;
    if (rect == null) return;

    // The draw tool previews in the active prefab's colour, so what is about to
    // be placed is obvious before the button is released.
    final prefab = context.controller.activePrefab;
    final isMarquee =
        context.controller.toolId.value == BuiltInTools.select ||
        prefab == null;
    final color = isMarquee ? OverlayColors.selection : prefab.color;

    context.draw.fillWorldRect(rect, color.withValues(alpha: 0.18));
    if (isMarquee) {
      context.draw.dashWorldRect(rect, color.withValues(alpha: 0.95));
    } else {
      context.draw.strokeWorldRect(rect, color.withValues(alpha: 0.95));
    }
    context.draw.worldLabel(
      rect.topLeft,
      '${rect.width.round()} x ${rect.height.round()}',
      color,
    );
  }
}

/// Alignment guides dragged out from the rulers.
class GuidesOverlay extends DesignerOverlay {
  @override
  String get id => 'guides';

  @override
  String get label => 'Guides';

  @override
  IconData get icon => Icons.straighten;

  @override
  int get order => OverlayOrder.guides;

  @override
  void paint(OverlayPaintContext context) {
    final guides = context.controller.guides.value;
    if (guides.isEmpty) return;

    final draw = context.draw;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = OverlayColors.guide.withValues(alpha: 0.55)
      ..strokeWidth = 1;

    for (final guide in guides) {
      if (guide.isVertical) {
        final x = draw.toScreen(Offset(guide.position, 0)).dx;
        draw.canvas.drawLine(Offset(x, 0), Offset(x, draw.size.height), paint);
      } else {
        final y = draw.toScreen(Offset(0, guide.position)).dy;
        draw.canvas.drawLine(Offset(0, y), Offset(draw.size.width, y), paint);
      }
    }
  }
}

/// World-coordinate rulers along the top and left edges.
///
/// Tick spacing adapts to zoom: a fixed interval either crowds into an
/// unreadable smear when zoomed out or leaves the ruler blank when zoomed in.
class RulersOverlay extends DesignerOverlay with InteractiveOverlay {
  // The guide being dragged, and the guides as they were before, for undo.
  int _guideIndex = -1;
  List<DesignerGuide> _guidesBefore = const [];

  /// A press on a ruler starts a guide: a new one, or the one under the
  /// pointer if there is one within a few pixels.
  @override
  bool onPointerDown(OverlayPointerContext context) {
    final area = context.area;
    const t = thickness;
    final onTop =
        context.screen.dy >= area.top &&
        context.screen.dy < area.top + t &&
        context.screen.dx >= area.left;
    final onLeft =
        context.screen.dx >= area.left &&
        context.screen.dx < area.left + t &&
        context.screen.dy >= area.top;
    if (!onTop && !onLeft) return false;

    final guides = context.controller.guides.value;
    _guidesBefore = guides;
    _guideIndex = -1;
    for (var i = 0; i < guides.length; i++) {
      final g = guides[i];
      final at = context.camera.worldToScreen(Offset(g.position, g.position));
      if (onTop && g.isVertical && (at.dx - context.screen.dx).abs() <= 4 ||
          onLeft && !g.isVertical && (at.dy - context.screen.dy).abs() <= 4) {
        _guideIndex = i;
        break;
      }
    }
    if (_guideIndex < 0) {
      final world = context.camera.screenToWorld(context.screen);
      context.controller.guides.value = [
        ...guides,
        DesignerGuide(
          isVertical: onLeft,
          position: onLeft ? world.dx : world.dy,
        ),
      ];
      _guideIndex = guides.length;
    }
    return true;
  }

  @override
  void onPointerMove(OverlayPointerContext context) {
    final guides = List.of(context.controller.guides.value);
    if (_guideIndex < 0 || _guideIndex >= guides.length) return;
    final vertical = guides[_guideIndex].isVertical;
    final world = context.camera.screenToWorld(context.screen);
    var position = vertical ? world.dx : world.dy;
    if (context.snapping) {
      position = DesignerGeometry.snapValue(position, context.gridSize);
    }
    guides[_guideIndex] = DesignerGuide(
      isVertical: vertical,
      position: position,
    );
    context.controller
      ..guides.value = guides
      ..setStatus('${vertical ? 'x' : 'y'} = ${position.toStringAsFixed(0)}');
  }

  /// A guide dropped back on its ruler is removed; any change is one undo
  /// step.
  @override
  void onPointerUp(OverlayPointerContext context) {
    var guides = context.controller.guides.value;
    if (_guideIndex >= 0 && _guideIndex < guides.length) {
      final vertical = guides[_guideIndex].isVertical;
      final onRuler = vertical
          ? context.screen.dx < context.area.left + thickness
          : context.screen.dy < context.area.top + thickness;
      if (onRuler) {
        guides = [...guides]..removeAt(_guideIndex);
        context.controller.guides.value = guides;
      }
    }
    final before = _guidesBefore;
    final after = context.controller.guides.value;
    if (!listEquals(before, after)) {
      context.history.push(
        CallbackCommand(
          label: after.length < before.length ? 'Remove guide' : 'Move guide',
          onRedo: () => context.controller.guides.value = after,
          onUndo: () => context.controller.guides.value = before,
        ),
      );
    }
    onCancel();
  }

  @override
  void onCancel() {
    _guideIndex = -1;
    _guidesBefore = const [];
  }

  /// The id the session and the status bar refer to it by.
  static const String overlayId = 'rulers';

  @override
  String get id => overlayId;

  @override
  String get label => 'Rulers';

  @override
  IconData get icon => Icons.square_foot;

  @override
  int get order => OverlayOrder.chrome;

  /// Thickness of the ruler strips, in screen pixels.
  static const double thickness = 18;

  @override
  void paint(OverlayPaintContext context) {
    final draw = context.draw;
    final canvas = draw.canvas;
    // Along the edges of the part of the canvas that is not under a panel —
    // at the canvas edge itself, the left ruler sat under the tool palette.
    final area = context.controller.visibleViewport(draw.size);

    final background = Paint()
      ..style = PaintingStyle.fill
      ..color = EditorTheme.surfaceDark.withValues(alpha: 0.85);
    canvas
      ..drawRect(
        Rect.fromLTWH(area.left, area.top, area.width, thickness),
        background,
      )
      ..drawRect(
        Rect.fromLTWH(area.left, area.top, thickness, area.height),
        background,
      );

    final topLeft = draw.toWorld(area.topLeft);
    final bottomRight = draw.toWorld(area.bottomRight);
    final step = _rulerStep(draw.camera.zoom.abs());

    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..color = EditorTheme.textMuted.withValues(alpha: 0.8)
      ..strokeWidth = 1;

    for (
      var x = (topLeft.dx / step).floor() * step;
      x <= bottomRight.dx;
      x += step
    ) {
      final sx = draw.toScreen(Offset(x, 0)).dx;
      if (sx < area.left + thickness || sx > area.right) continue;
      canvas.drawLine(
        Offset(sx, area.top + thickness - 5),
        Offset(sx, area.top + thickness),
        tick,
      );
      draw.label(
        Offset(sx + 2, area.top + 2),
        x.round().toString(),
        EditorTheme.textMuted,
        fontSize: 9,
      );
    }

    for (
      var y = (topLeft.dy / step).floor() * step;
      y <= bottomRight.dy;
      y += step
    ) {
      final sy = draw.toScreen(Offset(0, y)).dy;
      if (sy < area.top + thickness || sy > area.bottom) continue;
      canvas.drawLine(
        Offset(area.left + thickness - 5, sy),
        Offset(area.left + thickness, sy),
        tick,
      );
      draw.label(
        Offset(area.left + 2, sy + 2),
        y.round().toString(),
        EditorTheme.textMuted,
        fontSize: 9,
      );
    }
  }

  /// Picks a ruler interval that stays legible at the current [zoom].
  double _rulerStep(double zoom) {
    const candidates = [10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0];
    const minScreenSpacing = 64.0;
    for (final candidate in candidates) {
      if (candidate * zoom >= minScreenSpacing) return candidate;
    }
    return candidates.last;
  }
}
