import 'dart:math' as math;
import 'dart:ui';

import '../state/designer_geometry.dart';
import 'grid_topology.dart';
import '../../../core/theme/viewport_look.dart';
import '../../../core/view/editor_view.dart';

/// The default grid: axis-aligned squares of [cellSize] on a side.
class SquareGrid extends GridTopology {
  const SquareGrid();

  /// Below this many screen pixels between lines, lines are thinned out.
  static const double minScreenSpacing = 8;

  @override
  String get id => 'square';

  @override
  Point2 cellAt(Offset world, double cellSize) =>
      Point2((world.dx / cellSize).floor(), (world.dy / cellSize).floor());

  @override
  Offset cellCenter(Point2 cell, double cellSize) =>
      Offset((cell.x + 0.5) * cellSize, (cell.y + 0.5) * cellSize);

  @override
  Rect cellBounds(Point2 cell, double cellSize) =>
      Rect.fromLTWH(cell.x * cellSize, cell.y * cellSize, cellSize, cellSize);

  @override
  Path cellPath(Point2 cell, double cellSize) =>
      Path()..addRect(cellBounds(cell, cellSize));

  @override
  Iterable<Point2> neighbours(Point2 cell) => [
    Point2(cell.x + 1, cell.y),
    Point2(cell.x - 1, cell.y),
    Point2(cell.x, cell.y + 1),
    Point2(cell.x, cell.y - 1),
  ];

  @override
  Set<Point2> cellsIn(Rect rect, double cellSize) {
    final range = cellRange(rect, cellSize);
    return {
      for (var y = range.top.toInt(); y < range.bottom; y++)
        for (var x = range.left.toInt(); x < range.right; x++) Point2(x, y),
    };
  }

  @override
  Rect cellRange(Rect rect, double cellSize) {
    final minX = (rect.left / cellSize).floor();
    final minY = (rect.top / cellSize).floor();
    final maxX = math.max(minX, (rect.right / cellSize).ceil() - 1);
    final maxY = math.max(minY, (rect.bottom / cellSize).ceil() - 1);
    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      maxX + 1.0,
      maxY + 1.0,
    );
  }

  @override
  Iterable<Point2> brush(Point2 cell, int size) sync* {
    final r = (size - 1) ~/ 2;
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        yield Point2(cell.x + dx, cell.y + dy);
      }
    }
  }

  @override
  double snapValue(double value, double cellSize) =>
      cellSize <= 0 ? value : (value / cellSize).roundToDouble() * cellSize;

  @override
  Offset snapPoint(Offset w, double cellSize) =>
      Offset(snapValue(w.dx, cellSize), snapValue(w.dy, cellSize));

  /// Every edge on a grid line, and never collapsed: a drag shorter than a
  /// cell still becomes one cell.
  @override
  Rect snapRect(Rect rect, double cellSize) {
    if (cellSize <= 0) return rect;
    final left = snapValue(rect.left, cellSize);
    final top = snapValue(rect.top, cellSize);
    var right = snapValue(rect.right, cellSize);
    var bottom = snapValue(rect.bottom, cellSize);
    if (right <= left) right = left + cellSize;
    if (bottom <= top) bottom = top + cellSize;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  List<Rect> merge(Set<Point2> cells, double cellSize) => [
    for (final r in mergeCells(cells))
      Rect.fromLTWH(
        r.left * cellSize,
        r.top * cellSize,
        r.width * cellSize,
        r.height * cellSize,
      ),
  ];

  /// [merge] in cell coordinates: the standard greedy sweep. Extend a run to
  /// the right, then grow it downward while every cell of the row below is
  /// free. Sorted first, so the same painting always gives the same
  /// rectangles and saved scenes stay stable.
  static List<Rect> mergeCells(Set<Point2> cells) {
    if (cells.isEmpty) return const [];
    final remaining = Set<Point2>.from(cells);
    final rects = <Rect>[];
    final ordered = remaining.toList()
      ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    for (final origin in ordered) {
      if (!remaining.contains(origin)) continue;
      var width = 1;
      while (remaining.contains(Point2(origin.x + width, origin.y))) {
        width++;
      }
      var height = 1;
      var canGrow = true;
      while (canGrow) {
        for (var dx = 0; dx < width; dx++) {
          if (!remaining.contains(Point2(origin.x + dx, origin.y + height))) {
            canGrow = false;
            break;
          }
        }
        if (canGrow) height++;
      }
      for (var dy = 0; dy < height; dy++) {
        for (var dx = 0; dx < width; dx++) {
          remaining.remove(Point2(origin.x + dx, origin.y + dy));
        }
      }
      rects.add(
        Rect.fromLTWH(
          origin.x.toDouble(),
          origin.y.toDouble(),
          width.toDouble(),
          height.toDouble(),
        ),
      );
    }
    return rects;
  }

  @override
  void paintGrid(
    Canvas canvas,
    EditorView camera,
    Size canvasSize, {
    required double cellSize,
  }) {
    if (cellSize <= 0 || canvasSize == Size.zero) return;
    camera.viewportSize = canvasSize;
    final a = camera.screenToWorld(Offset.zero);
    final b = camera.screenToWorld(Offset(canvasSize.width, canvasSize.height));
    final minX = math.min(a.dx, b.dx), maxX = math.max(a.dx, b.dx);
    final minY = math.min(a.dy, b.dy), maxY = math.max(a.dy, b.dy);
    final baseSpacing = cellSize * camera.zoom.abs();
    if (!baseSpacing.isFinite || baseSpacing <= 0) return;
    // Thin the lines out when the zoom would pack them too tightly.
    final step =
        cellSize * math.max(1, (minScreenSpacing / baseSpacing).ceil());
    const majorEvery = 5;
    final paint = Paint()..style = PaintingStyle.stroke;
    void line(bool major, Offset from, Offset to) {
      paint
        ..strokeWidth = major ? 1.2 : 0.8
        ..color = ViewportLook.gridLine(major ? 0.14 : 0.07);
      canvas.drawLine(from, to, paint);
    }

    var i = 0;
    for (
      var x = (minX / step).floor() * step;
      x <= maxX + step;
      x += step, i++
    ) {
      final sx = camera.worldToScreen(Offset(x, 0)).dx;
      line(i % majorEvery == 0, Offset(sx, 0), Offset(sx, canvasSize.height));
    }
    i = 0;
    for (
      var y = (minY / step).floor() * step;
      y <= maxY + step;
      y += step, i++
    ) {
      final sy = camera.worldToScreen(Offset(0, y)).dy;
      line(i % majorEvery == 0, Offset(0, sy), Offset(canvasSize.width, sy));
    }
  }
}
