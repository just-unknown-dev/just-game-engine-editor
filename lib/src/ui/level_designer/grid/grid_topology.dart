import 'dart:ui';


import '../state/designer_geometry.dart';
import '../../../core/view/editor_view.dart';

/// The shape of the cells the designer paints, snaps and fills on.
///
/// Everything that used to assume squares — cell lookup, brushes, bucket
/// fill, merging painted cells into entities, the grid lines themselves —
/// asks this instead. Square is the default; a module supplies another
/// (`HexGrid` ships as one). Cells are addressed by [Point2]: column and row
/// for squares, axial `q`/`r` for hexes.
abstract class GridTopology {
  const GridTopology();

  /// Stable identifier, e.g. `'square'`.
  String get id;

  /// The cell containing [world].
  Point2 cellAt(Offset world, double cellSize);

  /// The centre of [cell], in world units.
  Offset cellCenter(Point2 cell, double cellSize);

  /// The box around [cell].
  Rect cellBounds(Point2 cell, double cellSize);

  /// The outline of [cell], for painting.
  Path cellPath(Point2 cell, double cellSize);

  /// The cells sharing an edge with [cell]: four for squares, six for hexes.
  Iterable<Point2> neighbours(Point2 cell);

  /// Every cell [rect] touches; a zero-size rect still yields the cell it
  /// sits in.
  Set<Point2> cellsIn(Rect rect, double cellSize);

  /// The cells of a brush [size] wide centred on [cell].
  Iterable<Point2> brush(Point2 cell, int size);

  /// The range of cells a world [rect] spans, as a rect in cell coordinates
  /// (right and bottom exclusive). What a bucket fill is bounded by.
  Rect cellRange(Rect rect, double cellSize);

  /// [value] snapped along one axis, where that means something. A hex grid
  /// has no axis to snap along and returns [value].
  double snapValue(double value, double cellSize) => value;

  /// [world] snapped to the grid.
  Offset snapPoint(Offset world, double cellSize);

  /// [rect] moved so it sits on the grid; its size is kept.
  Rect snapRect(Rect rect, double cellSize);

  /// Painted [cells] merged into as few world-space rectangles as possible,
  /// or null when cells of this shape cannot merge into rectangles at all —
  /// the caller then places one entity per cell at its bounds.
  List<Rect>? merge(Set<Point2> cells, double cellSize);

  /// Draws the grid over the visible world.
  void paintGrid(
    Canvas canvas,
    EditorView camera,
    Size canvasSize, {
    required double cellSize,
  });

  /// The empty cells reachable from [start] without crossing [blocked],
  /// moving through [neighbours]: a bucket fill.
  ///
  /// Only fills inside [limit] (in cell coordinates). A region that reaches
  /// the edge of the limit is not enclosed — it would leak out into the rest
  /// of the world — so the result is null rather than a fill of everything.
  /// Also null past [maxCells]. Empty means [start] itself is blocked.
  Set<Point2>? floodFill(
    Point2 start,
    Set<Point2> blocked, {
    required Rect limit,
    int maxCells = 20000,
  }) {
    if (blocked.contains(start)) return const {};
    final minX = limit.left.floor();
    final minY = limit.top.floor();
    final maxX = limit.right.ceil() - 1;
    final maxY = limit.bottom.ceil() - 1;
    bool inside(Point2 p) =>
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY;
    if (!inside(start)) return null;

    final filled = <Point2>{start};
    final queue = <Point2>[start];
    while (queue.isNotEmpty) {
      final cell = queue.removeLast();
      if (cell.x == minX ||
          cell.x == maxX ||
          cell.y == minY ||
          cell.y == maxY) {
        return null; // touched the edge: not enclosed
      }
      for (final next in neighbours(cell)) {
        if (blocked.contains(next) || !filled.add(next)) continue;
        if (filled.length > maxCells) return null;
        queue.add(next);
      }
    }
    return filled;
  }
}
