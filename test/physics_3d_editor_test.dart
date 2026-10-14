// The editor's built-in 3-D physics: what it adds (only where the engine
// has 3-D physics), the outlines it draws, the checks it makes and their
// fixes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorScope scope({bool physics3D = true, SceneMode mode = SceneMode.threeD}) {
    final world = World()..initialize();
    if (physics3D) Physics3D.registerSchemas(world.context);
    final s = EditorScope(world: world);
    addTearDown(s.dispose);
    s.sceneState.openScene(EditorScene(name: 'deep', mode: mode));
    return s;
  }

  List<SceneProblem> check(EditorScope s) =>
      Physics3DChecks.all(ValidationContext(scope: s, projectRoot: Directory.systemTemp.path));

  test('with 3-D physics it adds the collider outlines, Solid and Trigger, and its checks', () {
    final s = scope();
    expect(s.viewportOverlays.map((o) => o.id), ['physics3d.colliders']);
    expect(s.prefabVariants.map((v) => v.id), containsAll(['solid', 'trigger']));
    expect(BuiltInValidators.all, contains(Physics3DChecks.all));
  });

  test('a 2-D project gets none of it', () {
    final s = scope(physics3D: false, mode: SceneMode.twoD);
    expect(s.viewportOverlays.map((o) => o.id), isNot(contains('physics3d.colliders')));
    expect(s.prefabVariants.map((v) => v.id), isNot(contains('solid')));
  });

  test('its checks find nothing in a 2-D scene', () {
    final s = scope(mode: SceneMode.twoD);
    s.world.createEntityWithComponents([TransformComponent(), RigidBody3D()], name: 'Crate');
    expect(check(s), isEmpty);
  });

  test('outlines: a box has twelve edges, rounder shapes their rings', () {
    expect(ColliderOverlay3D.shapeLines(Collider3D()), hasLength(12));
    final box = ColliderOverlay3D.boxLines(Vector3(1, 2, 3));
    expect(box.every((l) => l.$1.distanceTo(l.$2) > 0), isTrue);
    expect(box.map((l) => l.$1.distanceTo(l.$2)).toSet(), {2, 4, 6});
    final capsule = ColliderOverlay3D.capsuleLines(0.5, 2);
    final ys = [for (final (a, b) in capsule) ...[a.y, b.y]];
    expect(ys.reduce((a, b) => a < b ? a : b), closeTo(-1, 1e-9), reason: 'its caps reach the full height');
    expect(ys.reduce((a, b) => a > b ? a : b), closeTo(1, 1e-9));
  });

  group('checks', () {
    test('a body with no collider; its fix adds one, undoably', () {
      final s = scope();
      final e = s.world.createEntityWithComponents([TransformComponent(), RigidBody3D()], name: 'Crate');
      final problems = check(s);
      expect(problems.single.message, contains('no collider'));
      problems.single.fixes.single.apply();
      expect(e.hasComponent<Collider3D>(), isTrue);
      expect(check(s), isEmpty);
      s.history.undo();
      expect(e.hasComponent<Collider3D>(), isFalse);
    });

    test('a moving body with a mesh shape is an error; the fix makes it a hull', () {
      final s = scope();
      final c = Collider3D(shape: ColliderShape3D.mesh, model: 'missing.glb');
      s.world.createEntityWithComponents([TransformComponent(), RigidBody3D(), c], name: 'Rock');
      final problems = check(s);
      final moving = problems.firstWhere((p) => p.message.contains('dynamic body'));
      expect(moving.severity, ProblemSeverity.error);
      expect(problems.any((p) => p.message.contains("isn't there")), isTrue);
      moving.fixes.single.apply();
      expect(c.shape, ColliderShape3D.convexHull);
    });

    test('a character with a body too, a hull with no model, a joint to nobody', () {
      final s = scope();
      s.world.createEntityWithComponents([TransformComponent(), CharacterBody3D(), RigidBody3D(), Collider3D()], name: 'Hero');
      s.world.createEntityWithComponents([TransformComponent(), Collider3D(shape: ColliderShape3D.convexHull)], name: 'Hull');
      s.world.createEntityWithComponents([
        TransformComponent(),
        Collider3D(),
        RigidBody3D(),
        HingeJoint3D(connectedBody: const EntityTarget.name('Nobody')),
      ], name: 'Door');
      final messages = check(s).map((p) => p.message).toList();
      expect(messages, contains(contains('a character and a rigid body')));
      expect(messages, contains(contains('names no model')));
      expect(messages, contains(contains("isn't in the scene")));
    });
  });
}
