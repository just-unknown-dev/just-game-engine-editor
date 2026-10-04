import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../grid/square_grid.dart';

/// Integer grid coordinate.
///
/// A dedicated value type rather than a record so it has stable equality and
/// hashing for use as a Set key, which the greedy merge depends on.
class Point2 {
  const Point2(this.x, this.y);

  /// Column.
  final int x;

  /// Row.
  final int y;

  @override
  bool operator ==(Object other) =>
      other is Point2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point2($x, $y)';
}

/// One of the eight resize handles on a selection's bounds.
enum ResizeHandle {
  topLeft(-1, -1),
  top(0, -1),
  topRight(1, -1),
  right(1, 0),
  bottomRight(1, 1),
  bottom(0, 1),
  bottomLeft(-1, 1),
  left(-1, 0);

  const ResizeHandle(this.x, this.y);

  /// -1 for the left edge, 1 for the right, 0 for neither.
  final int x;

  /// -1 for the top edge, 1 for the bottom, 0 for neither.
  final int y;

  /// Whether this handle drags a corner, changing both axes.
  bool get isCorner => x != 0 && y != 0;

  /// Where on [rect] this handle sits.
  Offset on(Rect rect) => Offset(
    rect.center.dx + x * rect.width / 2,
    rect.center.dy + y * rect.height / 2,
  );
}

/// Geometry helpers shared by the designer's tools and painter.
///
/// Pure functions with no editor state, so they are directly testable without
/// standing up a World or an Engine.
abstract final class DesignerGeometry {
  /// Rounds [value] to the nearest multiple of [step].
  static double snapValue(double value, double step) {
    if (step <= 0) return value;
    return (value / step).roundToDouble() * step;
  }

  /// Snaps a rectangle so its *edges* land on grid lines.
  ///
  /// Distinct from snapping the centre, which is what the base editor does.
  /// For level geometry the edges are what matter: a platform 100 units wide
  /// on a 32-unit grid has a centre that can never sit on a grid line, and it
  /// is the edges that have to line up for platforms to tile cleanly against
  /// each other.
  static Rect snapRectEdges(Rect rect, double step) {
    if (step <= 0) return rect;
    final left = snapValue(rect.left, step);
    final top = snapValue(rect.top, step);
    final right = snapValue(rect.right, step);
    final bottom = snapValue(rect.bottom, step);
    // Never collapse to nothing — a drag smaller than one cell becomes one
    // cell, which is what the author was reaching for.
    return Rect.fromLTRB(
      left,
      top,
      right > left ? right : left + step,
      bottom > top ? bottom : top + step,
    );
  }

  /// Snaps a centre position so the rectangle's top-left corner lands on a
  /// grid line, keeping [size] unchanged.
  ///
  /// Snapping the corner rather than all four edges, because the size is fixed
  /// here: [snapRectEdges] is free to resize, and resizing then re-centring at
  /// the original size puts the edge back off-grid. For a size that is not a
  /// whole number of cells only the leading edges can align, and those are the
  /// ones an author lines up against.
  static Offset snapCenterForSize(Offset center, Size size, double step) {
    if (step <= 0) return center;
    final left = snapValue(center.dx - size.width / 2, step);
    final top = snapValue(center.dy - size.height / 2, step);
    return Offset(left + size.width / 2, top + size.height / 2);
  }

  /// Builds a rectangle from two drag corners, normalised so width and height
  /// are positive regardless of drag direction.
  static Rect rectFromDrag(Offset start, Offset end) =>
      Rect.fromPoints(start, end);

  /// The definitions [entity]'s components are read with: its world's
  /// (`world.context.definitions`). For no entity, or one in no world, the
  /// engine's own definitions only.
  static jge.ComponentDefinitionRegistry definitionsFor(jge.Entity? entity) =>
      entity?.world?.context.definitions ?? _core;

  /// The engine's own definitions, for components in no world. Never
  /// registered into.
  static final jge.ComponentDefinitionRegistry _core =
      jge.ComponentDefinitionRegistry.core();

  /// The unscaled size implied by [entity]'s components, largest wins.
  ///
  /// One answer per component, from the extent on its definition: the same
  /// answer the resize handles and the gizmo use, so a marquee, a handle and
  /// an outline can never disagree about how big something is.
  static Size? componentSize(jge.Entity entity) {
    Size? best;
    final definitions = definitionsFor(entity);
    for (final component in entity.components) {
      final size = sizeOf(component, definitions);
      if (size == null) continue;
      final current = best;
      if (current == null ||
          size.width * size.height > current.width * current.height) {
        best = size;
      }
    }
    return best;
  }

