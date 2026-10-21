import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';

import 'package:just_editor_core/host.dart';

/// Checks a 3-D level's shape against how it is played: a spawn point
/// with nothing under it, solid things with nothing at all under them
/// (a fall from them never lands — unless the game kit has a kill height,
/// which catches every fall), and things below the kill height (the game
/// kit's: lost as soon as play starts). Nothing in a 2-D scene.
abstract final class LevelChecks3D {
  /// How far down a check looks for something to land on (metres).
  static const double reach = 500;

  /// Every check.
  static List<SceneProblem> all(ValidationContext context) {
    final scope = context.scope;
    if (scope.sceneState.editingMode != SceneMode.threeD) return const [];
    final world = context.world;
    final picker = RayEntityPicker(tests: () => scope.pickTests);
    final drawn = [
      for (final e in world.entities)
        if (e.isAlive &&
            e.isActive &&
            !scope.view.isHiddenIn(e) &&
            e.hasComponent<TransformComponent>())
          e,
    ];
    // What can be landed on: what has a size of its own (a light's or a
    // camera's stand-in box is not ground).
    final solid = [
      for (final e in drawn)
        if (e.components.any(
          (c) => scope.definitions.definitionFor(c)?.extent != null,
        ))
          e,
    ];
    final box = Aabb3();
    // Each solid's box, worked out once: a ray straight down can only meet
    // a box it passes through, so most are ruled out without a picker's
    // closer look at their shapes.
    final solidBoxes = [
      for (final e in solid)
        if (RayEntityPicker.boundsOf(e, box)) (e, Aabb3.copy(box)),
    ];

    // What is under [from], leaving out [self] and what is under it.
    bool somethingBelow(Entity self, Vector3 from) {
      // From a hair above it (+Y is down), so what it stands on is met.
      final top = from.y - 1e-3;
      const slack = 1e-6;
      final under = [
        for (final (e, b) in solidBoxes)
          if (b.max.y >= top &&
              b.min.y - from.y <= reach &&
              from.x >= b.min.x - slack &&
              from.x <= b.max.x + slack &&
              from.z >= b.min.z - slack &&
              from.z <= b.max.z + slack &&
              !identical(e, self) &&
              !_isInside(e, self))
            e,
      ];
      if (under.isEmpty) return false;
      final ray = Ray3()..setValues(from.x, top, from.z, 0, 1, 0);
      final hit = picker.placementAlong(ray, under);
      return hit != null && hit.position.y - from.y <= reach;
    }

    final kill = scope.killHeight;
    final out = <SceneProblem>[];
    for (final e in drawn) {
      final name = e.name ?? 'An entity';
      final at = e.getComponent<TransformComponent>()!.position;
      final spawn = e.getComponent<SpawnComponent>();
      if (spawn != null && !somethingBelow(e, at)) {
        out.add(
          SceneProblem(
            entity: e,
            message:
                'Nothing under the spawn point $name: what spawns there falls.',
            hint: 'Put ground under it, or move it over some.',
          ),
        );
      }
      final collider = e.getComponent<Collider3D>();
      final sensor = e.getComponent<RigidBody3D>()?.isSensor ?? false;
      final dynamicBody =
          e.getComponent<RigidBody3D>()?.bodyType == BodyType3D.dynamic;
      // With a kill height every fall is caught there; what is below it
      // is said below.
      if (kill == null &&
          collider != null &&
          !sensor &&
          !dynamicBody &&
          RayEntityPicker.boundsOf(e, box)) {
        final base = Vector3(
          (box.min.x + box.max.x) / 2,
          box.max.y,
          (box.min.z + box.max.z) / 2,
        );
        if (!somethingBelow(e, base)) {
          out.add(
            SceneProblem(
              entity: e,
              message:
                  'Nothing at all under $name: a fall from it never lands.',
              hint: 'Put ground or a kill zone under it.',
            ),
          );
        }
      }
      // +Y is down: its top lower than the kill height is past it.
      if (kill != null &&
          (spawn != null || (collider != null && !sensor)) &&
          RayEntityPicker.boundsOf(e, box)) {
        if (box.min.y > kill) {
          out.add(
            SceneProblem(
              entity: e,
              message:
                  '$name is below the kill height (${(-kill).toStringAsFixed(1)} m): '
                  'it is lost as soon as play starts.',
              hint: 'Raise it above the kill height.',
            ),
          );
        }
      }
    }
    return out;
  }

  // Whether [e] is somewhere under [ancestor] in the tree.
  static bool _isInside(Entity e, Entity ancestor) {
    var parent = e.getComponent<ParentComponent>()?.parentId;
    for (var guard = 0; parent != null && guard < 64; guard++) {
      if (parent == ancestor.id) return true;
      parent = e.world
          ?.getEntity(parent)
          ?.getComponent<ParentComponent>()
          ?.parentId;
    }
    return false;
  }
}
