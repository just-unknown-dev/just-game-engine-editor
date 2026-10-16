import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine/just_game_engine.dart'
    show TileCell, TileCoord, MapGeometry, MapOrientation, LevelMapRuntime;

import 'package:just_editor_core/host.dart';
import '../../../core/level_map/tile_edit_state.dart';
import '../../overlay/transform_gizmo.dart';
import '../tools/tiles/tile_select_tool.dart';
import '../tools/tiles/tile_tool_base.dart';
import 'built_in_overlays.dart';
import '../../../core/scope/editor_scope_services.dart';

/// Ids of the tile overlays.
abstract final class TileOverlays {
  static const String grid = 'tile_grid';
  static const String brush = 'tile_brush';
}

/// Colours the tile overlays use.
abstract final class TileOverlayColors {
  /// The cell lines: the viewport's grid colour, a little stronger.
  static Color get grid => ViewportLook.gridLine(0.22);
  static const Color hover = Color(0xCCFFFFFF);
  static const Color erase = Color(0xFFFF5252);
}

/// Whether a tile tool is in [context]'s hand.
bool _tileToolActive(OverlayPaintContext context) =>
    context.controller.activeTool?.group == ToolGroups.tiles;

/// Runs [paint] with [draw]'s canvas in world units, as the camera sees
/// them, then puts the canvas back.
void _inWorld(
  DesignerCanvas draw,
  void Function(Canvas canvas, double zoom) paint,
) {
  final canvas = draw.canvas;
  canvas.save();
  draw.camera.applyTransform(canvas, draw.camera.viewportSize);
  paint(canvas, draw.camera.zoom);
  canvas.restore();
}

/// [points] as a closed path.
Path _polygon(List<Offset> points, [Offset shift = Offset.zero]) {
  final path = Path()
    ..moveTo(points.first.dx + shift.dx, points.first.dy + shift.dy);
  for (var i = 1; i < points.length; i++) {
    path.lineTo(points[i].dx + shift.dx, points[i].dy + shift.dy);
  }
  return path..close();
}

/// The outline of a set of cells: the cell edges no other cell of the set
/// shares, whatever the map's orientation.
Path _outline(MapGeometry g, Iterable<TileCoord> cells, Offset shift) {
  // Neighbouring cells share an edge's two corners exactly (to rounding),
  // so an edge seen twice is inside the set.
  String key(Offset a) => '${(a.dx * 64).round()},${(a.dy * 64).round()}';
  final seen = <String, (Offset, Offset)>{};
  final twice = <String>{};
  for (final c in cells) {
    final pts = g.cellPolygon(c.x, c.y);
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final ka = key(a), kb = key(b);
      final k = ka.compareTo(kb) < 0 ? '$ka|$kb' : '$kb|$ka';
      if (seen.containsKey(k)) {
        twice.add(k);
      } else {
        seen[k] = (a, b);
      }
    }
  }
  final path = Path();
  seen.forEach((k, e) {
    if (twice.contains(k)) return;
    path
      ..moveTo(e.$1.dx + shift.dx, e.$1.dy + shift.dy)
      ..lineTo(e.$2.dx + shift.dx, e.$2.dy + shift.dy);
  });
  return path;
}

