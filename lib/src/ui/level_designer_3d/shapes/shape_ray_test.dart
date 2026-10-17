import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';

import 'package:just_editor_core/host.dart';

/// Picks a 3-D shape ([Primitive3D]) by its triangles, not its box: a click
/// through an arch or a ring's hole picks what is behind it. Knows its
/// corners too, for a move that puts one on another (V held), and which
/// way its surface faces, for placing on a slope or a ball.
final class ShapeRayTest
    implements EntityRayTest, EntityVertexSource, EntitySurfaceTest {
  final Map<Object, ModelGeometry> _meshes = {};
  final Matrix4 _world = Matrix4.identity();
  final Matrix4 _inverse = Matrix4.identity();
  final Vector3 _origin = Vector3.zero();
  final Vector3 _direction = Vector3.zero();

  /// How many shapes' triangles are kept.
  static const int keep = 256;

  ModelGeometry _geometryOf(Primitive3D shape) {
    final key = shape.shapeKey;
    var geometry = _meshes[key];
    if (geometry == null) {
      if (_meshes.length >= keep) _meshes.remove(_meshes.keys.first);
      geometry = _meshes[key] = shape.buildMesh().geometry;
    }
    return geometry;
  }

  @override
  List<Vector3>? verticesOf(Entity entity) {
    final shape = entity.getComponent<Primitive3D>();
    final transform = entity.getComponent<TransformComponent>();
    if (shape == null || transform == null) return null;
    final p = _geometryOf(shape).positions;
    transform.localToWorldInto(_world);
    final seen = <(double, double, double)>{};
    final out = <Vector3>[];
    for (var i = 0; i + 2 < p.length; i += 3) {
      if (!seen.add((p[i], p[i + 1], p[i + 2]))) continue;
      final v = Vector3.zero();
      _world.transformPointInto(Vector3(p[i], p[i + 1], p[i + 2]), v);
      out.add(v);
    }
    return out;
  }

  @override
  RayTriangleHit? surfaceHit(Entity entity, Ray3 ray) {
    final shape = entity.getComponent<Primitive3D>();
    final transform = entity.getComponent<TransformComponent>();
    if (shape == null || transform == null) return null;
    final geometry = _geometryOf(shape);
    transform.localToWorldInto(_world);
    return RayTriangles.nearestPlaced(geometry, _world, ray) ??
        RayTriangleHit(double.infinity, Vector3(0, -1, 0));
  }

  @override
  double? distanceTo(Entity entity, Ray3 ray) {
    final shape = entity.getComponent<Primitive3D>();
    final transform = entity.getComponent<TransformComponent>();
    if (shape == null || transform == null) return null;
    final geometry = _geometryOf(shape);
    if (geometry.triangleCount == 0) return double.infinity;
    transform.localToWorldInto(_world);
    if (_inverse.copyInverse(_world) == 0) return null;
    _inverse
      ..transformPointInto(ray.origin, _origin)
      ..transformDirectionInto(ray.direction, _direction);
    return RayTriangles.nearestHit(geometry, _origin, _direction) ?? double.infinity;
  }
}
