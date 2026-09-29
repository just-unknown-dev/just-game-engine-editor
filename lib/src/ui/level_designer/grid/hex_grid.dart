import 'dart:math' as math;
import 'dart:ui';

import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../extension/editor_module.dart';
import '../state/designer_geometry.dart';
import 'grid_topology.dart';
import '../../../core/theme/viewport_look.dart';

/// Pointy-top hexagons, addressed by axial coordinates: [Point2.x] is `q`,
/// [Point2.y] is `r`. The cell size is a hex's width, flat to flat, so a
/// 32-unit grid has 32-unit-wide hexes.
///
/// Hexes do not merge into rectangles, so a painted stroke becomes one entity
/// per cell, placed at the cell's bounds; a hex-aware module supplies hex
/// prefabs.
class HexGrid extends GridTopology {
  const HexGrid();

  static const double _sqrt3 = 1.7320508075688772;

  @override
  String get id => 'hex';

  /// Circumradius: centre to a corner.
  double radiusFor(double width) => width / _sqrt3;

  @override
  Offset cellCenter(Point2 cell, double cellSize) {
    final r = radiusFor(cellSize);
    return Offset(cellSize * (cell.x + cell.y / 2), 1.5 * r * cell.y);
  }

  @override
  Point2 cellAt(Offset world, double cellSize) {
    final r = radiusFor(cellSize);
    final q = (_sqrt3 / 3 * world.dx - world.dy / 3) / r;
    final rr = (2 / 3 * world.dy) / r;
    return _round(q, rr);
  }

  /// Cube rounding: the nearest hex to fractional axial coordinates.
  static Point2 _round(double q, double r) {
    final s = -q - r;
    var rq = q.round(), rr = r.round(), rs = s.round();
    final dq = (rq - q).abs(), dr = (rr - r).abs(), ds = (rs - s).abs();
    if (dq > dr && dq > ds) {
      rq = -rr - rs;
    } else if (dr > ds) {
      rr = -rq - rs;
    }
    return Point2(rq, rr);
  }

  @override
  Rect cellBounds(Point2 cell, double cellSize) {
    final r = radiusFor(cellSize);
    return Rect.fromCenter(
      center: cellCenter(cell, cellSize),
      width: cellSize,
      height: 2 * r,
    );
  }

  @override
  Path cellPath(Point2 cell, double cellSize) {
    final centre = cellCenter(cell, cellSize);
    final r = radiusFor(cellSize);
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 180 * (60 * i - 30);
      final p = centre + Offset(r * math.cos(angle), r * math.sin(angle));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  static const _directions = [
    Point2(1, 0),
    Point2(1, -1),
    Point2(0, -1),
    Point2(-1, 0),
    Point2(-1, 1),
    Point2(0, 1),
  ];

  @override
  Iterable<Point2> neighbours(Point2 cell) => [
    for (final d in _directions) Point2(cell.x + d.x, cell.y + d.y),
  ];

  /// Hex distance, in cells.
  static int distance(Point2 a, Point2 b) {
    final dq = a.x - b.x, dr = a.y - b.y;
    return (dq.abs() + dr.abs() + (dq + dr).abs()) ~/ 2;
  }

  @override
  Set<Point2> cellsIn(Rect rect, double cellSize) {
    final cells = {cellAt(rect.center, cellSize)};
    final range = cellRange(rect, cellSize);
    for (var r = range.top.toInt(); r < range.bottom; r++) {
      for (var q = range.left.toInt(); q < range.right; q++) {
        final candidate = Point2(q, r);
        if (rect.inflate(1e-6).contains(cellCenter(candidate, cellSize))) {
          cells.add(candidate);
        }
      }
    }
    return cells;
  }

  @override
  Rect cellRange(Rect rect, double cellSize) {
    // Axial q shears with r, so take the corners' extremes with a margin.
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ].map((p) => cellAt(p, cellSize));
    var minQ = corners.first.x,
        maxQ = corners.first.x,
        minR = corners.first.y,
        maxR = corners.first.y;
    for (final corner in corners) {
      minQ = math.min(minQ, corner.x);
      maxQ = math.max(maxQ, corner.x);
      minR = math.min(minR, corner.y);
      maxR = math.max(maxR, corner.y);
    }
    return Rect.fromLTRB(minQ - 1.0, minR - 1.0, maxQ + 2.0, maxR + 2.0);
  }

  @override
  Iterable<Point2> brush(Point2 cell, int size) sync* {
    final radius = (size - 1) ~/ 2;
    for (var dq = -radius; dq <= radius; dq++) {
      for (
        var dr = math.max(-radius, -dq - radius);
        dr <= math.min(radius, -dq + radius);
        dr++
      ) {
        yield Point2(cell.x + dq, cell.y + dr);
      }
    }
  }

  @override
  Offset snapPoint(Offset world, double cellSize) =>
      cellCenter(cellAt(world, cellSize), cellSize);

  @override
  Rect snapRect(Rect rect, double cellSize) => Rect.fromCenter(
    center: snapPoint(rect.center, cellSize),
    width: rect.width,
    height: rect.height,
  );

  /// Hexes never merge into rectangles.
  @override
  List<Rect>? merge(Set<Point2> cells, double cellSize) => null;

  @override
  void paintGrid(
    Canvas canvas,
    jge.Camera camera,
    Size canvasSize, {
    required double cellSize,
  }) {
    if (cellSize <= 0 || canvasSize == Size.zero) return;
    if (cellSize * camera.zoom.abs() < 6) return; // too dense to read
    camera.viewportSize = canvasSize;
    final view = Rect.fromPoints(
      camera.screenToWorld(Offset.zero),
      camera.screenToWorld(Offset(canvasSize.width, canvasSize.height)),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = ViewportLook.gridLine(0.09);
    for (final cell in cellsIn(view.inflate(cellSize), cellSize)) {
      final path = cellPath(cell, cellSize);
      final screen = Path();
      var first = true;
      for (final metric in path.computeMetrics()) {
        for (var d = 0.0; d <= metric.length; d += metric.length / 6) {
          final p = camera.worldToScreen(
            metric.getTangentForOffset(d)!.position,
          );
          first ? screen.moveTo(p.dx, p.dy) : screen.lineTo(p.dx, p.dy);
          first = false;
        }
      }
      canvas.drawPath(screen..close(), paint);
    }
  }
}

/// Opt in to hex cells: `modules: [HexGridModule()]`.
class HexGridModule extends EditorModule {
  @override
  String get id => 'hexGrid';

  @override
  String get name => 'Hex grid';

  @override
  GridTopology? get gridTopology => const HexGrid();
}