  /// The size [component] implies on its own, or null — through its
  /// definition in [definitions] (the engine's own when null).
  static Size? sizeOf(
    jge.Component component, [
    jge.ComponentDefinitionRegistry? definitions,
  ]) => (definitions ?? _core)
      .definitionFor(component)
      ?.extent
      ?.sizeOf(component);

  /// The world-space rectangle [entity] occupies.
  ///
  /// Null when nothing about the entity implies a size — a spawn point, say,
  /// which the painter draws its own marker for.
  static Rect? worldBounds(jge.Entity entity) {
    final transform = entity.getComponent<jge.TransformComponent>();
    if (transform == null) return null;

    final size = componentSize(entity);
    if (size == null) return null;

    final width = size.width * transform.scale.x.abs();
    final height = size.height * transform.scale.y.abs();
    // The axis-aligned box around the rotated shape, so a platform turned a
    // quarter turn is hit-tested, snapped and aligned by the space it
    // actually occupies rather than the space it would if it were not turned.
    final cos = math.cos(transform.angle).abs();
    final sin = math.sin(transform.angle).abs();
    return Rect.fromCenter(
      center: Offset(transform.position.x, transform.position.y),
      width: width * cos + height * sin,
      height: width * sin + height * cos,
    );
  }

  /// The topmost entity at [point] that [pickable] allows.
  ///
  /// Reverse layer order, so the thing drawn in front is the thing you grab.
  /// Sizeless markers are caught within [markerReach] of their origin, or
  /// they would be impossible to grab.
  static jge.Entity? topmostAt(
    jge.World world,
    Offset point, {
    required bool Function(jge.Entity) pickable,
    required double markerReach,
  }) {
    final candidates = world
        .query([jge.TransformComponent])
        .where((e) => e.isActive && pickable(e))
        .toList();
    candidates.sort((a, b) {
      final la = a.getComponent<jge.LayerComponent>();
      final lb = b.getComponent<jge.LayerComponent>();
      final byLayer = (lb?.layer ?? 0).compareTo(la?.layer ?? 0);
      if (byLayer != 0) return byLayer;
      return (lb?.zOrder ?? 0).compareTo(la?.zOrder ?? 0);
    });
    for (final entity in candidates) {
      final bounds = worldBounds(entity);
      if (bounds != null) {
        if (bounds.contains(point)) return entity;
        continue;
      }
      final t = entity.getComponent<jge.TransformComponent>();
      if (t == null) continue;
      if ((Offset(t.position.x, t.position.y) - point).distance <=
          markerReach) {
        return entity;
      }
    }
    return null;
  }

  /// Entities whose bounds intersect [selection].
  ///
  /// [pickable] gates out hidden and locked layers, so dragging a marquee over
  /// finished background work does not sweep it into the selection.
  static List<jge.Entity> entitiesIn(
    Rect selection,
    Iterable<jge.Entity> entities, {
    required bool Function(jge.Entity) pickable,
  }) {
    final hits = <jge.Entity>[];
    for (final entity in entities) {
      if (!entity.isActive || !pickable(entity)) continue;

      final bounds = worldBounds(entity);
      if (bounds != null) {
        if (bounds.overlaps(selection)) hits.add(entity);
        continue;
      }

      // Sizeless entities (spawn points, camera zones) are caught by origin.
      final transform = entity.getComponent<jge.TransformComponent>();
      if (transform == null) continue;
      final origin = Offset(transform.position.x, transform.position.y);
      if (selection.contains(origin)) hits.add(entity);
    }
    return hits;
  }

  /// Combined bounds of [entities], or null when none can be measured.
  static Rect? unionBounds(Iterable<jge.Entity> entities) {
    Rect? union;
    for (final entity in entities) {
      var bounds = worldBounds(entity);
      if (bounds == null) {
        final transform = entity.getComponent<jge.TransformComponent>();
        if (transform == null) continue;
        bounds = Rect.fromCenter(
          center: Offset(transform.position.x, transform.position.y),
          width: 1,
          height: 1,
        );
      }
      union = union == null ? bounds : union.expandToInclude(bounds);
    }
    return union;
  }

  // ── Cells: the square grid, kept as the shorthand tests and tools used ──
  //
  // A designer session asks its `GridTopology` instead; these are that
  // topology when it is the default square one.

  static const SquareGrid _square = SquareGrid();

