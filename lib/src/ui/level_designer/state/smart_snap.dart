import 'dart:math' as math;
import 'dart:ui';

/// An alignment the moving selection snapped to, drawn as a guide line.
///
/// A vertical guide is the line x = [position] from y = [start] to [end]; a
/// horizontal one is y = [position] from x = [start] to [end].
class SnapGuide {
  const SnapGuide({
    required this.vertical,
    required this.position,
    required this.start,
    required this.end,
  });

  /// Whether the line is vertical (constant x).
  final bool vertical;

  /// The x of a vertical guide, the y of a horizontal one.
  final double position;

  /// Where the line begins along its own axis.
  final double start;

  /// Where it ends.
  final double end;

  @override
  String toString() =>
      'SnapGuide(${vertical ? 'x' : 'y'}=$position, $start..$end)';
}

/// The gap between the selection and its nearest neighbour on one side.
class SpacingGuide {
  const SpacingGuide({required this.from, required this.to});

  /// Where the measured gap starts, in world space.
  final Offset from;

  /// Where it ends.
  final Offset to;

  /// Length of the gap.
  double get distance => (to - from).distance;
}

/// How far to shift a moving rectangle so it lines up with its neighbours.
class SnapResult {
  const SnapResult({this.dx, this.dy});

  /// Horizontal adjustment, or null if nothing was close enough on that axis.
  final double? dx;

  /// Vertical adjustment, or null.
  final double? dy;

  /// The adjustment with unsnapped axes left alone.
  Offset get adjustment => Offset(dx ?? 0, dy ?? 0);
}

/// Snapping to other entities rather than to the grid.
///
/// Levels are built by lining things up with each other — a ledge flush with
/// the platform beside it, a pickup centred over a gap — and a grid only
/// helps when both happen to sit on it. This compares edges and centres.
abstract final class SmartSnap {
  /// The smallest shift on each axis that puts one of [moving]'s edges or its
  /// centre within [threshold] of one of an [others] edge or centre.
  ///
  /// Axes are independent: a rectangle can snap horizontally to one
  /// neighbour and vertically to another. [xLines] and [yLines] are ruler
  /// guides — infinite lines that attract edges and centres the same way.
  static SnapResult snap(
    Rect moving,
    Iterable<Rect> others, {
    required double threshold,
    bool snapX = true,
    bool snapY = true,
    Iterable<double> xLines = const [],
    Iterable<double> yLines = const [],
  }) {
    double? bestX;
    double? bestY;
    if (snapX) {
      for (final x in xLines) {
        bestX = _closer(bestX, _nearest(_xs(moving), [x], threshold));
      }
    }
    if (snapY) {
      for (final y in yLines) {
        bestY = _closer(bestY, _nearest(_ys(moving), [y], threshold));
      }
    }
    for (final other in others) {
      if (snapX) {
        bestX = _closer(bestX, _nearest(_xs(moving), _xs(other), threshold));
      }
      if (snapY) {
        bestY = _closer(bestY, _nearest(_ys(moving), _ys(other), threshold));
      }
    }
    return SnapResult(dx: bestX, dy: bestY);
  }

  /// Every alignment between [moving] and [others] that holds exactly (to
  /// [epsilon]), merged into one guide per line.
  static List<SnapGuide> guides(
    Rect moving,
    Iterable<Rect> others, {
    double epsilon = 1e-3,
  }) {
    final vertical = <double, (double, double)>{};
    final horizontal = <double, (double, double)>{};
    void add(
      Map<double, (double, double)> into,
      double at,
      double start,
      double end,
    ) {
      final existing = into.entries
          .where((e) => (e.key - at).abs() <= epsilon)
          .firstOrNull;
      if (existing == null) {
        into[at] = (start, end);
      } else {
        final (s, e) = existing.value;
        into[existing.key] = (math.min(s, start), math.max(e, end));
      }
    }

    for (final other in others) {
      for (final a in _xs(moving)) {
        for (final b in _xs(other)) {
          if ((a - b).abs() > epsilon) continue;
          add(
            vertical,
            b,
            math.min(moving.top, other.top),
            math.max(moving.bottom, other.bottom),
          );
        }
      }
      for (final a in _ys(moving)) {
        for (final b in _ys(other)) {
          if ((a - b).abs() > epsilon) continue;
          add(
            horizontal,
            b,
            math.min(moving.left, other.left),
            math.max(moving.right, other.right),
          );
        }
      }
    }
    return [
      for (final e in vertical.entries)
        SnapGuide(
          vertical: true,
          position: e.key,
          start: e.value.$1,
          end: e.value.$2,
        ),
      for (final e in horizontal.entries)
        SnapGuide(
          vertical: false,
          position: e.key,
          start: e.value.$1,
          end: e.value.$2,
        ),
    ];
  }

  /// The gap to the nearest neighbour on each side of [moving] that it
  /// overlaps along the other axis — the ones you are spacing it against.
  ///
  /// Gaps longer than [maxDistance] are left out; a readout to something
  /// half a level away is noise.
  static List<SpacingGuide> spacing(
    Rect moving,
    Iterable<Rect> others, {
    double maxDistance = double.infinity,
  }) {
    SpacingGuide? left, right, above, below;
    for (final o in others) {
      final overlapY = o.top < moving.bottom && o.bottom > moving.top;
      final overlapX = o.left < moving.right && o.right > moving.left;
      if (overlapY) {
        final y =
            (math.max(o.top, moving.top) + math.min(o.bottom, moving.bottom)) /
            2;
        if (o.right <= moving.left) {
          final g = SpacingGuide(
            from: Offset(o.right, y),
            to: Offset(moving.left, y),
          );
          if (left == null || g.distance < left.distance) left = g;
        } else if (o.left >= moving.right) {
          final g = SpacingGuide(
            from: Offset(moving.right, y),
            to: Offset(o.left, y),
          );
          if (right == null || g.distance < right.distance) right = g;
        }
      }
      if (overlapX) {
        final x =
            (math.max(o.left, moving.left) + math.min(o.right, moving.right)) /
            2;
        if (o.bottom <= moving.top) {
          final g = SpacingGuide(
            from: Offset(x, o.bottom),
            to: Offset(x, moving.top),
          );
          if (above == null || g.distance < above.distance) above = g;
        } else if (o.top >= moving.bottom) {
          final g = SpacingGuide(
            from: Offset(x, moving.bottom),
            to: Offset(x, o.top),
          );
          if (below == null || g.distance < below.distance) below = g;
        }
      }
    }
    return [
      for (final g in [left, right, above, below])
        if (g != null && g.distance <= maxDistance) g,
    ];
  }

  static List<double> _xs(Rect r) => [r.left, r.center.dx, r.right];
  static List<double> _ys(Rect r) => [r.top, r.center.dy, r.bottom];

  static double? _nearest(
    List<double> from,
    List<double> to,
    double threshold,
  ) {
    double? best;
    for (final a in from) {
      for (final b in to) {
        final d = b - a;
        if (d.abs() <= threshold && (best == null || d.abs() < best.abs())) {
          best = d;
        }
      }
    }
    return best;
  }

  static double? _closer(double? a, double? b) {
    if (a == null) return b;
    if (b == null) return a;
    return b.abs() < a.abs() ? b : a;
  }
}
