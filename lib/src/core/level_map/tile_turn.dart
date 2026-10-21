import 'dart:math' as math;

import 'package:just_game_engine/just_game_engine.dart';

import 'tile_commands.dart';

/// Turning a block of tiles in steps — tiles picked with Select tiles, or
/// all of a piece's. The block turns about its middle and each tile turns
/// with it, as a stamp brush does (Z).
abstract final class TileTurn {
  /// Steps in a whole turn on [g]: quarters, or sixths on a hexagonal map.
  static int stepsPerTurn(MapGeometry g) =>
      g.orientation == MapOrientation.hexagonal ? 6 : 4;

  /// One step, in radians.
  static double stepAngle(MapGeometry g) => 2 * math.pi / stepsPerTurn(g);

  /// The cell [cells] turn about: the middle of their block, the cell a
  /// stamp picks a block up by.
  static TileCoord pivotOf(MapGeometry g, Iterable<TileCoord> cells) {
    final stable = [for (final c in cells) g.toStable(c)];
    final xs = stable.map((c) => c.x);
    final ys = stable.map((c) => c.y);
    final minX = xs.reduce(math.min);
    final minY = ys.reduce(math.min);
    final w = xs.reduce(math.max) - minX + 1;
    final h = ys.reduce(math.max) - minY + 1;
    return g.fromStable(TileCoord(minX + w ~/ 2, minY + h ~/ 2));
  }

  /// Turns the tiles at [cells] of [stroke]'s layer [steps] steps —
  /// clockwise when positive — about [pivot] (the middle of the block when
  /// not given), writing through [stroke]. Returns where [cells] are now,
  /// empty ones included, so a selection can follow its tiles.
  static Set<TileCoord> turn(
    TileStroke stroke,
    MapGeometry g,
    Set<TileCoord> cells,
    int steps, {
    TileCoord? pivot,
  }) {
    if (cells.isEmpty) return cells;
    final n = steps.abs() % stepsPerTurn(g);
    if (n == 0) return cells;
    final clockwise = steps > 0;
    final at = pivot ?? pivotOf(g, cells);
    final source = stroke.layer.cells;
    // The tiles, and the shape of the block with its gaps, turned alike.
    var tiles = TileStamp.capture(
      source,
      cells,
      g,
      anchor: at,
      skipEmpty: true,
    );
    var shape = TileStamp.capture(source, cells, g, anchor: at);
    for (var i = 0; i < n; i++) {
      tiles = tiles.turned(g, clockwise: clockwise);
      shape = shape.turned(g, clockwise: clockwise);
    }
    for (final c in cells) {
      stroke.set(c, TileCell.empty);
    }
    for (final (c, value) in tiles.placeAt(at, g)) {
      stroke.set(c, value);
    }
    return {for (final (c, _) in shape.placeAt(at, g)) c};
  }
}
