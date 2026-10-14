import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';

import '../../ui/level_designer/state/editor_commands.dart';
import 'scene_validator.dart';

/// Scene checks for 3-D physics, in the editor's Problems: bodies with no
/// shape, shapes a body type cannot have, characters with a body as well,
/// mesh colliders with no model, colliders matching a shape that isn't
/// there, and joints to nothing.
abstract final class Physics3DChecks {
  /// Every check, as one validator.
  static List<SceneProblem> all(ValidationContext context) {
    // 3-D scenes only: a 2-D scene has nothing for these to find.
    if (context.scope.sceneState.editingMode != SceneMode.threeD) return const [];
    final world = context.world;
    final problems = <SceneProblem>[];
    String name(Entity e) => e.name ?? 'entity ${e.id}';

    for (final e in world.query([RigidBody3D])) {
      final body = e.getComponent<RigidBody3D>()!;
      final collider = e.getComponent<Collider3D>();
      if (collider == null) {
        problems.add(SceneProblem(
          message: '${name(e)} has a 3-D rigid body but no collider, so it has no shape and touches nothing.',
          entity: e,
          hint: 'Add a Collider 3D.',
          fixes: [
            ProblemFix(
              label: 'Add a box collider',
              apply: () => context.scope.history.push(
                AddComponentCommand(
                  entity: e,
                  component: Collider3D(),
                  sceneState: context.scope.sceneState,
                ),
              ),
            ),
          ],
        ));
        continue;
      }
      if (body.bodyType == BodyType3D.dynamic &&
          (collider.shape == ColliderShape3D.mesh || collider.shape == ColliderShape3D.heightField)) {
        problems.add(SceneProblem(
          message: '${name(e)} is a dynamic body with a ${collider.shape.name} collider, which only a static or kinematic body can have.',
          severity: ProblemSeverity.error,
          entity: e,
          hint: 'Use a convex hull or simple shapes for something that moves, or make it static.',
          fixes: [
            ProblemFix(
              label: 'Make it a convex hull',
              apply: () => _setShape(context, collider, ColliderShape3D.convexHull),
            ),
          ],
        ));
      }
    }

    for (final e in world.query([CharacterBody3D])) {
      if (e.hasComponent<RigidBody3D>()) {
        problems.add(SceneProblem(
          message: '${name(e)} is a character and a rigid body at once; the two would fight over where it is.',
          severity: ProblemSeverity.error,
          entity: e,
          hint: 'Keep the Character Body 3D and remove the Rigid Body 3D.',
        ));
      }
    }

    for (final e in world.query([Collider3D])) {
      final c = e.getComponent<Collider3D>()!;
      if (c.shape == ColliderShape3D.matchShape && !e.components.any((x) => x is SolidShapeSource)) {
        problems.add(SceneProblem(
          message: "${name(e)}'s collider matches its shape, but it has no 3-D shape to match, so it makes no body.",
          severity: ProblemSeverity.error,
          entity: e,
          hint: 'Give it a 3-D shape (a Cube, Stairs, …), or pick a shape for the collider.',
          fixes: [
            ProblemFix(
              label: 'Make it a box',
              apply: () => _setShape(context, c, ColliderShape3D.box),
            ),
          ],
        ));
      }
      final needsModel = c.shape == ColliderShape3D.mesh || c.shape == ColliderShape3D.convexHull;
      if (needsModel && c.model.trim().isEmpty) {
        problems.add(SceneProblem(
          message: "${name(e)}'s ${c.shape.name} collider names no model to take its shape from.",
          entity: e,
          hint: 'Pick the model (.glb or .gltf) in its Model field.',
        ));
      } else if (needsModel && !context.fileExists(c.model)) {
        problems.add(SceneProblem(
          message: "${name(e)}'s collider uses ${c.model}, which isn't there.",
          severity: ProblemSeverity.error,
          entity: e,
        ));
      }
    }

    for (final e in world.entities) {
      for (final joint in e.components.whereType<Joint3D>()) {
        final target = joint.connectedBody;
        if (target.isNone) continue;
        if (target.resolve(world, e, includeInactive: true) == null) {
          problems.add(SceneProblem(
            message: "${name(e)}'s ${joint.runtimeType} is joined to $target, which isn't in the scene.",
            entity: e,
            hint: 'Pick the body it joins, or clear the field to join it to the world.',
          ));
        }
      }
    }
    return problems;
  }

  static void _setShape(ValidationContext context, Collider3D collider, ColliderShape3D shape) {
    final field = context.scope.definitions.definitionFor(collider)?.field('shape');
    final write = field?.write;
    if (field == null || write == null) {
      collider.shape = shape;
      return;
    }
    context.scope.history.push(
      ComponentFieldCommand(
        label: 'Collider shape',
        component: collider,
        write: write,
        before: field.read(collider),
        after: shape,
        sceneState: context.scope.sceneState,
      ),
    );
  }
}
