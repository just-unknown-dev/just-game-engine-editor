import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import 'built_in_overlays.dart';

/// Where the minimap sits and how it maps world to panel. Shared by the
/// overlay that draws it and the session that handles clicks on it, so the
/// two cannot disagree about what is where.
class MinimapLayout {
  MinimapLayout._(this.panel, this._scale, this._origin);

  /// Panel size in screen pixels.
  static const Size size = Size(200, 124);

  /// Gap from the viewport edges.
  static const double margin = 10;

  /// The panel rectangle for a visible viewport [area]: bottom-left, clear of
  /// the left ruler, and [bottomReserve] above the bottom edge, for anything
  /// that has to sit beneath it.
  static Rect panelFor(Rect area, {double bottomReserve = 0}) => Rect.fromLTWH(
    area.left + RulersOverlay.thickness + margin,
    area.bottom - margin - bottomReserve - size.height,
    size.width,
    size.height,
  );

  /// Lays the map out for everything [controller] shows in [world], plus the
  /// camera's current [view]. Null when there is nothing to show.
  static MinimapLayout? of(
    jge.World world,
    LevelDesignerController controller,
    Rect area,
    Rect view,
  ) {
    Rect? extent = view;
    for (final e in world.query([jge.TransformComponent])) {
      if (!e.isActive || !controller.isShownInViewport(e)) continue;
      final b = DesignerGeometry.worldBounds(e);
      if (b != null) extent = extent!.expandToInclude(b);
    }
    if (extent == null || extent.isEmpty) return null;
    extent = extent.inflate(math.max(extent.width, extent.height) * 0.04);

    final panel = panelFor(
      area,
      bottomReserve: controller.minimapBottomReserve,
    );
    final inner = panel.deflate(6);
    final scale = math.min(
      inner.width / extent.width,
      inner.height / extent.height,
    );
    // Centre the extent in the panel.
    final origin =
        inner.center -
        Offset(extent.center.dx * scale, extent.center.dy * scale);
    return MinimapLayout._(panel, scale, origin);
  }

  /// The panel, in screen pixels.
  final Rect panel;
  final double _scale;
  final Offset _origin;

  /// World point to panel point.
  Offset toPanel(Offset world) => _origin + world * _scale;

  /// World rectangle to panel rectangle.
  Rect rectToPanel(Rect world) =>
      Rect.fromPoints(toPanel(world.topLeft), toPanel(world.bottomRight));

  /// Panel point to world point.
  Offset toWorld(Offset panelPoint) => (panelPoint - _origin) / _scale;
}

/// A map of the whole level with the current view on it. Click or drag it to
/// go there.
class MinimapOverlay extends DesignerOverlay with InteractiveOverlay {
  /// A press on the map jumps the view there; dragging keeps jumping.
  @override
  bool onPointerDown(OverlayPointerContext context) {
    final panel = MinimapLayout.panelFor(
      context.area,
      bottomReserve: context.controller.minimapBottomReserve,
    );
    if (!panel.contains(context.screen)) return false;
    _jumpTo(context);
    return true;
  }

  @override
  void onPointerMove(OverlayPointerContext context) => _jumpTo(context);

  /// Centres the visible viewport on the world point under the pointer. The
  /// camera centres the whole canvas, not the visible part, so the target is
  /// offset by how far off-centre the panels push that part.
  static void _jumpTo(OverlayPointerContext context) {
    final cam = context.camera;
    final area = context.area;
    final view = Rect.fromPoints(
      cam.screenToWorld(area.topLeft),
      cam.screenToWorld(area.bottomRight),
    );
    final layout = MinimapLayout.of(
      context.world,
      context.controller,
      area,
      view,
    );
    if (layout == null) return;
    final target = layout.toWorld(context.screen);
    final canvasCentre = Offset(
      cam.viewportSize.width / 2,
      cam.viewportSize.height / 2,
    );
    cam.setPosition(target - (area.center - canvasCentre) / cam.zoom);
  }

  /// A colour that reads as the entity: its rectangle's fill when it has one,
  /// else the accent colour of the first definition that declares one.
  static Color _colourOf(jge.Entity entity) {
    for (final c in entity.components) {
      if (c is jge.RectangleComponent) return c.fillStyle.color;
    }
    final definitions = DesignerGeometry.definitionsFor(entity);
    for (final c in entity.components) {
      final accent = definitions.definitionFor(c)?.hints.accentColor;
      if (accent != null) return accent;
    }
    return EditorTheme.textMuted;
  }

  /// Stable id, for toggling and for hit-testing.
  static const String overlayId = 'minimap';

  @override
  String get id => overlayId;

  @override
  String get label => 'Minimap';

  @override
  IconData get icon => Icons.map_outlined;

  @override
  String get description => 'Overview of the level; click to jump';

  @override
  int get order => OverlayOrder.chrome + 10;

  @override
  void paint(OverlayPaintContext context) {
    final draw = context.draw;
    final area = context.controller.visibleViewport(draw.size);
    final view = Rect.fromPoints(
      draw.toWorld(area.topLeft),
      draw.toWorld(area.bottomRight),
    );
    final layout = MinimapLayout.of(
      context.world,
      context.controller,
      area,
      view,
    );
    if (layout == null) return;

    final canvas = draw.canvas;
    canvas
      ..save()
      ..clipRect(layout.panel)
      ..drawRect(
        layout.panel,
        Paint()..color = EditorTheme.surfaceDark.withValues(alpha: 0.88),
      );

    final selected = {
      ...context.controller.sceneState.multiSelectedIds.value,
      ?context.controller.sceneState.selectedEntity.value?.id,
    };
    final fill = Paint();
    for (final e in context.world.query([jge.TransformComponent])) {
      if (!e.isActive || !context.controller.isShownInViewport(e)) continue;
      final b = DesignerGeometry.worldBounds(e);
      if (b == null) continue;
      final r = layout.rectToPanel(b);
      fill.color = selected.contains(e.id)
          ? OverlayColors.selection
          : _colourOf(e).withValues(alpha: 0.85);
      // At least a pixel, or small things vanish from the map entirely.
      canvas.drawRect(
        Rect.fromCenter(
          center: r.center,
          width: math.max(r.width, 1.5),
          height: math.max(r.height, 1.5),
        ),
        fill,
      );
    }

    canvas
      ..drawRect(
        layout.rectToPanel(view),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.9),
      )
      ..restore()
      ..drawRect(
        layout.panel,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = EditorTheme.textMuted.withValues(alpha: 0.6),
      );
  }
}
