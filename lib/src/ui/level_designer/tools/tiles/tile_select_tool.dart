import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../../../core/level_map/tile_turn.dart';
import '../../../../core/state/transform_mode.dart';
import '../../../overlay/gizmo_painter.dart' show GizmoHandle;
import '../../../overlay/transform_gizmo.dart';

import '../../../../core/level_map/tile_commands.dart';
import '../../../../core/level_map/level_map_documents.dart';
import '../../../../core/level_map/tile_edit_state.dart';
import '../../../../core/level_map/tile_selection_ops.dart';
import '../../controls/designer_controls.dart';
import '../level_tool.dart';
import 'tile_tool_base.dart';

/// Selects cells of the layer being painted: a dragged box, the connected
/// run of one tile (the wand), or every cell holding one tile. V again
/// cycles between them.
///
/// Shift adds to the selection and Ctrl takes away. Dragging the selection
/// moves its tiles. The selection shows the Move or Rotate gizmo, as the
/// toolbar says (W, R): an arrow moves the tiles along it, the ring turns
/// them a quarter at a time. Tiles do not scale. Ctrl+C copies, Ctrl+X cuts, Delete clears, Ctrl+A
/// selects every painted cell and Esc lets go. Enter — or *Make entity*,
/// or the right-click menu while tiles are selected — cuts the selected
/// tiles out into an entity of their own.
class TileSelectTool extends TileTool {
  TileSelectTool(super.scope, {super.switchTool});

  @override
  String get id => TileTools.select;
  @override
  String get label => 'Select tiles';
  @override
  IconData get icon => Icons.highlight_alt;
  @override
  // W, E and R are Move, Scale and Rotate.
  String? get shortcut => 'V';
  @override
  int get order => 240;

  /// A right-click on a selection opens its menu — make an entity, copy,
  /// cut, delete; with none, it picks tiles up, as every tile tool's does.
  @override
  bool get acceptsSecondaryButton => state.selection.value.isEmpty;

  @override
  List<Widget> buildTileOptions(
    BuildContext context,
    ToolOptionsContext options,
  ) => [
    ChoicePicker<TileSelectMode>(
      signal: state.selectMode,
      options: const [
        ToolChoice(
          value: TileSelectMode.rect,
          icon: Icons.highlight_alt,
          label: 'Box',
          tooltip: 'Drag out a box',
        ),
        ToolChoice(
          value: TileSelectMode.wand,
          icon: Icons.auto_fix_high,
          label: 'Wand',
          tooltip: 'The connected run of the tile clicked',
        ),
        ToolChoice(
          value: TileSelectMode.sameTile,
          icon: Icons.select_all,
          label: 'Same',
          tooltip: 'Every cell holding the tile clicked',
        ),
      ],
    ),
    const OptionsDivider(),
    DesignerToggle(
      icon: Icons.open_in_new,
      label: 'Make entity',
      isOn: false,
      tooltip:
          'Cut the selected tiles out into an entity of their own, on this '
          'layer (Enter)',
      onTap: () => makeEntity(options.world, options.controller.setStatus),
    ),
  ];

  /// Cuts the selected tiles out of the layer being painted into an entity
  /// of their own — see [TileSelectionOps.makeEntity].
  void makeEntity(World world, void Function(String message) say) =>
      TileSelectionOps.makeEntity(scope, world, say);

  @override
  String? get description =>
      'Select tiles: a box, the connected run of a tile, or every cell of a '
      'tile (V again switches). Shift adds, Ctrl takes away, drag to move. '
      'Ctrl+C / Ctrl+X copy and cut, Delete clears, Enter makes an entity.';

  TileAim? _aim;
  TileCoord? _start;
  ({bool add, bool subtract}) _combine = (add: false, subtract: false);

  TileStroke? _moving;
  TileCoord? _moveFrom;

  /// An arrow of the move gizmo: the move keeps to its axis.
  Axis? _axis;

  /// Whether the move began on the gizmo, where a click is only a click.
  bool _viaGizmo = false;

  /// Set while a click that fell through the ring is replayed.
  bool _throughGizmo = false;

  // Turning the selection with the rotate ring.
  TileStroke? _turning;
  TileAim? _turnAim;
  Set<TileCoord> _turnCells = const {};
  TileCoord? _turnPivot;
  Offset _turnCentre = Offset.zero;
  double _turnFrom = 0;
  int _turnSteps = 0;
  bool _turnHeld = false;

