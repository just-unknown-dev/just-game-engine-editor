import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'editor_view.dart';
import 'entity_picker.dart';

/// Knows the real shape of some entities — a 3-D model's triangles — so a
/// pick lands on what is drawn, not on its box. Modules offer these
/// (`EditorModule.pickTests`).
abstract interface class EntityRayTest {
  /// How far along [ray] (in units of its direction) it first meets
  /// [entity]'s shape: [double.infinity] for a miss, or null when this test
  /// does not know the entity (its box then decides).
  double? distanceTo(jge.Entity entity, jge.Ray3 ray);
}

/// A point on a surface in space and which way the surface faces there:
/// where something placed from the viewport goes, and which way is up for
/// it.
final class SurfacePoint {
  /// [position] on a surface facing [normal] (unit length), on [onto] or
  /// on the ground when null.
  SurfacePoint(this.position, this.normal, {this.onto});

  /// Where it is.
  final jge.Vector3 position;

  /// Which way the surface faces: up (-Y) on the ground.
  final jge.Vector3 normal;

  /// What the surface belongs to, or null for the ground.
  final jge.Entity? onto;
}

/// Picks in 3-D: the view's ray through the pixel ([EditorView.screenToRay])
/// against each entity's box in space, nearest first, each hit then checked
/// against its real shape when an [EntityRayTest] knows it.
///
/// An entity's box is the union of its components' 3-D extents
/// (`ComponentExtent.boundsInto`) placed by its transform; with none, a
/// half-metre cube at its position.
class RayEntityPicker implements EntityPicker {
  /// A picker refining box hits with [tests].
  RayEntityPicker({List<EntityRayTest> Function()? tests}) : _tests = tests;

  final List<EntityRayTest> Function()? _tests;

  final jge.Ray3 _ray = jge.Ray3();
  final jge.Aabb3 _box = jge.Aabb3();

  @override
  jge.Entity? pickAt(EditorView view, Offset screen, List<jge.Entity> candidates) {
    view.screenToRay(screen, _ray);
    final hits = <(double, jge.Entity)>[];
    for (final entity in candidates) {
      if (!boundsOf(entity, _box)) continue;
      final t = _ray.intersectAabb(_box);
      if (t != null) hits.add((t, entity));
    }
    if (hits.isEmpty) return null;
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    final tests = _tests?.call() ?? const <EntityRayTest>[];
    if (tests.isEmpty) return hits.first.$2;
    jge.Entity? best;
    var bestT = double.infinity;
    for (final (boxT, entity) in hits) {
      // A box no nearer than the best exact hit can't hold a nearer one.
      if (boxT >= bestT) break;
      double? exact;
      for (final test in tests) {
        exact = test.distanceTo(entity, _ray);
        if (exact != null) break;
      }
      final t = exact ?? boxT;
      if (t < bestT) {
        bestT = t;
        best = entity;
      }
    }
    return best;
  }

  /// Where something placed at [screen] goes: on the nearest of
  /// [candidates] under the pointer — the face of its box it meets, facing
  /// out — or else on the ground, facing up.
  SurfacePoint placementAt(EditorView view, Offset screen, Iterable<jge.Entity> candidates) {
    view.screenToRay(screen, _ray);
    var bestT = double.infinity;
    jge.Entity? onto;
    final box = jge.Aabb3();
    for (final entity in candidates) {
      if (!boundsOf(entity, _box)) continue;
      final t = _ray.intersectAabb(_box);
      if (t != null && t > 0 && t < bestT) {
        bestT = t;
        onto = entity;
        box.setFrom(_box);
      }
    }
    if (onto == null) {
      return SurfacePoint(view.screenToGround(screen), jge.Vector3(0, -1, 0));
    }
    final at = jge.Vector3.zero();
    _ray.atInto(bestT, at);
    // The face it met: the side the point is nearest, for its box's size.
    final size = jge.Vector3.zero();
    box.sizeInto(size);
    double near(double v, double lo, double hi, double extent) {
      final d = (v - lo).abs() < (v - hi).abs() ? (v - lo).abs() : (v - hi).abs();
      return d / (extent > 1e-9 ? extent : 1e-9);
    }
    final dx = near(at.x, box.min.x, box.max.x, size.x);
    final dy = near(at.y, box.min.y, box.max.y, size.y);
    final dz = near(at.z, box.min.z, box.max.z, size.z);
    double side(double v, double lo, double hi) => (v - lo).abs() < (v - hi).abs() ? -1 : 1;
    final normal = dy <= dx && dy <= dz
        ? jge.Vector3(0, side(at.y, box.min.y, box.max.y), 0)
        : dx <= dz
        ? jge.Vector3(side(at.x, box.min.x, box.max.x), 0, 0)
        : jge.Vector3(0, 0, side(at.z, box.min.z, box.max.z));
    return SurfacePoint(at, normal, onto: onto);
  }

  @override
  List<jge.Entity> pickInRect(EditorView view, Rect screenRect, Iterable<jge.Entity> candidates) {
    final out = <jge.Entity>[];
    final centre = jge.Vector3.zero();
    for (final entity in candidates) {
      if (!boundsOf(entity, _box)) continue;
      _box.centerInto(centre);
      final at = view.projectToScreen(centre);
      if (at != null && screenRect.contains(at)) out.add(entity);
    }
    return out;
  }

  static final jge.Aabb3 _local = jge.Aabb3();
  static final jge.Aabb3 _part = jge.Aabb3();
  static final jge.Matrix4 _matrix = jge.Matrix4.identity();

  /// [entity]'s box in world space into [out]; false without a transform.
  static bool boundsOf(jge.Entity entity, jge.Aabb3 out) {
    final transform = entity.getComponent<jge.TransformComponent>();
    if (transform == null) return false;
    final definitions = entity.world?.context.definitions;
    _local.setEmpty();
    if (definitions != null) {
      for (final component in entity.components) {
        final extent = definitions.definitionFor(component)?.extent;
        if (extent != null && extent.boundsInto(component, _part)) _local.addBox(_part);
      }
    }
    if (_local.isEmpty) _local.setValues(-0.25, -0.25, -0.25, 0.25, 0.25, 0.25);
    transform.localToWorldInto(_matrix);
    _local.transformInto(_matrix, out);
    return true;
  }
}
