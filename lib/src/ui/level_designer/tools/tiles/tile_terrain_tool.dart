import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

import '../../../../core/level_map/tile_commands.dart';
import '../../../../core/level_map/tile_edit_state.dart';
import '../level_tool.dart';
import 'tile_tool_base.dart';

/// Paints terrains: grass, water, a road. Each corner or edge painted gets
/// the chosen terrain, and every cell touching it gets the tile whose
/// corners and edges join what is around it — Tiled's terrain brush.
///
/// Right-click takes the terrain under the pointer. Orthogonal, isometric
/// and staggered maps only: a hexagonal cell's six sides are not what a
/// tileset's terrain sets describe.
class TerrainTool extends TileTool {
  TerrainTool(super.scope, {super.switchTool});

  @override
  String get id => TileTools.terrain;
  @override
  String get label => 'Terrain';
  @override
  IconData get icon => Icons.landscape;
  @override
  String? get shortcut => 'T';
  @override
  int get order => 220;

  @override
  List<Widget> buildTileOptions(
    BuildContext context,
    ToolOptionsContext options,
  ) => [
    SignalBuilder<TerrainChoice?>(
      signal: state.terrain,
      builder: (context, choice, _) {
        final color = _chosenColor(choice, options.world);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color == null ? null : Color(color.color),
                border: Border.all(color: const Color(0x66FFFFFF)),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              color == null
                  ? 'Choose a terrain in the Tileset panel'
                  : color.name.isEmpty
                  ? 'Terrain ${choice!.color}'
                  : color.name,
              style: const TextStyle(fontSize: 11, color: Color(0xFFCCCCCC)),
            ),
          ],
        );
      },
    ),
  ];

  /// The terrain [choice] names on the map being painted, or null.
  WangColorData? _chosenColor(TerrainChoice? choice, World world) {
    if (choice == null) return null;
    final target = state.peek(world);
    final ts = target?.tilesetAt(choice.slot);
    if (ts == null || choice.set >= ts.wangSets.length) return null;
    final colors = ts.wangSets[choice.set].colors;
    if (choice.color < 1 || choice.color > colors.length) return null;
    return colors[choice.color - 1];
  }

  @override
  String? get description =>
      'Paint a terrain: the tiles around it are chosen so the terrains '
      'join. Choose one in the Tileset panel\'s Terrains; right-click takes '
      'the terrain under the pointer.';

  TileStroke? _stroke;
  TileAim? _aim;
  (WangFiller, int)? _filler;
  Offset? _last;
  WangTarget? _lastTarget;
  final Set<TileCoord> _unmatched = {};

  (Object, WangFiller)? _cache;

  /// The filler for [a] with the chosen terrain and its colour — or null,
  /// having said why unless [quiet].
  (WangFiller, int)? fillerFor(TileAim a, ToolContext c, {bool quiet = false}) {
    void say(String text) {
      if (!quiet) c.controller.setStatus(text);
    }

    final choice = state.terrain.value;
    if (choice == null) {
      say('Choose a terrain first: the Tileset panel, Terrains');
      return null;
    }
    final g = a.target.geometry;
    if (!g.hasLattice) {
      say(
        'Terrain painting works on square-cornered grids: a hexagonal map '
        'has none. Paint it with the stamp',
      );
      return null;
    }
    final ts = a.target.tilesetAt(choice.slot);
    if (ts == null || choice.set >= ts.wangSets.length) {
      say('That terrain\'s tileset is not on this map');
      return null;
    }
    final set = ts.wangSets[choice.set];
    if (choice.color < 1 || choice.color > set.colors.length) {
      say('That terrain is no longer in ${set.name}');
      return null;
    }
    final key = Object.hash(
      identityHashCode(ts),
      ts.revision,
      choice,
      identityHashCode(a.target.data),
      a.target.data.revision,
    );
    final cached = _cache;
    if (cached != null && cached.$1 == key) return (cached.$2, choice.color);
    final filler = WangFiller(
      set: set,
      tileset: ts,
      slot: choice.slot,
      geometry: g,
      random: random,
    );
    _cache = (key, filler);
    return (filler, choice.color);
  }

  @override
  bool onPointerDown(ToolContext context) {
    final c = context;
    if (c.button == ToolButton.secondary ||
        (c.button == ToolButton.primary && c.isAltDown)) {
      pickTerrain(c);
      return true;
    }
    return super.onPointerDown(c);
  }

  @override
  bool onPaintDown(ToolContext c) {
    if (state.terrain.value == null) {
      c.controller.setStatus(
        'Choose a terrain first: the Tileset panel, Terrains',
      );
      return true;
    }
    final a = aim(c, create: true);
    if (a == null) return true;
    final f = fillerFor(a, c);
    if (f == null) return true;
    _aim = a;
    _filler = f;
    _stroke = strokeOn(a);
    _lastTarget = null;
    _unmatched.clear();
    final local = TileTool.localPoint(a, c.worldPosition, c);
    _paintAt(local);
    _last = local;
    return true;
  }

  void _paintAt(Offset local) {
    final a = _aim!;
    final (filler, color) = _filler!;
    final target = WangFiller.targetAt(
      a.target.geometry,
      local,
      filler.set.type,
    );
    if (target == _lastTarget) return;
    _lastTarget = target;
    final result = filler.paint(a.layer.cells, [target], color);
    result.changes.forEach(_stroke!.set);
    _unmatched
      ..removeAll(result.changes.keys)
      ..addAll(result.unmatched);
  }

  @override
  void onPaintMove(ToolContext c) {
    final a = _aim;
    final from = _last;
    if (_stroke == null || a == null || from == null) return;
    final to = TileTool.localPoint(a, c.worldPosition, c);
    final g = a.target.geometry;
    // Every corner and edge passed over, not only where the pointer was
    // seen: a quick stroke leaves no gaps.
    final step = math.max(1.0, math.min(g.tileWidth, g.tileHeight) / 4);
    final n = math.max(1, ((to - from).distance / step).ceil());
    for (var i = 1; i <= n; i++) {
      _paintAt(Offset.lerp(from, to, i / n)!);
    }
    _last = to;
    state.hoverCell = g.cellAt(to);
  }

  @override
  void onPaintUp(ToolContext c) {
    final stroke = _stroke;
    if (stroke == null) return;
    commit(stroke, 'Paint terrain');
    if (_unmatched.isNotEmpty) {
      final n = _unmatched.length;
      c.controller.setStatus(
        '$n cell${n == 1 ? '' : 's'} had no exact tile: '
        '${_filler!.$1.set.name} is missing some combinations',
      );
    }
    _end();
  }

  @override
  void onPaintCancel() {
    _stroke?.revert();
    _end();
  }

  void _end() {
    _stroke = null;
    _aim = null;
    _filler = null;
    _last = null;
    _lastTarget = null;
  }

  @override
  void onPointerHover(ToolContext context) {
    super.onPointerHover(context);
    final a = aim(context, forEdit: false, quiet: true);
    if (a == null) return;
    final f = fillerFor(a, context, quiet: true);
    if (f == null) return;
    final local = TileTool.localPoint(a, context.worldPosition, context);
    final target = WangFiller.targetAt(a.target.geometry, local, f.$1.set.type);
    state.preview = f.$1.paint(a.layer.cells, [target], f.$2).changes;
  }

  @override
  void onActivate() => state.paletteTerrains.value = true;

  // ── Picking a terrain up ─────────────────────────────────────────────────

  /// Chooses the terrain at the corner or edge under the pointer.
  void pickTerrain(ToolContext c) {
    final a = aim(c, forEdit: false);
    if (a == null) return;
    final g = a.target.geometry;
    if (!g.hasLattice) {
      c.controller.setStatus('Hexagonal maps have no terrains to take');
      return;
    }
    final local = TileTool.localPoint(a, c.worldPosition, c);
    final cell = g.cellAt(local);
    final value = a.layer.cells.cellAt(cell.x, cell.y);
    if (TileCell.isEmpty(value)) {
      c.controller.setStatus('No tile there to take a terrain from');
      return;
    }
    final slot = TileCell.slotOf(value);
    final ts = a.target.tilesetAt(slot);
    if (ts != null) {
      for (var i = 0; i < ts.wangSets.length; i++) {
        final set = ts.wangSets[i];
        final base = set.wangIds[TileCell.localIdOf(value)];
        if (base == null) continue;
        final id = WangFiller.transformId(base, TileCell.flagsOf(value));
        final target = WangFiller.targetAt(g, local, set.type);
        final color = colorAt(id, target, g.toLattice(cell));
        if (color < 1 || color > set.colors.length) continue;
        state.terrain.value = TerrainChoice(slot: slot, set: i, color: color);
        c.controller.setStatus('Terrain: ${set.colors[color - 1].name}');
        return;
      }
    }
    c.controller.setStatus('That tile has no terrain');
  }

  /// The colour Wang id [id] of the cell at lattice [l] shows at [target].
  static int colorAt(List<int> id, WangTarget target, TileCoord l) {
    final at = target.at;
    switch (target.kind) {
      case WangFeatureKind.corner:
        if (at == l) return id[WangSetData.topLeft];
        if (at == TileCoord(l.x + 1, l.y)) return id[WangSetData.topRight];
        if (at == TileCoord(l.x + 1, l.y + 1)) {
          return id[WangSetData.bottomRight];
        }
        return id[WangSetData.bottomLeft];
      case WangFeatureKind.edge:
        if (target.horizontal) {
          return at == l ? id[WangSetData.top] : id[WangSetData.bottom];
        }
        return at == l ? id[WangSetData.left] : id[WangSetData.right];
      case WangFeatureKind.cell:
        final counts = <int, int>{};
        for (final c in id) {
          if (c > 0) counts[c] = (counts[c] ?? 0) + 1;
        }
        if (counts.isEmpty) return 0;
        return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }
  }
}
