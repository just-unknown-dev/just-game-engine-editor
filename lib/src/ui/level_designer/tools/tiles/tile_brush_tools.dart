import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../../../core/level_map/tile_commands.dart';
import '../../../../core/level_map/tile_edit_state.dart';
import '../../controls/designer_controls.dart';
import 'package:just_editor_core/host.dart';
import 'tile_tool_base.dart';

/// Paints the brush — the tiles picked in the Tileset panel, or picked up
/// from the map with a right-drag — wherever it is dragged.
class StampTool extends TileTool {
  StampTool(super.scope, {super.switchTool});

  @override
  String get id => TileTools.stamp;
  @override
  String get label => 'Stamp';
  @override
  IconData get icon => Icons.approval;
  @override
  String? get shortcut => 'S';
  @override
  int get order => 200;

  @override
  List<Widget> buildTileOptions(
    BuildContext context,
    ToolOptionsContext options,
  ) => [randomToggle()];
  @override
  String? get description =>
      'Paint the tiles picked in the Tileset panel. Right-drag picks tiles '
      'up from the map; X / Y mirror the brush, Z turns it.';

  TileStroke? _stroke;
  TileAim? _aim;
  TileCoord? _last;

  @override
  void onActivate() => state.paletteTerrains.value = false;

  @override
  bool onPaintDown(ToolContext c) {
    if (state.stamp.value == null) {
      c.controller.setStatus(
        'Pick a tile in the Tileset panel first, or right-click one on the map',
      );
      return true;
    }
    final a = aim(c, create: true);
    if (a == null) return true;
    final stamp = brushFor(a, c);
    if (stamp == null) return true;
    _aim = a;
    _stroke = strokeOn(a);
    final at = cellAt(a, c.worldPosition, c);
    stampAt(_stroke!, a, at, stamp);
    _last = at;
    return true;
  }

  @override
  void onPaintMove(ToolContext c) {
    final stroke = _stroke;
    final a = _aim;
    // Read on each move: X, Y and Z turn the brush mid-stroke.
    final stamp = a == null ? null : brushFor(a, c, quiet: true);
    if (stroke == null || a == null || stamp == null) return;
    final at = cellAt(a, c.worldPosition, c);
    if (at == _last) return;
    for (final cell in TileTool.cellsAlong(a.target.geometry, _last!, at)) {
      stampAt(stroke, a, cell, stamp);
    }
    _last = at;
    state.hoverCell = at;
  }

  @override
  void onPaintUp(ToolContext c) {
    commit(_stroke, 'Paint tiles');
    _stroke = null;
    _aim = null;
    _last = null;
  }

  @override
  void onPaintCancel() {
    _stroke?.revert();
    _stroke = null;
    _aim = null;
  }

  @override
  Map<TileCoord, int> previewAt(TileAim aim, TileCoord at) {
    final stamp = state.stampIn(aim.target.data).stamp;
    if (stamp == null) return const {};
    return {for (final (c, v) in stamp.placeAt(at, aim.target.geometry)) c: v};
  }
}

/// Clears cells, as wide as the designer's brush size (`[` and `]`).
class TileEraseTool extends TileTool {
  TileEraseTool(super.scope, {super.switchTool});

  @override
  String get id => TileTools.erase;
  @override
  String get label => 'Erase tiles';
  @override
  IconData get icon => Icons.cleaning_services;
  @override
  String? get shortcut => 'D';
  @override
  int get order => 230;

  @override
  List<Widget> buildTileOptions(
    BuildContext context,
    ToolOptionsContext options,
  ) => [
    const OptionsLabel('Size'),
    BrushSizePicker(signal: options.controller.brushSize, noun: 'eraser'),
  ];
  @override
  String? get description =>
      'Clear tiles from the layer. [ and ] change the brush size.';

  TileStroke? _stroke;
  TileAim? _aim;
  TileCoord? _last;
  int _size = 1;

  /// The cells a brush [size] across covers around [at].
  static List<TileCoord> brushCells(MapGeometry g, TileCoord at, int size) {
    final r = (size - 1) ~/ 2;
    if (r <= 0) return [at];
    final centre = g.toStable(at);
    final hex = g.orientation == MapOrientation.hexagonal;
    return [
      for (var dy = -r; dy <= r; dy++)
        for (var dx = -r; dx <= r; dx++)
          // A hexagon's "square" is a hexagon: axial distance.
          if (!hex || (dx.abs() + dy.abs() + (dx + dy).abs()) ~/ 2 <= r)
            g.fromStable(TileCoord(centre.x + dx, centre.y + dy)),
    ];
  }