  /// The gizmo the selection shows: All (arrows and ring), Move or Rotate,
  /// as the toolbar says — All when it says Scale.
  TransformMode? _gizmo(ToolContext c) => TransformModes.shown(
    c.controller.view.transformMode.value,
    TransformModes.tiles,
  );

  /// Where [cells] of [layer] are drawn in the world now, with [camera]
  /// where it is.
  static Rect? cellsBounds(
    LevelMapTarget target,
    MapLayerData layer,
    Iterable<TileCoord> cells,
    Offset? camera,
  ) {
    final shift = target.layerShift(layer, camera);
    final g = target.geometry;
    double? l, t, r, b;
    for (final c in cells) {
      for (final p in g.cellPolygon(c.x, c.y)) {
        final x = p.dx + shift.dx;
        final y = p.dy + shift.dy;
        l = l == null ? x : math.min(l, x);
        t = t == null ? y : math.min(t, y);
        r = r == null ? x : math.max(r, x);
        b = b == null ? y : math.max(b, y);
      }
    }
    return l == null ? null : Rect.fromLTRB(l, t!, r!, b!);
  }

  /// Starts what a press on the selection's gizmo means, when it is on it.
  bool _onGizmo(ToolContext c, TileAim a) {
    final cells = state.selection.value;
    if (cells.isEmpty || c.isShiftDown || c.isCtrlDown) return false;
    final bounds = cellsBounds(a.target, a.layer, cells, c.camera?.position);
    if (bounds == null) return false;
    final px = c.unitsPerPixel;
    final mode = _gizmo(c);
    if (mode == null) return false;
    // All has both: the arrows, then the ring around them.
    if (mode != TransformMode.rotate) {
      final handle = TransformGizmo.moveHandleAt(
        c.worldPosition,
        bounds.center,
        px: px,
      );
      if (handle != GizmoHandle.none) {
        _lift(c, cellAt(a, c.worldPosition, c));
        _viaGizmo = true;
        _axis = switch (handle) {
          GizmoHandle.translateX => Axis.horizontal,
          GizmoHandle.translateY => Axis.vertical,
          _ => null,
        };
        return true;
      }
    }
    if (mode != TransformMode.rotate && mode != TransformMode.all) {
      return false;
    }
    var radius = scope.handleLayout.ringRadius(bounds, px);
    // All's ring stands out past the arrows, which would otherwise take
    // its presses.
    if (mode == TransformMode.all) {
      radius = TransformGizmo.ringClearOfArrows(radius, px: px);
    }
    if (!TransformGizmo.onRing(
      c.worldPosition,
      bounds.center,
      radius,
      px: px,
    )) {
      return false;
    }
    final edit = aim(c);
    if (edit == null) return true;
    _turnHeld = true;
    _turnAim = edit;
    _turnCells = cells;
    _turnPivot = TileTurn.pivotOf(edit.target.geometry, cells);
    _turnCentre = bounds.center;
    _turnFrom = _angle(_turnCentre, c.worldPosition);
    _turnSteps = 0;
    return true;
  }

  static double _angle(Offset centre, Offset at) =>
      math.atan2(at.dy - centre.dy, at.dx - centre.dx);

  /// Turns the selected tiles the whole steps the ring has been dragged
  /// round, from where they started; the selection follows them.
  void _turn(ToolContext c) {
    final a = _turnAim!;
    final g = a.target.geometry;
    final steps =
        ((_angle(_turnCentre, c.worldPosition) - _turnFrom) /
                TileTurn.stepAngle(g))
            .round();
    if (steps == _turnSteps) return;
    _turning?.revert();
    _turnSteps = steps;
    final stroke = strokeOn(a);
    state.selection.value = Set.unmodifiable(
      TileTurn.turn(stroke, g, _turnCells, steps, pivot: _turnPivot),
    );
    _turning = stroke;
    c.controller.setStatus(
      '${(steps * TileTurn.stepAngle(g) * 180 / math.pi).round()}°',
    );
  }

  // ── Choosing cells ───────────────────────────────────────────────────────

  /// The topmost shown layer of [target] with a tile under [world], where
  /// each layer is drawn with the camera at [camera]; null when none has.
  static MapLayerData? layerUnder(
    LevelMapTarget target,
    Offset world,
    Offset? camera,
  ) {
    for (final layer in target.data.layers.reversed) {
      if (!layer.visible) continue;
      final cell = target.geometry.cellAt(
        world - target.layerShift(layer, camera),
      );
      if (!TileCell.isEmpty(layer.cells.cellAt(cell.x, cell.y))) return layer;
    }
    return null;
  }

