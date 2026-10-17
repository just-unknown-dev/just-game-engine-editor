// Placing in a 3-D scene: Place's preview, a press dragged to aim, the
// wheel spinning it, a stamped trail as one undo step, standing on a wall,
// a random size; then End dropping things to the ground, a duplicate that
// repeats how far the last copy was moved, an array round a circle, and the
// palette's search, favourites and pictures.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

EditorScope _scope() {
  final world = World()..initialize();
  Graphics3D.registerSchemas(world.context);
  final scope = testScope(world: world);
  scope.sceneState.openScene(EditorScene(name: 'level', mode: SceneMode.threeD));
  return scope;
}

LevelDesignerSession _open(
  EditorScope scope,
  EditorView view, {
  ModifierKeys Function()? modifiers,
}) {
  final session = LevelDesignerSession(
    scope: scope,
    uniqueName: scope.entities.uniqueName.call,
    onDuplicate: () {},
    onDelete: () {},
    onArray: (_, _) {},
    readModifiers: modifiers ?? () => const ModifierKeys(),
    camera: () => view,
  );
  addTearDown(session.dispose);
  return session;
}

/// A view from 20 m above the origin, looking down.
OrbitFlyEditorView _above() {
  final view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(400, 400)))
    ..viewportSize = const Size(400, 400)
    ..pivot.setValues(0, 0, 0)
    ..distance = 20
    ..yaw = 0
    ..pitch = -math.pi / 2;
  return view..sync();
}

List<Entity> _cubes(EditorScope scope) => [
  for (final e in scope.world.entities)
    if (e.getComponent<Primitive3D>() is Cube3D) e,
];

Vector3 _at(Entity e) => e.getComponent<TransformComponent>()!.position;

