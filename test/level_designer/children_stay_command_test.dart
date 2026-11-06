// What is under an entity resized, turned to a typed angle or flipped in
// the Level Designer: where it was in the world, then, at Play (a pass of
// the transform hierarchy) and after an undo and a redo — never moved by
// what its parent did, with no undo step to show for it.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import '../support/test_scope.dart';

LevelDesignerSession _session(EditorScope scope) {
  final session = LevelDesignerSession(
    scope: scope,
    uniqueName: (p) => p,
    onDuplicate: () {},
    onDelete: () {},
    onArray: (_, _) {},
    readModifiers: () => const ModifierKeys(),
  );
  addTearDown(session.dispose);
  return session;
}

Entity _block(World world, String name, double x, double y) =>
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, y, 0)),
      Rectangle2DComponent(width: 64, height: 32),
      LayerComponent(),
    ], name: name);

void main() {
  late World world;
  late EditorScope scope;
  late LevelDesignerSession session;
  late Entity parent;
  late Entity child;
  late Entity grandchild;

  double x(Entity e) => e.getComponent<TransformComponent>()!.position.x;
  double y(Entity e) => e.getComponent<TransformComponent>()!.position.y;
  double angle(Entity e) => e.getComponent<TransformComponent>()!.angle;

  /// What the world does at Play, and a parent's next settle in the editor.
  void settle() => world.transformHierarchy.propagate();

  void expectChildrenHome() {
    expect([x(child), y(child)], [closeTo(200, 1e-6), closeTo(16, 1e-6)]);
    expect(
      [x(grandchild), y(grandchild)],
      [closeTo(260, 1e-6), closeTo(16, 1e-6)],
    );
  }

  setUp(() {
    world = World()..initialize();
    scope = testScope(world: world);
    session = _session(scope);
    parent = _block(world, 'Parent', 32, 16); // bounds 0,0 → 64,32
    child = _block(world, 'Child', 200, 16);
    grandchild = _block(world, 'Grandchild', 260, 16);
    placeEntity(
      child,
      world: world,
      sceneState: session.sceneState,
      slot: HierarchySlot(parentId: parent.id, index: -1),
    );
    placeEntity(
      grandchild,
      world: world,
      sceneState: session.sceneState,
      slot: HierarchySlot(parentId: child.id, index: -1),
    );
    settle(); // as a scene load does
    expectChildrenHome();
  });

  test('a resize by the right-edge handle leaves the children where they '
      'are, at Play and after an undo and a redo', () {
    session.sceneState.selectEntity(parent);
    scope.view.transformMode.value = TransformMode.scale;
    session
      ..onPointerDown(const Offset(64, 16), 32)
      ..onPointerMove(const Offset(128, 16), 32)
      ..onPointerUp(const Offset(128, 16), 32);
    expect(x(parent), 64, reason: 'the parent moved with its bounds');
    settle();
    expectChildrenHome();
    expect(scope.history.undoEntries, hasLength(1));

    scope.history.undo();
    expect(x(parent), 32);
    expectChildrenHome();
    settle();
    expectChildrenHome();

    scope.history.redo();
    expect(x(parent), 64);
    settle();
    expectChildrenHome();
  });

  test('a typed angle turns the parent alone, at Play and after an undo '
      'and a redo', () {
    session.ops.setRotation([parent], math.pi / 2);
    expect(angle(parent), closeTo(math.pi / 2, 1e-9));
    settle();
    expectChildrenHome();
    expect(angle(child), 0, reason: 'an angle, not a turn of what is under');

    scope.history.undo();
    expect(angle(parent), 0);
    settle();
    expectChildrenHome();

    scope.history.redo();
    settle();
    expectChildrenHome();
  });

  test('a scrub of the angle field is one undo step, the children staying '
      'put throughout', () {
    for (final a in [0.1, 0.2, 0.3]) {
      session.ops.setRotation([parent], a, mergeKey: 'scrub');
    }
    expect(scope.history.undoEntries, hasLength(1));
    settle();
    expectChildrenHome();
    scope.history.undo();
    settle();
    expect(angle(parent), 0);
    expectChildrenHome();
  });

  test('a numeric resize leaves the children where they are', () {
    session.ops.resizeTo([parent], const Rect.fromLTWH(0, 0, 128, 64));
    expect([x(parent), y(parent)], [64, 32]);
    settle();
    expectChildrenHome();
    scope.history.undo();
    settle();
    expectChildrenHome();
  });

  test('a flip mirrors what is under the entity with it, and the hierarchy '
      'keeps it there', () {
    session.ops.flip([parent], horizontal: true);
    // Mirrored across the parent's middle, x = 32.
    expect(x(parent), 32);
    expect(x(child), closeTo(32 - 168, 1e-6));
    expect(x(grandchild), closeTo(32 - 228, 1e-6));
    settle();
    expect(x(child), closeTo(-136, 1e-6), reason: 'no jump at Play');
    expect(x(grandchild), closeTo(-196, 1e-6));
    expect(scope.history.undoEntries, hasLength(1), reason: 'one step');

    scope.history.undo();
    settle();
    expectChildrenHome();
    scope.history.redo();
    settle();
    expect(x(child), closeTo(-136, 1e-6));
    expect(x(grandchild), closeTo(-196, 1e-6));
  });

  test('the parent then moved with its children still takes them along '
      'by the same offset', () {
    session.ops.setRotation([parent], math.pi / 2);
    session.ops.nudge([parent], const Offset(10, 0));
    settle();
    expect(x(child), closeTo(210, 1e-6));
    expect(x(grandchild), closeTo(270, 1e-6));
  });
}