/// Draws [cell]'s tile at [at] on [g], turned as the cell says: what the
/// map would draw there. Nothing when its tileset is not loaded yet.
void paintTile(
  Canvas canvas,
  LevelMapRuntime runtime,
  MapGeometry g,
  TileCoord at,
  int cell,
  Offset shift,
  Paint paint,
) {
  if (TileCell.isEmpty(cell)) return;
  final slot = TileCell.slotOf(cell);
  final ts = runtime.tilesetAt(slot);
  final image = runtime.imageAt(slot);
  final id = TileCell.localIdOf(cell);
  if (ts == null || image == null || !ts.contains(id)) return;
  final t = TileCell.drawTransform(
    cell,
    hexagonal: g.orientation == MapOrientation.hexagonal,
  );
  final tw = ts.tileWidth.toDouble();
  final th = ts.tileHeight.toDouble();
  final dest = g
      .tileImageRect(
        at.x,
        at.y,
        t.sideways ? th : tw,
        t.sideways ? tw : th,
        offsetX: ts.tileOffsetX,
        offsetY: ts.tileOffsetY,
      )
      .shift(shift);
  final def = ts.tile(id);
  final shown = def != null && def.isAnimated
      ? def.frameAt(id, runtime.animationMs)
      : id;
  canvas
    ..save()
    ..translate(dest.center.dx, dest.center.dy);
  if (t.radians != 0) canvas.rotate(t.radians);
  if (t.mirrored) canvas.scale(-1, 1);
  canvas
    ..drawImageRect(
      image,
      ts.sourceRect(shown),
      Rect.fromCenter(center: Offset.zero, width: tw, height: th),
      paint,
    )
    ..restore();
}

/// The map's own grid, in its orientation, under the layer being painted —
/// while a tile tool is in hand. Also draws the tiles' collision when the
/// tile controls' collision view is on, whatever the tool.
class TileGridOverlay extends DesignerOverlay {
  TileGridOverlay(this.scope);

  final EditorScope scope;

  @override
  String get id => TileOverlays.grid;
  @override
  String get label => 'Tile grid';
  @override
  IconData get icon => Icons.grid_on;
  @override
  String? get description =>
      'The Level Map\'s cells while a tile tool is in hand, and its collision '
      'when the collision view is on';
  @override
  int get order => OverlayOrder.region + 10;

  /// Past this many cells on screen the grid is left out: it would be a
  /// grey wash, and slow.
  static const int maxCells = 40000;

  final Map<(int, int), (int, List<jge.MapBodySpec>)> _collision = {};

  @override
  void paint(OverlayPaintContext context) {
    final state = scope.tiles;
    if (state.showCollision.value) _paintCollision(context);
    if (!_tileToolActive(context)) return;
    // Peek, never choose: choosing writes signals, and a paint that
    // writes one schedules a build mid-frame.
    final target = state.peek(context.world);
    final layer = target == null ? null : state.peekLayer(target);
    if (target == null || layer == null) return;
    final draw = context.draw;
    final g = target.geometry;
    final shift = TileTool.layerShift(target, layer, draw.camera.position);
    final zoom = draw.camera.zoom;
    if (math.min(g.tileWidth, g.tileHeight) * zoom < 4) return;
    final a = draw.toWorld(Offset.zero) - shift;
    final b = draw.toWorld(Offset(draw.size.width, draw.size.height)) - shift;
    final view = Rect.fromPoints(a, b);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0
      ..color = TileOverlayColors.grid;
    _inWorld(draw, (canvas, _) {
      if (g.orientation == MapOrientation.orthogonal) {
        final path = Path();
        final tw = g.tileWidth.toDouble();
        final th = g.tileHeight.toDouble();
        for (
          var x = (view.left / tw).floor();
          x <= (view.right / tw).ceil();
          x++
        ) {
          path
            ..moveTo(x * tw + shift.dx, view.top + shift.dy)
            ..lineTo(x * tw + shift.dx, view.bottom + shift.dy);
        }
        for (
          var y = (view.top / th).floor();
          y <= (view.bottom / th).ceil();
          y++
        ) {
          path
            ..moveTo(view.left + shift.dx, y * th + shift.dy)
            ..lineTo(view.right + shift.dx, y * th + shift.dy);
        }
        canvas.drawPath(path, paint);
        return;
      }
      final range = g.cellRange(view);
      if (range.width * range.height > maxCells) return;
      final path = Path();
      for (final c in range.coords) {
        path.addPath(_polygon(g.cellPolygon(c.x, c.y)), shift);
      }
      canvas.drawPath(path, paint);
    });
  }