Entity _cube(EditorScope scope, Vector3 at, String name) {
  final e = scope.world.createEntityWithComponents([TransformComponent(position: at), Cube3D()], name: name);
  scope.sceneState.registerEntity(e);
  return e;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Place', () {
    late EditorScope scope;
    late OrbitFlyEditorView view;
    late LevelDesignerSession session;
    late Place3DTool tool;
    var shift = false;

    setUp(() {
      scope = _scope();
      view = _above();
      shift = false;
      session = _open(scope, view, modifiers: () => ModifierKeys(shift: shift));
      session.setTool(BuiltInTools.place);
      session.controller.activePrefabId.value = 'shape.cube';
      tool = session.tools.byId(BuiltInTools.place)! as Place3DTool;
    });

    Offset screen(Vector3 p) => view.projectToScreen(p)!;

    void press(Vector3 p) => session.onPointerDown(Offset.zero, 32, screen: screen(p), canvasSize: const Size(400, 400));
    void move(Vector3 p) => session.onPointerMove(Offset.zero, 32, screen: screen(p), canvasSize: const Size(400, 400));
    void release(Vector3 p) => session.onPointerUp(Offset.zero, 32, screen: screen(p), canvasSize: const Size(400, 400));

    test('shows what a click would make, where it would go', () {
      session.onPointerHover(Offset.zero, 32, screen: screen(Vector3(2, 0, 3)), canvasSize: const Size(400, 400));
      final ghost = tool.ghost.value!;
      expect([ghost.at.position.x, ghost.at.position.z], [closeTo(2, 1e-6), closeTo(3, 1e-6)]);
      expect(ghost.edges, hasLength(24), reason: 'a cube\'s twelve edges, not its triangles');
      final middle = Vector3.zero();
      ghost.world.transformPointInto(Vector3.zero(), middle);
      expect(middle.y, closeTo(-0.5, 1e-6), reason: 'resting on the ground');
      expect(_cubes(scope), isEmpty, reason: 'nothing made yet');
    });

    test('a press dragged turns it to face the pointer; made on release', () {
      press(Vector3.zero());
      expect(_cubes(scope), isEmpty);
      move(Vector3(3, 0, 0));
      release(Vector3(3, 0, 0));
      final cube = _cubes(scope).single;
      final q = Quaternion.identity();
      cube.getComponent<TransformComponent>()!.rotationInto(q);
      final forward = Vector3(0, 0, 1);
      q.rotate(forward);
      expect([forward.x, forward.y, forward.z], [closeTo(1, 1e-6), closeTo(0, 1e-6), closeTo(0, 1e-6)]);
      expect(_at(cube).x, closeTo(0, 1e-6), reason: 'where it was pressed');
      expect(scope.history.undoEntries, hasLength(1));
    });

    test('Shift+wheel spins it; the wheel alone is the view\'s', () {
      final at = screen(Vector3.zero());
      expect(session.onScroll(Offset.zero, 32, const Offset(0, 100), screen: at, canvasSize: const Size(400, 400)), isFalse);
      shift = true;
      expect(session.onScroll(Offset.zero, 32, const Offset(0, 100), screen: at, canvasSize: const Size(400, 400)), isTrue);
      expect(scope.designer3D.placeSpin.value, Place3DTool.spinNotch);
      // Sideways, as some systems turn a Shift+wheel.
      session.onScroll(Offset.zero, 32, const Offset(-100, 0), screen: at, canvasSize: const Size(400, 400));
      expect(scope.designer3D.placeSpin.value, 0);
    });

    test('Stamp lays a trail, Spacing apart, as one undo step', () {
      scope.designer3D
        ..stamp.value = true
        ..stampSpacing.value = 1;
      press(Vector3.zero());
      for (var x = 0.5; x <= 3.5; x += 0.5) {
        move(Vector3(x, 0, 0));
      }
      release(Vector3(3.5, 0, 0));
      final cubes = _cubes(scope);
      expect(cubes.length, inInclusiveRange(4, 5));
      expect(cubes.every((c) => (_at(c).y + 0.5).abs() < 1e-6), isTrue, reason: 'each on the ground, not on the last');
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(_cubes(scope), isEmpty);
    });

    test('a random size, resting all the same', () {
      scope.designer3D.randomSize.value = 0.5;
      tool.onActivate();
      press(Vector3.zero());
      release(Vector3.zero());
      final cube = _cubes(scope).single;
      final s = cube.getComponent<TransformComponent>()!.scale.x;
      expect(s, inInclusiveRange(0.5, 1.5));
      expect(_at(cube).y, closeTo(-0.5 * s, 1e-6));
    });
  });

  test('Align stands it on a wall, its up out of the wall', () {
    final scope = _scope();
    final prefab = scope.prefabs.byId('shape.cube')!;
    final cube = scope.entities.spawnPrefab(prefab, SurfacePoint(Vector3(4, -1, 0), Vector3(1, 0, 0)), align: true);
    final p = _at(cube);
    expect([p.x, p.y, p.z], [closeTo(4.5, 1e-6), closeTo(-1, 1e-6), closeTo(0, 1e-6)]);
    final q = Quaternion.identity();
    cube.getComponent<TransformComponent>()!.rotationInto(q);
    final up = Vector3(0, -1, 0);
    q.rotate(up);
    expect([up.x, up.y, up.z], [closeTo(1, 1e-6), closeTo(0, 1e-6), closeTo(0, 1e-6)]);
  });

  group('End drops to the ground', () {
    test('onto what is under it, else the working plane; one undo step', () {
      final scope = _scope();
      _cube(scope, Vector3(0, -0.5, 0), 'floor');
      final high = _cube(scope, Vector3(0, -5, 0), 'high');
      final apart = _cube(scope, Vector3(6, -3, 0), 'apart');
      scope.sceneState
        ..selectEntity(high)
        ..toggleMultiSelect(apart);
      final picker = RayEntityPicker(tests: () => scope.pickTests);
      final moved = scope.entities.dropSelectionToGround(
        below: (ray, ignore) => picker.placementAlong(
          ray,
          scope.world.entities.where((e) => !ignore.contains(e)),
        ),
        plane: scope.designer3D.plane,
      );
      expect(moved, 2);
      expect(_at(high).y, closeTo(-1.5, 1e-6), reason: 'on the floor cube\'s top');
      expect(_at(apart).y, closeTo(-0.5, 1e-6), reason: 'on the plane');
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect([_at(high).y, _at(apart).y], [-5, -3]);
    });
  });

  test('a duplicate of the copy repeats how far it was moved', () {
    final scope = _scope();
    final a = _cube(scope, Vector3(0, -0.5, 0), 'Box');
    scope.sceneState.selectEntity(a);
    scope.entities.duplicateSelection(scope.history, gridSize: 32);
    final first = scope.sceneState.selectedEntity.value!;
    expect(_at(first).x, closeTo(1, 1e-9), reason: 'a metre along X at first');
    scope.sceneState.setPosition3(first, Vector3(0, -0.5, 3));
    scope.entities.duplicateSelection(scope.history, gridSize: 32);
    final second = scope.sceneState.selectedEntity.value!;
    final p = _at(second);
    expect([p.x, p.y, p.z], [closeTo(0, 1e-9), closeTo(-0.5, 1e-9), closeTo(6, 1e-9)]);
  });

  test('an array round a circle: one undo step, each facing the middle', () {
    final scope = _scope();
    final a = _cube(scope, Vector3(2, -0.5, 0), 'Pillar');
    scope.sceneState.selectEntity(a);
    scope.entities.arraySelection3D(
      scope.history,
      const Array3DSpec(mode: ArrayMode3D.radial, around: 4, radius: 2),
      _at(a),
    );
    final cubes = _cubes(scope);
    expect(cubes, hasLength(4));
    for (final c in cubes) {
      expect((_at(c) - Vector3(0, -0.5, 0)).length, closeTo(2, 1e-6));
    }
    final turned = cubes.where((c) => c.getComponent<TransformComponent>()!.eulerY.abs() > 1e-6);
    expect(turned, hasLength(3));
    expect(scope.history.undoEntries, hasLength(1));
  });

  testWidgets('the palette: search, favourites first, shape pictures', (tester) async {
    final scope = _scope();
    final session = _open(scope, _above());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SizedBox(width: 260, height: 900, child: PrefabPalettePanel(session: session))),
      ),
    );
    expect(find.text('Cube'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(PrefabPalettePanel), matching: find.byType(CustomPaint)),
      findsWidgets,
      reason: 'the shapes drawn',
    );

    await tester.enterText(find.byType(TextField), 'cyl');
    await tester.pump();
    expect(find.text('Cylinder'), findsOneWidget);
    expect(find.text('Cube'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('FAVOURITES'), findsNothing);
    // Shown at once; the write to the store is not waited for.
    unawaited(PrefabFavourites.toggle(scope.prefs, 'shape.torus'));
    await tester.pump();
    expect(find.text('FAVOURITES'), findsOneWidget);
    expect(find.text('Torus'), findsNWidgets(2), reason: 'first, and in its own place');
    expect(tester.takeException(), isNull);
  });
}