  /// Every cell of [aim]'s layer holding [value]. Empty cells are counted
  /// only inside what is painted: an infinite map is mostly empty.
  static Set<TileCoord> cellsHolding(TileAim aim, int value) {
    final cells = aim.layer.cells;
    if (!TileCell.isEmpty(value)) {
      return {
        for (final (x, y, v) in cells.cells)
          if (v == value) TileCoord(x, y),
      };
    }
    final used = cells.usedBounds;
    if (used == null) return const {};
    return {
      for (var y = used.top.toInt(); y < used.bottom.toInt(); y++)
        for (var x = used.left.toInt(); x < used.right.toInt(); x++)
          if (TileCell.isEmpty(cells.cellAt(x, y))) TileCoord(x, y),
    };
  }

  void _apply(Set<TileCoord> cells, ToolContext c) {
    final current = state.selection.value;
    final next = _combine.add
        ? {...current, ...cells}
        : _combine.subtract
        ? current.difference(cells)
        : cells;
    state.selection.value = Set.unmodifiable(next);
    final n = next.length;
    // Which layer: a selection is of one, and not always the one expected.
    final target = state.peek(c.world);
    final layer = target == null ? null : state.peekLayer(target);
    c.controller.setStatus(
      n == 0
          ? 'No tiles selected'
          : '$n cell${n == 1 ? '' : 's'} selected'
                '${layer == null ? '' : ' on ${layer.name}'}',
    );
  }

  @override
  bool onPaintDown(ToolContext c) {
    var a = aim(c, forEdit: false);
    if (a == null) return true;
    if (!_throughGizmo && _onGizmo(c, a)) return true;
    var at = cellAt(a, c.worldPosition, c);
    _combine = (add: c.isShiftDown, subtract: c.isCtrlDown && !c.isShiftDown);
    final plain = !_combine.add && !_combine.subtract;
    if (plain && state.selection.value.contains(at)) {
      _lift(c, at);
      return true;
    }
    // A fresh selection begun on tiles the layer being painted does not
    // have is of the layer they are on: what is selected is what is seen.
    if (plain && TileCell.isEmpty(a.layer.cells.cellAt(at.x, at.y))) {
      final under = layerUnder(a.target, c.worldPosition, c.camera?.position);
      if (under != null && under.id != a.layer.id) {
        state.layerId.value = under.id;
        c.controller.activeLayerId.value = under.sortLayerId;
        a = (target: a.target, layer: under);
        at = cellAt(a, c.worldPosition, c);
        c.controller.setStatus(
          'Selecting on ${under.name}: its tiles are here',
        );
      }
    }
    switch (state.selectMode.value) {
      case TileSelectMode.rect:
        _aim = a;
        _start = at;
        state.dragArea = (at, at);
      case TileSelectMode.wand:
        _apply(
          TileTool.connected(
            a.target.geometry,
            a.layer.cells,
            at,
            TileTool.floodLimit(a, c),
          ),
          c,
        );
      case TileSelectMode.sameTile:
        _apply(cellsHolding(a, a.layer.cells.cellAt(at.x, at.y)), c);
    }
    return true;
  }

  @override
  void onPaintMove(ToolContext c) {
    if (_turnHeld) {
      _turn(c);
      return;
    }
    final a = _aim;
    if (a == null) return;
    final at = cellAt(a, c.worldPosition, c);
    state.hoverCell = at;
    if (_moving != null) {
      final g = a.target.geometry;
      final s = g.toStable(at);
      state.floatOffset = TileCoord(
        _axis == Axis.vertical ? 0 : s.x - _moveFrom!.x,
        _axis == Axis.horizontal ? 0 : s.y - _moveFrom!.y,
      );
      return;
    }
    if (_start != null) state.dragArea = (_start!, at);
  }

  @override
  void onPaintUp(ToolContext c) {
    if (_turnHeld) {
      final stroke = _turning;
      if (_turnSteps != 0) {
        commit(stroke, 'Rotate tiles');
        _end();
        return;
      }
      // A click on the ring, not a turn: what the click would have done
      // without it there — the ring lies across the tiles round the
      // selection, and picking one of those is the likelier aim.
      stroke?.revert();
      state.selection.value = Set.unmodifiable(_turnCells);
      _end();
      _throughGizmo = true;
      onPaintDown(c);
      _throughGizmo = false;
      onPaintUp(c);
      return;
    }
    if (_moving != null) {
      _drop(c);
    } else {
      final area = state.dragArea;
      if (area != null) {
        _apply(TileTool.rectCells(area.$1, area.$2).toSet(), c);
      }
    }
    _end();
  }

