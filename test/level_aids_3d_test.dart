// The 3-D designer's aids: how far a jump carries (from a kit's level
// aids), the checks against how a level is played — a spawn point over
// nothing, a solid over the void, things below the kill height — and the
// ruler.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/aids/level_checks_3d.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/aids/ruler_3d.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';

/// A kit whose things are lost below 10 m down.
class _Aids extends LevelAids {
  const _Aids();

  @override
  MovementProfile movementOf(World world) => const MovementProfile(jumpSpeed: 9.81, gravity: 9.81, runSpeed: 5);

  @override
  double killHeight(World world) => 10;
}

class _Kit extends EditorModule {
  @override
  String get id => 'test.kit';
  @override
  String get name => 'Kit';
  @override
  LevelAids get levelAids => const _Aids();
}

EditorScope _scope({List<EditorModule> modules = const []}) {
  final world = World()..initialize();
  Graphics3D.registerSchemas(world.context);
  Physics3D.registerSchemas(world.context);
  final scope = testScope(world: world, modules: modules);
  scope.sceneState.openScene(EditorScene(name: 'level', mode: SceneMode.threeD));
  return scope;
}

Entity _make(EditorScope scope, List<Component> components, String name) {
  final e = scope.world.createEntityWithComponents(components, name: name);
  scope.sceneState.registerEntity(e);
  return e;
}

List<String> _problems(EditorScope scope) => [
  for (final p in LevelChecks3D.all(ValidationContext(scope: scope))) p.message,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a jump: as high as v²/2g, as far as the run takes it while up', () {
    const move = MovementProfile(jumpSpeed: 9.81, gravity: 9.81, runSpeed: 5);
    expect(move.jumpHeight, closeTo(4.905, 1e-9));
    expect(move.airTime, closeTo(2, 1e-9));
    expect(move.jumpDistance, closeTo(10, 1e-9));
    expect(const MovementProfile(jumpSpeed: 5, gravity: 0, runSpeed: 5).jumpHeight, 0);
  });

  test('every module\'s aids are asked: movement, kill height', () {
    final scope = _scope(modules: [_Kit()]);
    expect(scope.levelAids, hasLength(1));
    expect(scope.movement!.jumpDistance, closeTo(10, 1e-9));
    expect(scope.killHeight, 10);
    expect(_scope().killHeight, isNull);
  });

  group('checks', () {
    test('a spawn point over nothing; one on the ground is fine', () {
      final scope = _scope();
      _make(scope, [TransformComponent(position: Vector3(0, -2, 0)), SpawnComponent()], 'Over');
      expect(_problems(scope), [contains('Nothing under the spawn point Over')]);
      _make(scope, [TransformComponent(position: Vector3(0, 0.5, 0)), Cube3D(width: 10, depth: 10)], 'Ground');
      expect(_problems(scope), isEmpty, reason: 'the ground is under it now');
    });

    test('a solid over the void; over a kill zone it is not', () {
      final scope = _scope();
      _make(scope, [TransformComponent(position: Vector3(0, -5, 0)), Cube3D(), Collider3D()], 'Ledge');
      expect(_problems(scope), [contains('Nothing at all under Ledge')]);
      _make(scope, [
        TransformComponent(position: Vector3(0, 20, 0)),
        Collider3D(size: Vector3(20, 2, 20)),
        RigidBody3D(bodyType: BodyType3D.static, isSensor: true),
      ], 'Pit');
      expect(_problems(scope), isEmpty);
    });

    test('below the kill height: lost as play starts', () {
      final scope = _scope(modules: [_Kit()]);
      _make(scope, [TransformComponent(position: Vector3(0, 30, 0)), Cube3D(width: 50, depth: 50), Collider3D()], 'Deep');
      _make(scope, [TransformComponent(position: Vector3(0, 0, 0)), Cube3D(width: 50, depth: 50), Collider3D()], 'Floor');
      final problems = _problems(scope);
      expect(problems, contains(contains('Deep is below the kill height (-10.0 m)')));
      expect(problems.where((p) => p.contains('Floor')), isEmpty, reason: 'above it, and over Deep');
    });

    test('none in a 2-D scene', () {
      final scope = _scope();
      scope.sceneState.openScene(EditorScene(name: 'flat'));
      _make(scope, [TransformComponent(), SpawnComponent()], 'Spawn');
      expect(_problems(scope), isEmpty);
    });
  });

  test('Measure: from one point to another, in metres, up as up', () {
    final scope = _scope();
    final view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(400, 400)))
      ..viewportSize = const Size(400, 400)
      ..pivot.setValues(0, 0, 0)
      ..distance = 20
      ..yaw = 0
      ..pitch = -math.pi / 2;
    view.sync();
    final session = LevelDesignerSession(
      scope: scope,
      uniqueName: scope.entities.uniqueName.call,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => const ModifierKeys(),
      camera: () => view,
    );
    addTearDown(session.dispose);
    session.setTool(BuiltInTools.measure);
    final tool = session.tools.byId(BuiltInTools.measure)! as Measure3DTool;
    Offset at(double x, double z) => view.projectToScreen(Vector3(x, 0, z))!;
    session.onPointerDown(Offset.zero, 32, screen: at(0, 0), canvasSize: const Size(400, 400));
    session.onPointerMove(Offset.zero, 32, screen: at(3, 4), canvasSize: const Size(400, 400));
    session.onPointerUp(Offset.zero, 32, screen: at(3, 4), canvasSize: const Size(400, 400));
    final (a, b) = tool.measured.value!;
    expect((b - a).length, closeTo(5, 1e-6));
    expect(session.controller.status.value, startsWith('5.00 m'));
    expect(Measure3DTool.describe(Vector3.zero(), Vector3(0, -2, 0)), contains('up 2.00'));
  });
}
