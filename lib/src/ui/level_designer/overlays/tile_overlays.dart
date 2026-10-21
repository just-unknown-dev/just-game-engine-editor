import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine/just_game_engine.dart'
    show TileCell, TileCoord, MapGeometry, MapOrientation, LevelMapRuntime;

import 'package:just_editor_core/host.dart';
import '../../../core/level_map/tile_edit_state.dart';
import '../../../core/level_map/level_map_documents.dart';
import '../../overlay/transform_gizmo.dart';
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
Path _outline(
  MapGeometry g,
  Iterable<TileCoord> cells, [
  Offset shift = Offset.zero,
]) {
  // Neighbouring cells share an edge's two corners exactly (to rounding),
  // so an edge seen twice is inside the set. Keyed by whole numbers (a
  // 64th of a pixel), not strings: this runs over every cell of an area.
  (int, int) key(Offset a) => ((a.dx * 64).round(), (a.dy * 64).round());
  final seen = <(int, int, int, int), (Offset, Offset)>{};
  final twice = <(int, int, int, int)>{};
  for (final c in cells) {
    final pts = g.cellPolygon(c.x, c.y);
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final (ax, ay) = key(a);
      final (bx, by) = key(b);
      final k = ax < bx || (ax == bx && ay <= by)
          ? (ax, ay, bx, by)
          : (bx, by, ax, ay);
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

/// The smallest convex shape round [points] (Andrew's monotone chain).
Path _hull(List<Offset> points) {
  final pts = [
    ...points,
  ]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  double cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  final lower = <Offset>[];
  for (final p in pts) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Offset>[];
  for (final p in pts.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  final ring = [...lower..removeLast(), ...upper..removeLast()];
  return ring.isEmpty ? Path() : _polygon(ring);
}

/// The box of cells from [a] to [b] as one shape: round its four corner
/// cells — exact on square and diamond grids, close on the rest — for an
/// area too large to draw cell by cell.
Path _boxShape(MapGeometry g, TileCoord a, TileCoord b) => _hull([
  for (final c in [a, TileCoord(b.x, a.y), b, TileCoord(a.x, b.y)])
    ...g.cellPolygon(c.x, c.y),
]);

/// Draws [cell]'s tile at [at] on [g], turned as the cell says: what the
/// map would draw there. Nothing when its tileset is not loaded yet.
void _paintTile(
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

  // What a tool in use draws: it stays with the gizmos hidden.
  @override
  GizmoKind? get gizmoKind => null;

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

/// One value worked out for a key, and kept until the key changes: what
/// the overlays draw every frame is laid out only when it changes.
class _Kept<T> {
  Object? _key;
  T? _value;
  bool _set = false;

  T of(Object key, T Function() make) {
    if (!_set || _key != key) {
      _value = make();
      _key = key;
      _set = true;
    }
    return _value as T;
  }
}

/// [value] compared by identity: a set or map that is replaced, never
/// changed in place, as the tile state's are.
class _Same {
  const _Same(this.value);

  final Object value;

  @override
  bool operator ==(Object other) =>
      other is _Same && identical(other.value, value);

  @override
  int get hashCode => identityHashCode(value);
}

/// An area's fill and its outline, in its layer's own pixels.
typedef _AreaShape = ({Path fill, Path line});

/// What the tile tools are doing: the brush under the pointer, the cells an
/// eraser would clear, an area being dragged out, the selection, and tiles
/// being moved.
///
/// Laid out only when what it shows changes — the selection, the preview,
/// the area — and drawn shifted to its layer, so a frame with nothing new
/// costs a few paths, however many cells there are.
class TileBrushOverlay extends DesignerOverlay {
  TileBrushOverlay(this.scope);

  final EditorScope scope;

  // What a tool in use draws: it stays with the gizmos hidden.
  @override
  GizmoKind? get gizmoKind => null;

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

  /// Past this many cells, an area is drawn as one shape round the box it
  /// spans rather than cell by cell, and the tiles of a preview or of a
  /// block being moved are not drawn — only where they would go.
  static const int maxAreaCells = 20000;

  final _Kept<_AreaShape> _selection = _Kept();
  final _Kept<_AreaShape> _drag = _Kept();
  final _Kept<Path> _previewLine = _Kept();
  final _Kept<Path?> _previewErase = _Kept();
  final _Kept<Rect?> _bounds = _Kept();

  /// What [g] lays cells out by: what a shape kept for it depends on.
  static Object _gridOf(MapGeometry g) => (
    g.orientation,
    g.tileWidth,
    g.tileHeight,
    g.staggerAxis,
    g.staggerIndex,
    g.hexSideLength,
  );

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
    final grid = _gridOf(g);
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

      _paintSelection(canvas, state, g, grid, shift, line, fill);

      // Tiles being moved, where they would land.
      final floating = state.floating;
      if (floating.isNotEmpty &&
          floating.length <= maxAreaCells &&
          runtime != null) {
        floating.forEach(
          (cell, value) => _paintTile(
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
        final shape = _drag.of((area, grid), () {
          if (TileTool.areaOf(area.$1, area.$2) > maxAreaCells) {
            final box = _boxShape(g, area.$1, area.$2);
            return (fill: box, line: box);
          }
          return _cellsShape(g, TileTool.rectCells(area.$1, area.$2));
        });
        _paintShape(canvas, shape, shift, OverlayColors.selection, line, fill);
      }

      // What a click would do.
      final preview = state.preview;
      if (preview.isNotEmpty && area == null && floating.isEmpty) {
        final small = preview.length <= maxAreaCells;
        if (small && runtime != null) {
          preview.forEach((cell, value) {
            if (!TileCell.isEmpty(value)) {
              _paintTile(canvas, runtime, g, cell, value, shift, ghost);
            }
          });
        }
        // The map is replaced whenever the preview changes: kept by it.
        final key = (_Same(preview), grid);
        final erase = _previewErase.of(key, () {
          if (!preview.values.any(TileCell.isEmpty)) return null;
          if (!small) return _boundsShape(g, preview.keys);
          final path = Path();
          preview.forEach((c, value) {
            if (TileCell.isEmpty(value)) {
              path.addPath(_polygon(g.cellPolygon(c.x, c.y)), Offset.zero);
            }
          });
          return path;
        });
        final outline = _previewLine.of(
          key,
          () =>
              small ? _outline(g, preview.keys) : _boundsShape(g, preview.keys),
        );
        line.color = erase != null
            ? TileOverlayColors.erase
            : TileOverlayColors.hover;
        canvas
          ..save()
          ..translate(shift.dx, shift.dy);
        if (erase != null) {
          fill.color = TileOverlayColors.erase.withValues(alpha: 0.18);
          canvas.drawPath(erase, fill);
        }
        canvas
          ..drawPath(outline, line)
          ..restore();
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
    _paintGizmo(context, target, layer, grid);
  }

  /// The selection's gizmo, with Select tiles in hand: arrows to move it,
  /// the ring to turn it, or both (All) — as the toolbar says. Not while
  /// its tiles are being carried: they are not where it would be.
  void _paintGizmo(
    OverlayPaintContext context,
    LevelMapTarget target,
    jge.MapLayerData layer,
    Object grid,
  ) {
    if (context.controller.toolId.value != TileTools.select) return;
    final state = scope.tiles;
    final cells = state.selection.value;
    if (cells.isEmpty || state.floating.isNotEmpty) return;
    final draw = context.draw;
    final g = target.geometry;
    // In the layer's own pixels, kept by the selection — a fresh set
    // whenever it changes — then shifted to where the layer is drawn.
    final local = _bounds.of((
      _Same(cells),
      grid,
    ), () => _cellsBounds(g, cells));
    if (local == null) return;
    final bounds = local.shift(
      TileTool.layerShift(target, layer, draw.camera.position),
    );
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
    Object grid,
    Offset shift,
    Paint line,
    Paint fill,
  ) {
    final cells = state.selection.value;
    if (cells.isEmpty) return;
    final moved = state.floating.isNotEmpty;
    final offset = moved ? state.floatOffset : null;
    final shape = _selection.of((_Same(cells), offset, grid), () {
      final shown = moved
          ? [for (final c in cells) state.floated(g, c)]
          : cells.toList();
      if (shown.length <= maxAreaCells) return _cellsShape(g, shown);
      final box = _boundsShape(g, shown);
      return (fill: box, line: box);
    });
    _paintShape(canvas, shape, shift, OverlayColors.selection, line, fill);
  }

  /// [cells] cell by cell: every cell filled, and the outline round them.
  static _AreaShape _cellsShape(MapGeometry g, List<TileCoord> cells) {
    final area = Path();
    for (final c in cells) {
      area.addPath(_polygon(g.cellPolygon(c.x, c.y)), Offset.zero);
    }
    return (fill: area, line: _outline(g, cells));
  }

  /// One shape round the box [cells] span, for a set too large to draw
  /// cell by cell.
  static Path _boundsShape(MapGeometry g, Iterable<TileCoord> cells) {
    var x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    var first = true;
    for (final c in cells) {
      if (first) {
        x0 = x1 = c.x;
        y0 = y1 = c.y;
        first = false;
        continue;
      }
      x0 = math.min(x0, c.x);
      x1 = math.max(x1, c.x);
      y0 = math.min(y0, c.y);
      y1 = math.max(y1, c.y);
    }
    return first ? Path() : _boxShape(g, TileCoord(x0, y0), TileCoord(x1, y1));
  }

  /// The box [cells] cover, in their layer's own pixels.
  static Rect? _cellsBounds(MapGeometry g, Iterable<TileCoord> cells) {
    double? l, t, r, b;
    for (final c in cells) {
      for (final p in g.cellPolygon(c.x, c.y)) {
        l = l == null ? p.dx : math.min(l, p.dx);
        t = t == null ? p.dy : math.min(t, p.dy);
        r = r == null ? p.dx : math.max(r, p.dx);
        b = b == null ? p.dy : math.max(b, p.dy);
      }
    }
    return l == null ? null : Rect.fromLTRB(l, t!, r!, b!);
  }

  static void _paintShape(
    Canvas canvas,
    _AreaShape shape,
    Offset shift,
    Color color,
    Paint line,
    Paint fill,
  ) {
    fill.color = color.withValues(alpha: 0.16);
    line.color = color.withValues(alpha: 0.95);
    canvas
      ..save()
      ..translate(shift.dx, shift.dy)
      ..drawPath(shape.fill, fill)
      ..drawPath(shape.line, line)
      ..restore();
  }
}