  void _paintCollision(OverlayPaintContext context) {
    final docs = scope.mapDocs;
    final live = <(int, int)>{};
    _inWorld(context.draw, (canvas, zoom) {
      final fill = Paint();
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / zoom;
      for (final entity in context.world.query([jge.LevelMapComponent])) {
        final target = docs.resolve(entity);
        final runtime = target?.component.runtime;
        if (target == null || runtime == null) continue;
        for (final layer in target.data.layers) {
          if (!layer.collides || !layer.visible) continue;
          final key = (entity.id, layer.id);
          live.add(key);
          final signature = Object.hash(
            target.data.revision,
            layer.cells.revision,
            runtime.tilesetsRevision,
            layer.offsetX,
            layer.offsetY,
          );
          var cached = _collision[key];
          if (cached == null || cached.$1 != signature) {
            cached = (
              signature,
              jge.TileCollisionBuilder.build(
                cells: layer.cells,
                geometry: target.geometry,
                tilesetAt: runtime.tilesetAt,
                offset: Offset(layer.offsetX, layer.offsetY),
                kinds: runtime.context.collisionKinds,
              ),
            );
            _collision[key] = cached;
          }
          for (final spec in cached.$2) {
            final color = Color(
              runtime.context.collisionKinds.resolve(spec.kind).color,
            );
            fill.color = color.withValues(alpha: 0.22);
            stroke.color = color.withValues(alpha: 0.9);
            final at = target.origin + spec.center;
            final size = spec.size;
            if (size != null) {
              final r = Rect.fromCenter(
                center: at,
                width: size.width,
                height: size.height,
              );
              canvas
                ..drawRect(r, fill)
                ..drawRect(r, stroke);
            } else {
              final path = _polygon(spec.polygon!, at);
              canvas
                ..drawPath(path, fill)
                ..drawPath(path, stroke);
            }
          }
        }
      }
    });
    _collision.removeWhere((key, _) => !live.contains(key));
  }
}

/// What the tile tools are doing: the brush under the pointer, the cells an
/// eraser would clear, an area being dragged out, the selection, and tiles
/// being moved.
class TileBrushOverlay extends DesignerOverlay {
  TileBrushOverlay(this.scope);

  final EditorScope scope;

  @override
  String get id => TileOverlays.brush;
  @override
  String get label => 'Tile brush';
  @override
  IconData get icon => Icons.format_paint_outlined;
  @override
  String? get description =>
      'The tile brush under the pointer and the selected tiles';
  @override
  int get order => OverlayOrder.selection - 5;

  /// Past this many cells, an area is outlined by its corners only.
  static const int maxAreaCells = 20000;