  void _erase(TileCoord at) {
    for (final cell in brushCells(_aim!.target.geometry, at, _size)) {
      _stroke!.set(cell, TileCell.empty);
    }
  }

  @override
  bool onPaintDown(ToolContext c) {
    final a = aim(c);
    if (a == null) return true;
    _aim = a;
    _size = c.controller.brushSize.value;
    _stroke = strokeOn(a);
    final at = cellAt(a, c.worldPosition, c);
    _erase(at);
    _last = at;
    return true;
  }

  @override
  void onPaintMove(ToolContext c) {
    final a = _aim;
    if (_stroke == null || a == null) return;
    final at = cellAt(a, c.worldPosition, c);
    if (at == _last) return;
    for (final cell in TileTool.cellsAlong(a.target.geometry, _last!, at)) {
      _erase(cell);
    }
    _last = at;
    state.hoverCell = at;
  }

  @override
  void onPaintUp(ToolContext c) {
    commit(_stroke, 'Erase tiles');
    _stroke = null;
    _aim = null;
  }

  @override
  void onPaintCancel() {
    _stroke?.revert();
    _stroke = null;
    _aim = null;
  }

  @override
  Map<TileCoord, int> previewAt(TileAim aim, TileCoord at) => {
    for (final c in brushCells(aim.target.geometry, at, _hoverSize))
      c: TileCell.empty,
  };

  int _hoverSize = 1;

  @override
  void onPointerHover(ToolContext context) {
    _hoverSize = context.controller.brushSize.value;
    super.onPointerHover(context);
  }

  @override
  void afterPick() => switchTool?.call(TileTools.stamp);
}

/// Fills with the brush: a connected run of one tile (bucket), or a dragged
/// rectangle or ellipse. G again cycles between them. A brush of several
/// tiles fills as a repeating pattern.
class TileFillTool extends TileTool {
  TileFillTool(super.scope, {super.switchTool});

  @override
  String get id => TileTools.fill;
  @override
  String get label => 'Fill';
  @override
  IconData get icon => Icons.format_color_fill;
  @override
  String? get shortcut => 'G';
  @override
  int get order => 210;

  @override
  List<Widget> buildTileOptions(
    BuildContext context,
    ToolOptionsContext options,
  ) => [
    ChoicePicker<TileFillShape>(
      signal: state.fillShape,
      options: const [
        ToolChoice(
          value: TileFillShape.bucket,
          icon: Icons.format_color_fill,
          label: 'Bucket',
          tooltip: 'Fill the connected run of the tile clicked',
        ),
        ToolChoice(
          value: TileFillShape.rect,
          icon: Icons.crop_square,
          label: 'Rect',
          tooltip: 'Drag out a filled rectangle',
        ),
        ToolChoice(
          value: TileFillShape.ellipse,
          icon: Icons.circle_outlined,
          label: 'Ellipse',
          tooltip: 'Drag out a filled ellipse',
        ),
      ],
    ),
    const OptionsDivider(),
    randomToggle(),
  ];
  @override
  String? get description =>
      'Fill with the brush: the connected run of the tile clicked, or a '
      'dragged rectangle or ellipse. Press G again to switch between them.';

  TileAim? _aim;
  TileCoord? _start;
  TileStamp? _stamp;

  /// Where the dragged shape ends now, and what it would paint — kept here
  /// rather than read back from the overlay's preview, which a key pressed
  /// mid-drag may redraw.
  TileCoord? _end;
  Map<TileCoord, int> _pending = const {};

  @override
  void onActivate() => state.paletteTerrains.value = false;

  @override
  bool onKey(LogicalKeyboardKey key, ToolContext context) {
    final m = context.modifiers;
    if (key == LogicalKeyboardKey.keyG && !m.control && !m.alt && !m.other) {
      final shapes = TileFillShape.values;
      final next = shapes[(state.fillShape.value.index + 1) % shapes.length];
      state.fillShape.value = next;
      context.controller.setStatus('Fill: ${next.name}');
      return true;
    }
    return super.onKey(key, context);
  }

