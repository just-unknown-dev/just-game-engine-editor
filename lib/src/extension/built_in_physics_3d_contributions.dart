import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine/physics_3d.dart';

import '../core/physics/collider_overlay_3d.dart';
import 'package:just_editor_core/host.dart';
import '../ui/inspector/physics/physics_body_extras.dart';

/// What the editor itself brings for 3-D physics, through the seams a module
/// uses: collider outlines in the viewport, the rigid body's material
/// presets in the inspector, and a Solid and a Trigger of every 3-D shape
/// in the Add menu. (Its scene checks are among the built-in validators,
/// `Physics3DChecks`.)
///
/// Only for a project whose engine has 3-D physics ([appliesTo]): a 2-D
/// project sees none of it, and offers nothing it could not save. Within a
/// 3-D project the outlines and variants are 3-D only, so a 2-D scene does
/// not show them either.
abstract final class BuiltInPhysics3DContributions {
  /// Whether [context]'s engine has 3-D physics: its components are known.
  static bool appliesTo(jge.EngineContext context) =>
      context.definitions.definitionByType('RigidBody3D') != null;

  /// The 3-D collider outlines.
  static List<ViewportOverlay> get viewportOverlays => [ColliderOverlay3D()];

  /// The rigid body's material presets.
  static List<ComponentEditorExtras> get extras => [
    PhysicsBodyExtras.materialsFor('RigidBody3D'),
  ];

  /// A Solid and a Trigger of every 3-D shape.
  static List<PrefabVariant> get prefabVariants => [solid, trigger];

  static bool _hasShape(List<jge.Component> components) =>
      components.any((c) => c is jge.SolidShapeSource);

  /// Something to stand on and bump into: a static body matching the shape.
  static PrefabVariant get solid => PrefabVariant(
    id: 'solid',
    name: 'Solid',
    category: 'Solid shapes',
    description:
        'Something to stand on and bump into: a static body matching the shape.',
    appliesTo: _hasShape,
    extra: () => [
      RigidBody3D(bodyType: BodyType3D.static),
      Collider3D(shape: ColliderShape3D.matchShape),
    ],
  );

  /// Reports what enters and leaves it: a sensor matching the shape.
  static PrefabVariant get trigger => PrefabVariant(
    id: 'trigger',
    name: 'Trigger',
    category: 'Trigger shapes',
    description:
        'Reports what enters and leaves it: a sensor matching the shape.',
    appliesTo: _hasShape,
    extra: () => [
      RigidBody3D(bodyType: BodyType3D.static, isSensor: true),
      Collider3D(shape: ColliderShape3D.matchShape),
    ],
  );
}