  @override
  void paint(OverlayPaintContext context) {
    if (!_tileToolActive(context)) return;
    final state = scope.tiles;
    // Peek, never choose: choosing writes signals, and a paint that
    // writes one schedules a build mid-frame.
    final target = state.peek(context.world);
    final layer = target == null ? null : state.peekLayer(target);
    if (target == null || layer == null) return;
    final draw = context.draw;
    final g = target.geometry;
    final shift = TileTool.layerShift(target, layer, draw.camera.position);
    final runtime = target.component.runtime;
    _inWorld(draw, (canvas, zoom) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / zoom;
      final fill = Paint();
      final ghost = Paint()
        ..color = const Color(0xA6FFFFFF)
        ..filterQuality = FilterQuality.none;

      _paintSelection(canvas, state, g, shift, line, fill);

      // Tiles being moved, where they would land.
      if (state.floating.isNotEmpty && runtime != null) {
        state.floating.forEach(
          (cell, value) => paintTile(
            canvas,
            runtime,
            g,
            state.floated(g, cell),
            value,
            shift,
            ghost,
          ),
        );
      }

      // An area being dragged out.
      final area = state.dragArea;
      if (area != null) {
        final cells = TileTool.rectCells(area.$1, area.$2);
        _paintArea(
          canvas,
          g,
          cells,
          shift,
          OverlayColors.selection,
          line,
          fill,
        );
      }

      // What a click would do.
      final preview = state.preview;
      if (preview.isNotEmpty && area == null && state.floating.isEmpty) {
        var erases = false;
        preview.forEach((cell, value) {
          if (TileCell.isEmpty(value)) {
            erases = true;
          } else if (runtime != null) {
            paintTile(canvas, runtime, g, cell, value, shift, ghost);
          }
        });
        line.color = erases ? TileOverlayColors.erase : TileOverlayColors.hover;
        if (erases) {
          fill.color = TileOverlayColors.erase.withValues(alpha: 0.18);
          for (final c in preview.keys) {
            canvas.drawPath(_polygon(g.cellPolygon(c.x, c.y), shift), fill);
          }
        }
        canvas.drawPath(_outline(g, preview.keys, shift), line);
      } else {
        final hover = state.hoverCell;
        if (hover != null && area == null) {
          line.color = TileOverlayColors.hover;
          canvas.drawPath(
            _polygon(g.cellPolygon(hover.x, hover.y), shift),
            line,
          );
        }
      }
    });
    _paintGizmo(context);
  }

  /// The selection's gizmo, with Select tiles in hand: arrows to move it,
  /// the ring to turn it, or both (All) — as the toolbar says. Not while its tiles
  /// are being carried: they are not where it would be.
  void _paintGizmo(OverlayPaintContext context) {
    if (context.controller.toolId.value != TileTools.select) return;
    final state = scope.tiles;
    final cells = state.selection.value;
    if (cells.isEmpty || state.floating.isNotEmpty) return;
    // Peek, never choose: choosing writes signals, and a paint that
    // writes one schedules a build mid-frame.
    final target = state.peek(context.world);
    final layer = target == null ? null : state.peekLayer(target);
    if (target == null || layer == null) return;
    final draw = context.draw;
    final bounds = TileSelectTool.cellsBounds(
      target,
      layer,
      cells,
      draw.camera.position,
    );
    if (bounds == null) return;
    final centre = draw.toScreen(bounds.center);
    final zoom = draw.camera.zoom;
    final mode = TransformModes.shown(
      context.controller.view.transformMode.value,
      TransformModes.tiles,
    );
    if (mode == TransformMode.rotate || mode == TransformMode.all) {
      final radius = scope.handleLayout.ringRadius(bounds, 1 / zoom) * zoom;
      TransformGizmo.paintRotate(
        draw.canvas,
        centre,
        mode == TransformMode.all
            ? TransformGizmo.ringClearOfArrows(radius)
            : radius,
      );
    }
    if (mode == TransformMode.move || mode == TransformMode.all) {
      TransformGizmo.paintMove(draw.canvas, centre);
    }
  }

  void _paintSelection(
    Canvas canvas,
    TileEditState state,
    MapGeometry g,
    Offset shift,
    Paint line,
    Paint fill,
  ) {
    var cells = state.selection.value;
    if (cells.isEmpty) return;
    if (state.floating.isNotEmpty) {
      cells = {for (final c in cells) state.floated(g, c)};
    }
    _paintArea(canvas, g, cells, shift, OverlayColors.selection, line, fill);
  }

  void _paintArea(
    Canvas canvas,
    MapGeometry g,
    Iterable<TileCoord> cells,
    Offset shift,
    Color color,
    Paint line,
    Paint fill,
  ) {
    fill.color = color.withValues(alpha: 0.16);
    line.color = color.withValues(alpha: 0.95);
    final list = cells is List<TileCoord> ? cells : cells.toList();
    if (list.length > maxAreaCells) {
      // Too many to outline one by one: mark the extremes.
      for (final c in [list.first, list.last]) {
        canvas.drawPath(_polygon(g.cellPolygon(c.x, c.y), shift), line);
      }
      return;
    }
    final area = Path();
    for (final c in list) {
      area.addPath(_polygon(g.cellPolygon(c.x, c.y)), shift);
    }
    canvas
      ..drawPath(area, fill)
      ..drawPath(_outline(g, list, shift), line);
  }
}