  /// What [stamp] paints at [cell], repeating from [origin].
  int patternValue(
    TileAim aim,
    TileStamp stamp,
    TileCoord origin,
    TileCoord cell,
  ) {
    if (stamp.isRandom || stamp.cells.length == 1) {
      return paintValue(aim, stamp, stamp.cells.first.cell);
    }
    final g = aim.target.geometry;
    final ext = stamp.extent;
    final o = g.toStable(origin);
    final s = g.toStable(cell);
    int wrap(int v, int size) => ((v % size) + size) % size;
    final off = TileCoord(
      ext.x0 + wrap(s.x - o.x, ext.width),
      ext.y0 + wrap(s.y - o.y, ext.height),
    );
    for (final c in stamp.cells) {
      if (c.offset == off) return paintValue(aim, stamp, c.cell);
    }
    return -1; // a hole in the pattern: leave the cell alone
  }

  /// The cells of the box or ellipse from [a] to [b].
  static List<TileCoord> shapeCells(
    TileFillShape shape,
    TileCoord a,
    TileCoord b,
  ) {
    final box = TileTool.rectCells(a, b);
    if (shape != TileFillShape.ellipse) return box;
    final cx = (a.x + b.x) / 2;
    final cy = (a.y + b.y) / 2;
    final rx = (a.x - b.x).abs() / 2 + 0.5;
    final ry = (a.y - b.y).abs() / 2 + 0.5;
    return [
      for (final c in box)
        if (math.pow((c.x - cx) / rx, 2) + math.pow((c.y - cy) / ry, 2) <=
            1.0001)
          c,
    ];
  }

  Map<TileCoord, int> _fillValues(
    TileAim aim,
    Iterable<TileCoord> cells,
    TileCoord origin,
  ) {
    final stamp = _stamp!;
    return {
      for (final c in cells)
        if (patternValue(aim, stamp, origin, c) case final v when v >= 0) c: v,
    };
  }

  @override
  bool onPaintDown(ToolContext c) {
    if (state.stamp.value == null) {
      c.controller.setStatus('Pick a tile in the Tileset panel first');
      return true;
    }
    final a = aim(c, create: true);
    if (a == null) return true;
    final stamp = brushFor(a, c);
    if (stamp == null) return true;
    _stamp = stamp;
    final at = cellAt(a, c.worldPosition, c);
    if (state.fillShape.value == TileFillShape.bucket) {
      final region = TileTool.connected(
        a.target.geometry,
        a.layer.cells,
        at,
        TileTool.floodLimit(a, c),
      );
      if (region.length >= TileTool.maxRegion) {
        // Stopped part way: what it reached is a diamond round the click,
        // not the region. Nothing rather than that.
        c.controller.setStatus(
          'That region is more than ${TileTool.maxRegion} cells: zoom in, '
          'or fill a rectangle',
        );
        return true;
      }
      final stroke = strokeOn(a);
      _fillValues(a, region, at).forEach(stroke.set);
      commit(stroke, 'Fill tiles');
      c.controller.setStatus(
        'Filled ${region.length} cell${region.length == 1 ? '' : 's'}',
      );
      return true;
    }
    _aim = a;
    _start = at;
    _end = at;
    _show(_fillValues(a, [at], at));
    return true;
  }

  void _show(Map<TileCoord, int> values) {
    _pending = values;
    state.preview = values;
  }

  @override
  void onPaintMove(ToolContext c) {
    final a = _aim;
    final start = _start;
    if (a == null || start == null) return;
    final at = cellAt(a, c.worldPosition, c);
    // Only when the shape changes: a move within the end cell is the same
    // fill, and laying one out is the costly part.
    if (at == _end) return;
    _end = at;
    final area = ((at.x - start.x).abs() + 1) * ((at.y - start.y).abs() + 1);
    if (area > TileTool.maxRegion) {
      c.controller.setStatus(
        'Too big to fill at once: at most ${TileTool.maxRegion} cells',
      );
      _show(const {});
      return;
    }
    _show(_fillValues(a, shapeCells(state.fillShape.value, start, at), start));
  }

  @override
  void onPaintUp(ToolContext c) {
    final a = _aim;
    if (a != null && _pending.isNotEmpty) {
      final stroke = strokeOn(a);
      _pending.forEach(stroke.set);
      commit(
        stroke,
        state.fillShape.value == TileFillShape.ellipse
            ? 'Fill ellipse'
            : 'Fill rectangle',
      );
    }
    _finish();
  }

  @override
  void onPaintCancel() => _finish();

  void _finish() {
    state.preview = const {};
    _pending = const {};
    _aim = null;
    _start = null;
    _end = null;
  }

  @override
  Map<TileCoord, int> previewAt(TileAim aim, TileCoord at) {
    final stamp = state.stampIn(aim.target.data).stamp;
    if (stamp == null || stamp.cells.isEmpty) return const {};
    return {at: stamp.cells.first.cell};
  }
}
