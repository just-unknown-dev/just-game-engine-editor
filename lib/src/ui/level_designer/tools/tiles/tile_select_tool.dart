import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../../../core/level_map/tile_commands.dart';
import '../../../../core/level_map/level_map_documents.dart';
import '../../../../core/level_map/tile_edit_state.dart';
import '../../../../core/level_map/tile_selection_ops.dart';
import '../../controls/designer_controls.dart';
import '../level_tool.dart';
import 'tile_tool_base.dart';

/// Selects cells of the layer being painted: a dragged box, the connected
/// run of one tile (the wand), or every cell holding one tile. W again
/// cycles between them.
///
/// Shift adds to the selection and Ctrl takes away. Dragging the selection
/// moves its tiles. Ctrl+C copies, Ctrl+X cuts, Delete clears, Ctrl+A
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
  String? get shortcut => 'W';
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
      'tile (W again switches). Shift adds, Ctrl takes away, drag to move. '
      'Ctrl+C / Ctrl+X copy and cut, Delete clears, Enter makes an entity.';

  TileAim? _aim;
  TileCoord? _start;
  ({bool add, bool subtract}) _combine = (add: false, subtract: false);

  TileStroke? _moving;
  TileCoord? _moveFrom;

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
    final a = _aim;
    if (a == null) return;
    final at = cellAt(a, c.worldPosition, c);
    state.hoverCell = at;
    if (_moving != null) {
      final g = a.target.geometry;
      final s = g.toStable(at);
      state.floatOffset = TileCoord(s.x - _moveFrom!.x, s.y - _moveFrom!.y);
      return;
    }
    if (_start != null) state.dragArea = (_start!, at);
  }

  @override
  void onPaintUp(ToolContext c) {
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
      // A click inside the selection, not a drag: let go of it, as Tiled
      // does.
      stroke.revert();
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
    if (key == LogicalKeyboardKey.keyW && bare) {
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
