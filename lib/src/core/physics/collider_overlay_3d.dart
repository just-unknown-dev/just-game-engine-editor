import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, Paint, PaintingStyle;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';

import 'package:just_editor_core/host.dart';
import 'hull_outline.dart';

/// The shapes of the 3-D colliders and characters in a 3-D scene, as wire
/// outlines: faint for all of them, bright for the selection; sensors in
/// yellow, characters in blue. A collider matching its entity's shape shows
/// the parts it is made of.
final class ColliderOverlay3D extends ViewportOverlay {
  // The outlines of matched shapes, by their key: worked out once each.
  final Map<Object, List<(Vector3, Vector3)>> _matched = {};

  @override
  String get id => 'physics3d.colliders';

  @override
  String get label => 'Colliders';

  @override
  Dimensions get dimensions => Dimensions.threeD;

  @override
  void paint(ViewportOverlayContext context) {
    final world = context.world;
    final matrix = Matrix4.identity();
    for (final entity in world.query([TransformComponent, Collider3D])) {
      if (!context.isShown(entity)) continue;
      final c = entity.getComponent<Collider3D>()!;
      final selected = context.isSelected(entity);
      final sensor = entity.getComponent<RigidBody3D>()?.isSensor ?? false;
      final paint = _paint(sensor ? const Color(0xFFFFD54F) : const Color(0xFF7CFC9A), selected);
      entity.getComponent<TransformComponent>()!.localToWorldInto(matrix);
      final rotation = Quaternion.euler(c.rotation.x, c.rotation.y, c.rotation.z);
      Vector3 place(Vector3 p) {
        p
          ..x *= c.scale.x
          ..y *= c.scale.y
          ..z *= c.scale.z;
        rotation.rotate(p);
        p.add(c.offset);
        matrix.transformPointInto(p, p);
        return p;
      }

      final lines = c.shape == ColliderShape3D.matchShape
          ? _matchedLines(entity.components.whereType<SolidShapeSource>().firstOrNull)
          : shapeLines(c);
      for (final (a, b) in lines) {
        _line(context, place(Vector3.copy(a)), place(Vector3.copy(b)), paint);
      }
    }
    for (final entity in world.query([TransformComponent, CharacterBody3D])) {
      if (!context.isShown(entity)) continue;
      final ch = entity.getComponent<CharacterBody3D>()!;
      final paint = _paint(const Color(0xFF64B5F6), context.isSelected(entity));
      // Its feet are its position; the capsule stands up from them (-Y).
      final feet = entity.getComponent<TransformComponent>()!.position;
      for (final (a, b) in capsuleLines(ch.radius, ch.height)) {
        _line(context, a..add(feet)..y -= ch.height / 2, b..add(feet)..y -= ch.height / 2, paint);
      }
    }
  }

  List<(Vector3, Vector3)> _matchedLines(SolidShapeSource? source) {
    if (source == null) return const [];
    final key = source.solidKey;
    final known = _matched[key];
    if (known != null) return known;
    if (_matched.length >= 128) _matched.remove(_matched.keys.first);
    return _matched[key] = [for (final part in source.solidParts) ...partLines(part)];
  }

