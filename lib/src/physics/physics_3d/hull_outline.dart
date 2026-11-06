import 'dart:math' as math;
import 'dart:typed_data';

import 'package:just_game_engine/just_game_engine.dart';

/// The edges of the convex hull of a few points (x, y, z each), for drawing
/// a hull collider as a wire outline: each face found as a plane every
/// point lies behind, and outlined by the hull of the points on it — so a
/// flat side shows its outline, not the triangles inside it.
///
/// Brute force, for the handful of points a shape's parts have; past
/// [maxPoints] it gives the box round them. Callers keep the result.
abstract final class HullOutline {
  /// The most points outlined face by face.
  static const int maxPoints = 64;

  /// The hull's edges as pairs of points.
  static List<(Vector3, Vector3)> of(Float32List points) {
    final n = points.length ~/ 3;
    final p = [
      for (var i = 0; i < n; i++)
        Vector3(points[i * 3], points[i * 3 + 1], points[i * 3 + 2]),
    ];
    if (n == 0) return const [];
    final lo = Vector3.copy(p.first), hi = Vector3.copy(p.first);
    for (final q in p) {
      lo.setValues(
        math.min(lo.x, q.x),
        math.min(lo.y, q.y),
        math.min(lo.z, q.z),
      );
      hi.setValues(
        math.max(hi.x, q.x),
        math.max(hi.y, q.y),
        math.max(hi.z, q.z),
      );
    }
    final size = (hi - lo).length;
    if (n < 4 || n > maxPoints || size == 0) return _box(lo, hi);
    final eps = 1e-5 * size;

    final planes = <(Vector3, double)>[];
    final edges = <int>{};
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        for (var k = j + 1; k < n; k++) {
          final normal = (p[j] - p[i]).cross(p[k] - p[i]);
          final length = normal.length;
          if (length <= eps * size) continue;
          normal.scale(1 / length);
          var d = normal.dot(p[i]);
          var above = -double.infinity, below = double.infinity;
          for (final q in p) {
            final s = normal.dot(q) - d;
            above = math.max(above, s);
            below = math.min(below, s);
          }
          if (above > eps) {
            if (below < -eps) continue; // Points both sides: not a face.
            normal.scale(-1);
            d = -d;
          }
          if (planes.any(
            (plane) =>
                plane.$1.dot(normal) > 1 - 1e-9 && (plane.$2 - d).abs() <= eps,
          )) {
            continue;
          }
          planes.add((normal, d));
          _outlineFace(p, normal, d, eps, n, edges);
        }
      }
    }
    return [for (final e in edges) (p[e ~/ n], p[e % n])];
  }

  /// Adds to [edges] the outline of the points of [p] on the plane
  /// ([normal], [d]): their hull within it.
  static void _outlineFace(
    List<Vector3> p,
    Vector3 normal,
    double d,
    double eps,
    int n,
    Set<int> edges,
  ) {
    final on = [
      for (var i = 0; i < p.length; i++)
        if ((normal.dot(p[i]) - d).abs() <= eps) i,
    ];
    // Two directions within the plane.
    final helper = normal.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
    final u = normal.cross(helper)..normalize();
    final v = normal.cross(u);
    final flat = [for (final i in on) (u.dot(p[i]), v.dot(p[i]), i)]
      ..sort(
        (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
      );
    double turn(
      (double, double, int) o,
      (double, double, int) a,
      (double, double, int) b,
    ) => (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);
    final ring = <(double, double, int)>[];
    for (final pass in [flat, flat.reversed.toList()]) {
      final start = ring.length;
      for (final q in pass) {
        while (ring.length >= start + 2 &&
            turn(ring[ring.length - 2], ring.last, q) <= eps * eps) {
          ring.removeLast();
        }
        ring.add(q);
      }
      ring.removeLast();
    }
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i].$3, b = ring[(i + 1) % ring.length].$3;
      if (a == b) continue;
      edges.add(a < b ? a * n + b : b * n + a);
    }
  }

  static List<(Vector3, Vector3)> _box(Vector3 lo, Vector3 hi) {
    Vector3 corner(int i) => Vector3(
      i & 1 == 0 ? lo.x : hi.x,
      i & 2 == 0 ? lo.y : hi.y,
      i & 4 == 0 ? lo.z : hi.z,
    );
    return [
      for (var i = 0; i < 8; i++)
        for (final bit in [1, 2, 4])
          if (i & bit == 0) (corner(i), corner(i | bit)),
    ];
  }
}