  @override
  void onPaintCancel() {
    _moving?.revert();
    if (_turning != null) {
      _turning!.revert();
      state.selection.value = Set.unmodifiable(_turnCells);
    }
    _end();
  }

  void _end() {
    state
      ..dragArea = null
      ..floating = const {}
      ..floatOffset = const TileCoord(0, 0);
    _aim = null;
    _start = null;
    _moving = null;
    _moveFrom = null;
    _axis = null;
    _viaGizmo = false;
    _turning = null;
    _turnAim = null;
    _turnCells = const {};
    _turnPivot = null;
    _turnSteps = 0;
    _turnHeld = false;
  }

  // ── Moving ───────────────────────────────────────────────────────────────

  /// Lifts the selected tiles off the layer; they follow the pointer until
  /// dropped.
  void _lift(ToolContext c, TileCoord at) {
    final a = aim(c);
    if (a == null) return;
    final stroke = strokeOn(a);
    final floating = <TileCoord, int>{};
    for (final cell in state.selection.value) {
      final value = a.layer.cells.cellAt(cell.x, cell.y);
      if (TileCell.isEmpty(value)) continue;
      floating[cell] = value;
      stroke.set(cell, TileCell.empty);
    }
    _aim = a;
    _moving = stroke;
    _moveFrom = a.target.geometry.toStable(at);
    state
      ..floating = floating
      ..floatOffset = const TileCoord(0, 0);
  }

  void _drop(ToolContext c) {
    final stroke = _moving!;
    final a = _aim!;
    final g = a.target.geometry;
    final offset = state.floatOffset;
    if (offset.x == 0 && offset.y == 0) {
      stroke.revert();
      // A click on the gizmo, not a drag: nothing.
      if (_viaGizmo) return;
      // A click inside the selection, not a drag: let go of it, as Tiled
      // does.
      state.selection.value = const {};
      c.controller.setStatus('No tiles selected');
      return;
    }
    state.floating.forEach(
      (cell, value) => stroke.set(state.floated(g, cell), value),
    );
    state.selection.value = Set.unmodifiable({
      for (final cell in state.selection.value) state.floated(g, cell),
    });
    commit(stroke, 'Move tiles');
  }

  // ── Keys ─────────────────────────────────────────────────────────────────

  @override
  bool onKey(LogicalKeyboardKey key, ToolContext context) {
    final c = context;
    final m = c.modifiers;
    final bare = !m.control && !m.alt && !m.shift;
    if (key == LogicalKeyboardKey.keyV && bare) {
      final modes = TileSelectMode.values;
      final next = modes[(state.selectMode.value.index + 1) % modes.length];
      state.selectMode.value = next;
      c.controller.setStatus(switch (next) {
        TileSelectMode.rect => 'Select: box',
        TileSelectMode.wand => 'Select: connected tiles',
        TileSelectMode.sameTile => 'Select: every cell of a tile',
      });
      return true;
    }
    // Ctrl+Shift chords open docks: not ours.
    if (m.control && !m.alt && !m.shift) {
      switch (key) {
        case LogicalKeyboardKey.keyC:
          TileSelectionOps.copy(scope, c.world, c.controller.setStatus);
          return true;
        case LogicalKeyboardKey.keyX:
          TileSelectionOps.cut(scope, c.world, c.controller.setStatus);
          return true;
        case LogicalKeyboardKey.keyA:
          final a = aim(c, forEdit: false);
          if (a != null) {
            _combine = (add: false, subtract: false);
            _apply({
              for (final (x, y, v) in a.layer.cells.cells)
                if (!TileCell.isEmpty(v)) TileCoord(x, y),
            }, c);
          }
          return true;
      }
    }
    if (!m.control && !m.alt) {
      if (key == LogicalKeyboardKey.delete ||
          key == LogicalKeyboardKey.backspace) {
        // Kept even with nothing selected: the map's entity is usually the
        // selected one, and Delete must not remove it from under the brush.
        TileSelectionOps.delete(scope, c.world, c.controller.setStatus);
        return true;
      }
      if ((key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter) &&
          !m.shift &&
          state.selection.value.isNotEmpty) {
        makeEntity(c.world, c.controller.setStatus);
        return true;
      }
      if (key == LogicalKeyboardKey.escape &&
          state.selection.value.isNotEmpty) {
        state.selection.value = const {};
        c.controller.setStatus('No tiles selected');
        return true;
      }
    }
    return super.onKey(key, c);
  }

  @override
  void afterPick() => switchTool?.call(TileTools.stamp);
}
