import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart'
    show
        EntityRayTest,
        EntitySurfaceTest,
        EntityVertexSource,
        RayTriangleHit,
        RayTriangles;
import 'package:just_game_engine/graphics_3d.dart';

/// Picks a model by its triangles, not its box: a click through the arch
/// of a doorway picks what is behind it. Knows which way its surface faces
/// too, for placing on it.
///
/// It knows an entity with a [ModelComponent] whose model has loaded
/// ([dataOf]); for any other it says nothing, and the box decides.
final class ModelRayTest
    implements EntityRayTest, EntityVertexSource, EntitySurfaceTest {
  /// A test finding loaded models through [dataOf].
  ModelRayTest(this.dataOf);

  /// The parsed model at a path, or null while it isn't loaded.
  final ModelData? Function(String path) dataOf;

  final Map<ModelData, ModelGeometry?> _triangles = Map.identity();
  final Matrix4 _world = Matrix4.identity();
  final Matrix4 _inverse = Matrix4.identity();
  final Vector3 _origin = Vector3.zero();
  final Vector3 _direction = Vector3.zero();

  /// Most corners offered for one model: a big mesh offers none, rather
  /// than slowing every move.
  static const int maxVertices = 4096;

  @override
  List<Vector3>? verticesOf(Entity entity) {
    final model = entity.getComponent<ModelComponent>();
    final transform = entity.getComponent<TransformComponent>();
    if (model == null || transform == null || model.model.isEmpty) return null;
    final data = dataOf(model.model);
    if (data == null) return null;
    final geometry = _triangles.putIfAbsent(
      data,
      () => GraphicsModelAsset.trianglesOf(data),
    );
    if (geometry == null) return const [];
    final p = geometry.positions;
    if (p.length ~/ 3 > maxVertices) return const [];
    transform.localToWorldInto(_world);
    final out = <Vector3>[];
    for (var i = 0; i + 2 < p.length; i += 3) {
      final v = Vector3.zero();
      _world.transformPointInto(Vector3(p[i], p[i + 1], p[i + 2]), v);
      out.add(v);
    }
    return out;
  }

  @override
  RayTriangleHit? surfaceHit(Entity entity, Ray3 ray) {
    final model = entity.getComponent<ModelComponent>();
    final transform = entity.getComponent<TransformComponent>();
    if (model == null || transform == null || model.model.isEmpty) return null;
    final data = dataOf(model.model);
    if (data == null) return null;
    final geometry = _triangles.putIfAbsent(
      data,
      () => GraphicsModelAsset.trianglesOf(data),
    );
    final miss = RayTriangleHit(double.infinity, Vector3(0, -1, 0));
    if (geometry == null) return miss;
    transform.localToWorldInto(_world);
    return RayTriangles.nearestPlaced(geometry, _world, ray) ?? miss;
  }

  @override
  double? distanceTo(Entity entity, Ray3 ray) {
    final model = entity.getComponent<ModelComponent>();
    final transform = entity.getComponent<TransformComponent>();
    if (model == null || transform == null || model.model.isEmpty) return null;
    final data = dataOf(model.model);
    if (data == null) return null;
    final geometry = _triangles.putIfAbsent(
      data,
      () => GraphicsModelAsset.trianglesOf(data),
    );
    if (geometry == null) return double.infinity;
    transform.localToWorldInto(_world);
    if (_inverse.copyInverse(_world) == 0) return null;
    // Into the model's own space; t stays in the ray's units, as the
    // direction is carried over unnormalised.
    _inverse
      ..transformPointInto(ray.origin, _origin)
      ..transformDirectionInto(ray.direction, _direction);
    return RayTriangles.nearestHit(geometry, _origin, _direction) ??
        double.infinity;
  }
}
