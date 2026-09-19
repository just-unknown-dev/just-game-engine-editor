import 'dart:ui';

import '../grid/grid_topology.dart';
import '../grid/square_grid.dart';
import 'smart_snap.dart';

/// What a tool asks when it wants something snapped.
class SnapRequest {
  const SnapRequest({
    required this.moving,
    required this.gridSize,
    this.others = const [],
    this.xLines = const [],
    this.yLines = const [],
    this.threshold = 0,
    this.snapX = true,
    this.snapY = true,
    this.smart = true,
  });

  /// The rectangle being placed, in world units.
  final Rect moving;

  /// The authoring grid; zero or less means no grid.
  final double gridSize;

  /// Other entities' bounds to line up with.
  final Iterable<Rect> others;

  /// Ruler guides: infinite vertical and horizontal lines.
  final Iterable<double> xLines;
  final Iterable<double> yLines;

  /// How close counts, in world units.
  final double threshold;

  final bool snapX;
  final bool snapY;

  /// Whether snapping to other entities is on at all.
  final bool smart;
}

/// One way of snapping. Providers are asked in descending [priority]; the
/// first to answer for an axis wins that axis.
abstract class SnapProvider {
  const SnapProvider();

  /// Higher asks first. Built-ins: entities 100, grid 0.
  int get priority;

  /// The shift that snaps [request], per axis; null on an axis means no
  /// opinion, so a lower provider may still snap it.
  SnapResult snap(SnapRequest request);
}

/// Snaps edges and centres to other entities and ruler guides.
class EntitySnapProvider extends SnapProvider {
  const EntitySnapProvider();

  @override
  int get priority => 100;

  @override
  SnapResult snap(SnapRequest r) => !r.smart
      ? const SnapResult()
      : SmartSnap.snap(
          r.moving,
          r.others,
          threshold: r.threshold,
          snapX: r.snapX,
          snapY: r.snapY,
          xLines: r.xLines,
          yLines: r.yLines,
        );
}

/// Snaps the rectangle onto the grid: its top-left corner for squares, its
/// centre for hexes — whatever the topology's [GridTopology.snapRect] does.
class GridSnapProvider extends SnapProvider {
  const GridSnapProvider([this.grid = const SquareGrid()]);

  final GridTopology grid;

  @override
  int get priority => 0;

  @override
  SnapResult snap(SnapRequest r) {
    if (r.gridSize <= 0) return const SnapResult();
    final rect = r.moving;
    final snapped = grid.snapRect(rect, r.gridSize);
    return SnapResult(
      dx: r.snapX ? snapped.left - rect.left : null,
      dy: r.snapY ? snapped.top - rect.top : null,
    );
  }
}

/// The providers of one session, resolved by priority.
class SnapResolver {
  SnapResolver(Iterable<SnapProvider> providers)
    : providers = List.unmodifiable(
        providers.toList()..sort((a, b) => b.priority.compareTo(a.priority)),
      );

  /// Descending priority.
  final List<SnapProvider> providers;

  /// Asks each provider in turn until both axes have an answer.
  SnapResult resolve(SnapRequest request) {
    double? dx;
    double? dy;
    for (final p in providers) {
      final r = p.snap(request);
      dx ??= request.snapX ? r.dx : null;
      dy ??= request.snapY ? r.dy : null;
      if ((dx != null || !request.snapX) && (dy != null || !request.snapY)) {
        break;
      }
    }
    return SnapResult(dx: dx, dy: dy);
  }
}