  /// The square cell containing [world]. See [GridTopology.cellAt].
  static Point2 cellAt(Offset world, double cellSize) =>
      _square.cellAt(world, cellSize);

  /// Every square cell touched by [rect]. See [GridTopology.cellsIn].
  static Set<Point2> cellsIn(Rect rect, double cellSize) =>
      _square.cellsIn(rect, cellSize);

  /// A bucket fill on the square grid. See [GridTopology.floodFill].
  static Set<Point2>? floodFill(
    Point2 start,
    Set<Point2> blocked, {
    required Rect limit,
    int maxCells = 20000,
  }) => _square.floodFill(start, blocked, limit: limit, maxCells: maxCells);

  /// The cells of a [size]×[size] brush centred on [cell].
  static Iterable<Point2> brushCells(Point2 cell, int size) =>
      _square.brush(cell, size);

  /// Merges occupied square cells into as few rectangles as possible, in
  /// cell coordinates. See [SquareGrid.mergeCells].
  static List<Rect> greedyMerge(Set<Point2> cells) =>
      SquareGrid.mergeCells(cells);

  /// [point] turned [quarterTurns] quarter turns about [pivot], clockwise on
  /// screen (where +Y is down). Exact: no trigonometry, so a row of platforms
  /// rotated and rotated back lands on the same pixels.
  static Offset rotateQuarter(Offset point, Offset pivot, int quarterTurns) {
    final d = point - pivot;
    final turned = switch (quarterTurns % 4) {
      0 => d,
      1 => Offset(-d.dy, d.dx),
      2 => Offset(-d.dx, -d.dy),
      _ => Offset(d.dy, -d.dx),
    };
    return pivot + turned;
  }

  /// [point] mirrored across the vertical (when [horizontal]) or horizontal
  /// line through [pivot].
  static Offset mirror(
    Offset point,
    Offset pivot, {
    required bool horizontal,
  }) => horizontal
      ? Offset(2 * pivot.dx - point.dx, point.dy)
      : Offset(point.dx, 2 * pivot.dy - point.dy);

  /// The rectangle [start] becomes when [handle] is dragged to [pointer].
  ///
  /// [keepAspect] (Shift) preserves proportions on a corner drag;
  /// [fromCenter] (Alt) grows both sides at once, keeping the centre fixed.
  /// Never smaller than [minExtent] on either axis, and never inverted: a
  /// drag past the opposite edge stops there.
  static Rect resizeRect(
    Rect start,
    ResizeHandle handle,
    Offset pointer, {
    bool keepAspect = false,
    bool fromCenter = false,
    double minExtent = 1,
  }) {
    final anchor = fromCenter
        ? start.center
        : Offset(
            start.center.dx - handle.x * start.width / 2,
            start.center.dy - handle.y * start.height / 2,
          );
    final factor = fromCenter ? 2.0 : 1.0;

    var width = handle.x == 0
        ? start.width
        : math.max(minExtent, (pointer.dx - anchor.dx) * handle.x * factor);
    var height = handle.y == 0
        ? start.height
        : math.max(minExtent, (pointer.dy - anchor.dy) * handle.y * factor);

    if (keepAspect && handle.isCorner && start.width > 0 && start.height > 0) {
      final scale = math.max(width / start.width, height / start.height);
      width = start.width * scale;
      height = start.height * scale;
    }

    final center = fromCenter
        ? start.center
        : Offset(
            handle.x == 0 ? start.center.dx : anchor.dx + handle.x * width / 2,
            handle.y == 0 ? start.center.dy : anchor.dy + handle.y * height / 2,
          );
    return Rect.fromCenter(center: center, width: width, height: height);
  }

  /// Where [point] lands when [from] is stretched onto [to] — used to carry
  /// every entity in a resized selection to its proportional position.
  static Offset mapPoint(Offset point, Rect from, Rect to) => Offset(
    from.width == 0
        ? to.center.dx
        : to.left + (point.dx - from.left) / from.width * to.width,
    from.height == 0
        ? to.center.dy
        : to.top + (point.dy - from.top) / from.height * to.height,
  );

  /// Distance between two points, for the measure tool.
  static double distance(Offset a, Offset b) => (b - a).distance;

  /// Angle from [a] to [b] in degrees, clockwise from east — matching the
  /// screen-space convention where +Y is down.
  static double angleDegrees(Offset a, Offset b) {
    final delta = b - a;
    return math.atan2(delta.dy, delta.dx) * 180 / math.pi;
  }
}
