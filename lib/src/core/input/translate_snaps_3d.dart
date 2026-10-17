import 'dart:ui' show Offset;

import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';

/// Where a 3-D move lands besides the grid: on the surface under the
/// pointer, a corner on a corner (V held), its box lined up with a
/// neighbour's.
///
/// Made once, set up at the start of each move ([begin]) with what is
/// moved; the drag solver hands it each change ([adjust]) before applying
/// it.
class TranslateSnaps3D {
  TranslateSnaps3D({
    required this.view,
    required this.state,
    required this.surfaceAt,
    required this.candidates,
    required this.vertexSources,
    required this.holdingV,
  });

  /// How the editor sees the scene, read on use.
  final EditorView Function() view;

  /// Which snaps are on.
  final Designer3DState Function() state;

  /// The surface under [screen], leaving out [ignore].
  final SurfacePoint Function(Offset screen, Set<Entity> ignore) surfaceAt;

  /// What can be snapped to: what is drawn.
  final Iterable<Entity> Function() candidates;

  /// Who knows entities' corners.
  final Iterable<EntityVertexSource> Function() vertexSources;

  /// Whether V is held: corner on corner.
  final bool Function() holdingV;

  /// How far, on screen, a corner reaches for another.
  static const double vertexReach = 18;

  /// How far, in metres, a box's side reaches for a neighbour's.
  static const double boundsReach = 0.2;

  final Set<Entity> _moving = Set.identity();
  final Aabb3 _startBox = Aabb3();
  Vector3? _anchor;

  /// A move of [moving] begins with the pointer at [screen].
  void begin(List<Entity> moving, Offset screen) {
    _moving
      ..clear()
      ..addAll(moving);
    _startBox.setEmpty();
    final one = Aabb3();
    for (final e in moving) {
      if (RayEntityPicker.boundsOf(e, one)) _startBox.addBox(one);
    }
    // The corner of what is moved nearest where it was taken hold of.
    _anchor = _nearestVertex(moving, screen, double.infinity);
  }

  /// The move's change [delta] made to land: on a corner while V is held,
  /// else on the surface under the pointer (Surface on), then lined up
  /// with a neighbour's box (Bounds on).
  Vector3 adjust(Vector3 delta, Ray3 ray, Offset screen) {
    if (_moving.isEmpty) return delta;
    final anchor = _anchor;
    if (holdingV() && anchor != null) {
      final others = [
        for (final e in candidates())
          if (!_moving.contains(e)) e,
      ];
      final target = _nearestVertex(others, screen, vertexReach);
      if (target != null) return target - anchor;
      return delta;
    }
    final settings = state();
    var out = delta;
    if (settings.surfaceSnap.value && !_startBox.isEmpty) {
      final at = surfaceAt(screen, _moving);
      out = _restingOn(at) ?? out;
    }
    if (settings.boundsSnap.value && !_startBox.isEmpty) out = _lined(out);
    return out;
  }

  /// The change that sets what is moved on [at], its side against it.
  Vector3? _restingOn(SurfacePoint at) {
    final n = at.normal;
    final size = Vector3.zero(), centre = Vector3.zero();
    _startBox
      ..sizeInto(size)
      ..centerInto(centre);
    final reach = n.x.abs() * size.x / 2 + n.y.abs() * size.y / 2 + n.z.abs() * size.z / 2;
    final wanted = at.position + n * reach;
    return wanted - centre;
  }

  /// [delta] nudged so the moved box's sides meet a neighbour's, axis by
  /// axis, where one is within [boundsReach].
  Vector3 _lined(Vector3 delta) {
    final lo = _startBox.min + delta, hi = _startBox.max + delta;
    final best = [double.infinity, double.infinity, double.infinity];
    final nudge = [0.0, 0.0, 0.0];
    final box = Aabb3();
    for (final e in candidates()) {
      if (_moving.contains(e) || !RayEntityPicker.boundsOf(e, box)) continue;
      for (var axis = 0; axis < 3; axis++) {
        final mLo = _c(lo, axis), mHi = _c(hi, axis);
        final oLo = _c(box.min, axis), oHi = _c(box.max, axis);
        for (final gap in [oHi - mLo, oLo - mHi, oLo - mLo, oHi - mHi]) {
          if (gap.abs() < boundsReach && gap.abs() < best[axis]) {
            best[axis] = gap.abs();
            nudge[axis] = gap;
          }
        }
      }
    }
    return delta + Vector3(nudge[0], nudge[1], nudge[2]);
  }

  static double _c(Vector3 v, int axis) => switch (axis) {
    0 => v.x,
    1 => v.y,
    _ => v.z,
  };

  /// The corner of [entities] nearest [screen] on it, within [reach]
  /// pixels; null for none.
  Vector3? _nearestVertex(Iterable<Entity> entities, Offset screen, double reach) {
    final v = view();
    Vector3? best;
    var bestDistance = reach;
    for (final e in entities) {
      List<Vector3>? corners;
      for (final source in vertexSources()) {
        corners = source.verticesOf(e);
        if (corners != null) break;
      }
      if (corners == null) {
        // No mesh known: its box's corners.
        final box = Aabb3();
        if (!RayEntityPicker.boundsOf(e, box)) continue;
        corners = [
          for (var i = 0; i < 8; i++)
            Vector3(
              i & 1 == 0 ? box.min.x : box.max.x,
              i & 2 == 0 ? box.min.y : box.max.y,
              i & 4 == 0 ? box.min.z : box.max.z,
            ),
        ];
      }
      for (final c in corners) {
        final p = v.projectToScreen(c);
        if (p == null) continue;
        final d = (p - screen).distance;
        if (d < bestDistance) {
          bestDistance = d;
          best = c;
        }
      }
    }
    return best == null ? null : Vector3.copy(best);
  }
}
