// Sizing things in 3-D by their faces — a shape's, a collider's — with the
// face opposite staying put, as one undo step; and groups: made at the base
// of what they hold, copied whole, listed with their eyes and locks.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

EditorScope _scope() {
  final world = World()..initialize();
  Graphics3D.registerSchemas(world.context);
  Physics3D.registerSchemas(world.context);
  final scope = testScope(world: world);
  scope.sceneState.openScene(EditorScene(name: 'level', mode: SceneMode.threeD));
  return scope;
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

/// A view from 20 m behind the origin, looking along +Z.
OrbitFlyEditorView _ahead() {
  final view = _above()..pitch = 0;
  return view..sync();
}

Vector3 _at(Entity e) => e.getComponent<TransformComponent>()!.position;

Entity _make(EditorScope scope, List<Component> components, String name) {
  final e = scope.world.createEntityWithComponents(components, name: name);
  scope.sceneState.registerEntity(e);
  return e;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Drags the handle of [handles] at [from] to [to], seen through [view].
  void drag(
    EditorScope scope,
    List<ViewportHandle> handles,
    EditorView view,
    Vector3 from,
    Vector3 to, {
    bool snap = false,
    double grid = 0.25,
  }) {
    final session = HandleDragSession(scope);
    expect(session.down(view.projectToScreen(from)!, handles, view), isTrue, reason: 'a handle at $from');
    session
      ..move(view.projectToScreen(to)!, view, snap: snap, grid: grid)
      ..up();
  }

  group('a shape\'s faces', () {
    test('pulled out, the face opposite stays; one undo step of both', () {
      final scope = _scope();
      final cube = _make(scope, [TransformComponent(), Cube3D()], 'Box');
      final view = _above();
      final handles = ShapeSizeHandles().handlesOf(cube, scope);
      expect(handles, hasLength(6));
      drag(scope, handles, view, Vector3(0.5, 0, 0), Vector3(1.5, 0, 0));
      final shape = cube.getComponent<Primitive3D>()! as Cube3D;
      expect(shape.width, closeTo(2, 1e-6));
      expect(_at(cube).x, closeTo(0.5, 1e-6), reason: 'the -X face stays at -0.5');
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(shape.width, closeTo(1, 1e-9));
      expect(_at(cube).x, closeTo(0, 1e-9));
    });

    test('Ctrl snaps the size to the move step, in metres however it is scaled', () {
      final scope = _scope();
      final cube = _make(scope, [TransformComponent(scale: Vector3(2, 1, 1)), Cube3D()], 'Box');
      final view = _above();
      // Its +X face is at 1 m: scaled twice along X.
      drag(scope, ShapeSizeHandles().handlesOf(cube, scope), view, Vector3(1, 0, 0), Vector3(2.4, 0, 0), snap: true, grid: 0.5);
      final shape = cube.getComponent<Primitive3D>()! as Cube3D;
      expect(shape.width * 2, closeTo(3.5, 1e-6), reason: '3.4 m snapped to 3.5 m');
      expect(_at(cube).x - shape.width, closeTo(-1, 1e-6), reason: 'the far face still at -1 m');
    });

    test('a cylinder\'s side sets its radius; its top its height', () {
      final scope = _scope();
      final cylinder = _make(scope, [TransformComponent(), Cylinder3D()], 'Can');
      drag(scope, ShapeSizeHandles().handlesOf(cylinder, scope), _above(), Vector3(0.5, 0, 0), Vector3(1, 0, 0));
      final shape = cylinder.getComponent<Primitive3D>()! as Cylinder3D;
      expect(shape.radius, closeTo(0.75, 1e-6));
      expect(_at(cylinder).x, closeTo(0.25, 1e-6));
      // From the side: its top (up is -Y) pulled up a metre.
      drag(scope, ShapeSizeHandles().handlesOf(cylinder, scope), _ahead(), Vector3(0.25, -0.5, 0), Vector3(0.25, -1.5, 0));
      expect(shape.height, closeTo(2, 1e-6));
      expect(_at(cylinder).y, closeTo(-0.5, 1e-6), reason: 'its base stays on the ground at +0.5');
    });

    test('none in the Collision view, where the collider\'s are', () {
      final scope = _scope();
      final cube = _make(scope, [TransformComponent(), Cube3D(), Collider3D()], 'Box');
      expect(ShapeSizeHandles().handlesOf(cube, scope), hasLength(6));
      expect(ColliderSizeHandles().handlesOf(cube, scope), isEmpty, reason: 'the shape is what is seen');
      scope.designer3D.viewMode.value = ViewMode3D.collision;
      expect(ShapeSizeHandles().handlesOf(cube, scope), isEmpty);
      expect(ColliderSizeHandles().handlesOf(cube, scope), hasLength(6));
    });
  });

  group('a collider\'s faces', () {
    test('a trigger\'s box: its size and offset, the far face kept', () {
      final scope = _scope();
      final trigger = _make(scope, [
        TransformComponent(position: Vector3(3, 0, 0)),
        Collider3D(),
        RigidBody3D(isSensor: true),
      ], 'Trigger');
      final handles = ColliderSizeHandles().handlesOf(trigger, scope);
      expect(handles, hasLength(6));
      drag(scope, handles, _above(), Vector3(3.5, 0, 0), Vector3(4.5, 0, 0));
      final c = trigger.getComponent<Collider3D>()!;
      expect(c.size.x, closeTo(2, 1e-6));
      expect(c.offset.x, closeTo(0.5, 1e-6));
      expect(_at(trigger).x, 3, reason: 'the entity stays; the collider moves in it');
      expect(scope.history.undoEntries, hasLength(1));
    });

    test('a sphere by its radius; a matched shape has none', () {
      final scope = _scope();
      final ball = _make(scope, [TransformComponent(), Collider3D(shape: ColliderShape3D.sphere)], 'Ball');
      drag(scope, ColliderSizeHandles().handlesOf(ball, scope), _above(), Vector3(0.5, 0, 0), Vector3(1.5, 0, 0));
      expect(ball.getComponent<Collider3D>()!.radius, closeTo(1, 1e-6));
      final matched = _make(scope, [TransformComponent(), Collider3D(shape: ColliderShape3D.matchShape)], 'Matched');
      expect(ColliderSizeHandles().handlesOf(matched, scope), isEmpty);
    });
  });

  group('groups', () {
    test('made at the middle of the base of what they hold', () {
      final scope = _scope();
      final a = _make(scope, [TransformComponent(position: Vector3(0, -0.5, 0)), Cube3D()], 'A');
      final b = _make(scope, [TransformComponent(position: Vector3(4, -2.5, 2)), Cube3D()], 'B');
      scope.sceneState
        ..selectEntity(a)
        ..toggleMultiSelect(b);
      final group = scope.entities.groupSelection()!;
      final p = _at(group);
      expect([p.x, p.y, p.z], [closeTo(2, 1e-6), closeTo(0, 1e-6), closeTo(1, 1e-6)]);
      expect(scope.entities.isGroup(group), isTrue);
      expect(scope.entities.isGroup(a), isFalse);
    });

    test('copied whole: a duplicate of a group holds copies of its things', () {
      final scope = _scope();
      final a = _make(scope, [TransformComponent(position: Vector3(0, -0.5, 0)), Cube3D()], 'A');
      final b = _make(scope, [TransformComponent(position: Vector3(2, -0.5, 0)), Cube3D()], 'B');
      scope.sceneState
        ..selectEntity(a)
        ..toggleMultiSelect(b);
      final group = scope.entities.groupSelection()!;
      scope.sceneState.selectEntity(group);
      final before = scope.history.undoEntries.length;
      scope.entities.duplicateSelection(scope.history, gridSize: 32);
      final copy = scope.sceneState.selectedEntity.value!;
      expect(copy.id, isNot(group.id));
      expect(scope.sceneState.multiSelectedIds.value.length, lessThanOrEqualTo(1), reason: 'the copy, not what it holds');
      final inside = copy.getComponent<ChildrenComponent>()!.childIds.map(scope.world.getEntity).toList();
      expect(inside, hasLength(2));
      expect(inside.map((e) => _at(e!).x), [closeTo(1, 1e-6), closeTo(3, 1e-6)], reason: 'a metre along, in order');
      expect(scope.history.undoEntries.length, before + 1);
      scope.history.undo();
      expect(inside.every((e) => !e!.isAlive), isTrue);
    });

    testWidgets('GROUPS lists them; the eye hides one', (tester) async {
      final scope = _scope();
      final a = _make(scope, [TransformComponent(), Cube3D()], 'A');
      scope.sceneState.selectEntity(a);
      final group = scope.entities.groupSelection()!;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox(width: 280, child: Groups3DPanel(scope: scope)))),
      );
      expect(find.text(group.name!), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(scope.view.isHidden(group.id), isTrue);
      expect(scope.view.isHiddenIn(a), isTrue, reason: 'what it holds goes with it');
      expect(tester.takeException(), isNull);
    });
  });
}