  /// One convex part of a matched shape as line segments in its entity's
  /// own space.
  static List<(Vector3, Vector3)> partLines(SolidPart part) {
    List<(Vector3, Vector3)> at(List<(Vector3, Vector3)> lines, double x, double y, double z) {
      final offset = Vector3(x, y, z);
      return [for (final (a, b) in lines) (a..add(offset), b..add(offset))];
    }

    return switch (part) {
      SolidBox(:final halfX, :final halfY, :final halfZ, :final x, :final y, :final z) =>
        at(boxLines(Vector3(halfX, halfY, halfZ)), x, y, z),
      SolidSphere(:final radius, :final x, :final y, :final z) => at([
        ..._ring(Vector3.zero(), Vector3(1, 0, 0), Vector3(0, 1, 0), radius),
        ..._ring(Vector3.zero(), Vector3(1, 0, 0), Vector3(0, 0, 1), radius),
        ..._ring(Vector3.zero(), Vector3(0, 1, 0), Vector3(0, 0, 1), radius),
      ], x, y, z),
      SolidCapsule(:final halfHeight, :final radius, :final x, :final y, :final z) =>
        at(capsuleLines(radius, (halfHeight + radius) * 2), x, y, z),
      SolidCylinder(:final halfHeight, :final radius, :final x, :final y, :final z) => at([
        ..._ring(Vector3(0, -halfHeight, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), radius),
        ..._ring(Vector3(0, halfHeight, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), radius),
        for (final (dx, dz) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)])
          (Vector3(dx * radius, -halfHeight, dz * radius), Vector3(dx * radius, halfHeight, dz * radius)),
      ], x, y, z),
      SolidHull(:final points) => HullOutline.of(points),
      SolidMesh(:final positions, :final indices) => _meshLines(positions, indices),
      SolidHeightField(:final heights, :final sampleCount, :final cellSize, :final x, :final y, :final z) =>
        _fieldLines(heights, sampleCount, cellSize, Vector3(x, y, z)),
    };
  }

  /// A triangle mesh's edges, at most a few thousand of them.
  static List<(Vector3, Vector3)> _meshLines(Float32List p, Uint32List idx) {
    Vector3 at(int i) => Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]);
    final int step = math.max(1, idx.length ~/ (3 * 2000));
    return [
      for (var i = 0; i + 2 < idx.length; i += 3 * step) ...[
        (at(idx[i]), at(idx[i + 1])),
        (at(idx[i + 1]), at(idx[i + 2])),
        (at(idx[i + 2]), at(idx[i])),
      ],
    ];
  }

  /// A height field's grid, every few rows on a big one.
  static List<(Vector3, Vector3)> _fieldLines(Float32List h, int n, double cell, Vector3 origin) {
    if (n < 2 || h.length < n * n) return const [];
    final int step = math.max(1, n ~/ 32);
    Vector3? at(int col, int row) {
      final height = h[row * n + col];
      if (height >= SolidHeightField.holeHeight) return null;
      // Heights are up: +Y is down.
      return Vector3(origin.x + col * cell, origin.y - height, origin.z + row * cell);
    }

    final out = <(Vector3, Vector3)>[];
    for (var row = 0; row < n; row += step) {
      for (var col = 0; col + step < n; col += step) {
        final a = at(col, row), b = at(col + step, row);
        if (a != null && b != null) out.add((a, b));
      }
    }
    for (var col = 0; col < n; col += step) {
      for (var row = 0; row + step < n; row += step) {
        final a = at(col, row), b = at(col, row + step);
        if (a != null && b != null) out.add((a, b));
      }
    }
    return out;
  }

  static Paint _paint(Color colour, bool selected) => Paint()
    ..color = colour.withValues(alpha: selected ? 0.95 : 0.35)
    ..strokeWidth = selected ? 1.5 : 1
    ..style = PaintingStyle.stroke;

  static void _line(ViewportOverlayContext context, Vector3 a, Vector3 b, Paint paint) {
    final p = context.project(a), q = context.project(b);
    if (p != null && q != null) context.canvas.drawLine(p, q, paint);
  }

  /// [c]'s outline as line segments in its own space (before its offset,
  /// rotation and scale). A mesh, hull or height field shows the box its
  /// model or heights fill — here a metre cube, until the shape is built.
  static List<(Vector3, Vector3)> shapeLines(Collider3D c) => switch (c.shape) {
    ColliderShape3D.box => boxLines(c.size * 0.5),
    ColliderShape3D.sphere => [
      ..._ring(Vector3.zero(), Vector3(1, 0, 0), Vector3(0, 1, 0), c.radius),
      ..._ring(Vector3.zero(), Vector3(1, 0, 0), Vector3(0, 0, 1), c.radius),
      ..._ring(Vector3.zero(), Vector3(0, 1, 0), Vector3(0, 0, 1), c.radius),
    ],
    ColliderShape3D.capsule => capsuleLines(c.radius, c.height),
    ColliderShape3D.cylinder => [
      ..._ring(Vector3(0, -c.height / 2, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), c.radius),
      ..._ring(Vector3(0, c.height / 2, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), c.radius),
      for (final (x, z) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)])
        (Vector3(x * c.radius, -c.height / 2, z * c.radius), Vector3(x * c.radius, c.height / 2, z * c.radius)),
    ],
    _ => boxLines(Vector3(0.5, 0.5, 0.5)),
  };

  /// The twelve edges of a box of [half] extents about the origin.
  static List<(Vector3, Vector3)> boxLines(Vector3 half) {
    Vector3 corner(int i) => Vector3(
      i & 1 == 0 ? -half.x : half.x,
      i & 2 == 0 ? -half.y : half.y,
      i & 4 == 0 ? -half.z : half.z,
    );
    return [
      for (var i = 0; i < 8; i++)
        for (final bit in [1, 2, 4])
          if (i & bit == 0) (corner(i), corner(i | bit)),
    ];
  }

  /// A capsule [height] tall overall, about the origin, standing along Y.
  static List<(Vector3, Vector3)> capsuleLines(double radius, double height) {
    final half = math.max(0.0, height / 2 - radius);
    return [
      ..._ring(Vector3(0, -half, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), radius),
      ..._ring(Vector3(0, half, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), radius),
      for (final (x, z) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)])
        (Vector3(x * radius, -half, z * radius), Vector3(x * radius, half, z * radius)),
      // The two caps, as half rings over the top and under the bottom.
      for (final side in [Vector3(1, 0, 0), Vector3(0, 0, 1)])
        for (final (centre, up) in [(Vector3(0, -half, 0), -1.0), (Vector3(0, half, 0), 1.0)])
          ..._arc(centre, side, Vector3(0, up, 0), radius),
    ];
  }

  static List<(Vector3, Vector3)> _ring(Vector3 centre, Vector3 u, Vector3 v, double r) =>
      _curve(centre, u, v, r, 0, math.pi * 2, 32);

  static List<(Vector3, Vector3)> _arc(Vector3 centre, Vector3 across, Vector3 out, double r) =>
      _curve(centre, across, out, r, 0, math.pi, 16);

  static List<(Vector3, Vector3)> _curve(Vector3 centre, Vector3 u, Vector3 v, double r, double from, double to, int steps) {
    Vector3 at(int k) {
      final a = from + (to - from) * k / steps;
      return Vector3(
        centre.x + (u.x * math.cos(a) + v.x * math.sin(a)) * r,
        centre.y + (u.y * math.cos(a) + v.y * math.sin(a)) * r,
        centre.z + (u.z * math.cos(a) + v.z * math.sin(a)) * r,
      );
    }

    return [for (var k = 0; k < steps; k++) (at(k), at(k + 1))];
  }
}
