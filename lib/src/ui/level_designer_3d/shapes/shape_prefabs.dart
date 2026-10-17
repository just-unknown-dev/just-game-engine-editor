import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';

import 'package:just_editor_core/host.dart';

/// The 3-D shapes as the default kit's prefabs: in a 3-D scene's palette
/// and its viewport menu (Add › Shapes), each placed resting on what was
/// clicked, its side facing the surface against it.
abstract final class ShapePrefabs {
  /// Where they are listed.
  static const String category = 'Shapes';

  /// Their accent colour.
  static const Color color = Color(0xFF26A69A);

  /// Every shape.
  static List<PrefabDefinition> get all => [
    _prefab('cube', 'Cube', Icons.view_in_ar_outlined, Cube3D.new, 'A box, 1 m each way.'),
    _prefab('sphere', 'Sphere', Icons.circle_outlined, Sphere3D.new, 'A ball, 1 m across.'),
    _prefab('plane', 'Plane', Icons.crop_landscape_outlined, Plane3D.new, 'A flat 10 m square: a floor.'),
    _prefab('cylinder', 'Cylinder', Icons.storage_outlined, Cylinder3D.new, 'An upright cylinder.'),
    _prefab('capsule', 'Capsule', Icons.medication_outlined, Capsule3D.new, 'A cylinder with round ends.'),
    _prefab('cone', 'Cone', Icons.change_history, Cone3D.new, 'A cone, its tip up.'),
    _prefab('torus', 'Torus', Icons.donut_large, Torus3D.new, 'A ring lying flat.'),
    _prefab('ramp', 'Ramp', Icons.trending_up, Ramp3D.new, 'A wedge to walk up, rising towards +Z.'),
    _prefab('stairs', 'Stairs', Icons.stairs_outlined, Stairs3D.new, 'Five steps rising towards +Z.'),
    _prefab('arch', 'Arch', Icons.architecture, Arch3D.new, 'A half-round arch on two feet.'),
    _prefab('polygon', 'Polygon', Icons.hexagon_outlined, Polygon3D.new, 'An outline raised to a height: drag its corners.'),
  ];

  static PrefabDefinition _prefab(
    String id,
    String name,
    IconData icon,
    Primitive3D Function() make,
    String description,
  ) => PrefabDefinition(
    id: 'shape.$id',
    name: name,
    category: category,
    icon: icon,
    color: color,
    description: description,
    namePrefix: name,
    placement: PrefabPlacement.point,
    dimensions: Dimensions.threeD,
    build: (position, size) => [
      TransformComponent(position: Vector3(position.dx, position.dy, 0)),
      make(),
    ],
    buildAt: (at) {
      final shape = make();
      return [TransformComponent(position: restingOn(shape, at)), shape];
    },
  );

  /// Where [shape]'s entity goes so that it rests on [at]'s surface: its
  /// middle moved off the surface along its normal by half its size that
  /// way (a hair more for a flat one, so it does not fight the surface).
  static Vector3 restingOn(Primitive3D shape, SurfacePoint at) {
    final b = Aabb3();
    shape.boundsInto(b);
    final n = at.normal;
    final reach =
        n.x.abs() * (b.max.x - b.min.x) / 2 + n.y.abs() * (b.max.y - b.min.y) / 2 + n.z.abs() * (b.max.z - b.min.z) / 2;
    final lift = reach + (reach < 1e-6 ? 0.001 : 0);
    return Vector3(
      at.position.x + n.x * lift - (b.min.x + b.max.x) / 2,
      at.position.y + n.y * lift - (b.min.y + b.max.y) / 2,
      at.position.z + n.z * lift - (b.min.z + b.max.z) / 2,
    );
  }
}
