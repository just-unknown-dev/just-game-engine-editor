// Hiding and locking: editor-only, and there whether or not the Level
// Designer is open.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);

  late EditorScope scope;
  late EntityOps ops;

  setUp(() {
    scope = testScope();
    ops = EntityOps(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
      camera: Camera.new,
    );
    scope.sceneState.openScene(Scene(name: 'level_test'), const {});
  });

  Entity node(String name, {Entity? under}) {
    final entity = scope.world.createEntityWithComponents([
      TransformComponent(),
      ChildrenComponent(),
    ], name: name);
    scope.sceneState.registerEntity(entity);
    if (under != null) ops.reparentEntity(entity, under);
    return entity;
  }

  test('the scope has one, before any designer opens', () {
    final a = node('A');

    scope.view.toggleHidden(a.id);

    expect(scope.view.isHidden(a.id), isTrue);
    expect(scope.view.isLocked(a.id), isFalse);
  });

  test('a designer reads the same one', () {
    final a = node('A');
    scope.view.toggleHidden(a.id);

    final session = LevelDesignerSession(
      scope: scope,
      uniqueName: ops.uniqueName.call,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (count, step) {},
    );
    addTearDown(session.dispose);

    // What was hidden before it opened is hidden inside it, and the
    // viewport's picker agrees.
    expect(session.controller.hiddenEntities.value, contains(a.id));
    expect(session.controller.isPickable(a), isFalse);

    // And closing it does not forget.
    session.dispose();
    expect(scope.view.isHidden(a.id), isTrue);
  });

  test('hiding changes nothing about the entity', () {
    final a = node('A');
    scope.sceneState.markClean();

    scope.view.setHidden([a.id], hidden: true);

    // Editor-only: the game would still have it, which is what keeps
    // "hide the clutter" from shipping a missing enemy.
    expect(a.isActive, isTrue);
    expect(scope.sceneState.isDirty.value, isFalse, reason: 'nothing to save');
  });

  test('isolating leaves one subtree, and its parents, showing', () {
    final root = node('Root');
    final card = node('Card', under: root);
    final label = node('Label', under: card);
    final other = node('Other');

    scope.view.isolate(scope.world, [card.id]);

    expect(scope.view.isHidden(card.id), isFalse);
    expect(scope.view.isHidden(label.id), isFalse, reason: 'what is inside');
    expect(scope.view.isHidden(root.id), isFalse, reason: 'what holds it');
    expect(scope.view.isHidden(other.id), isTrue);

    scope.view.isolate(scope.world, const []);
    expect(scope.view.hidden.value, isEmpty);
  });

  testWidgets('the tree offers the eye and the padlock with no designer', (
    tester,
  ) async {
    final a = node('A');
    tester.view.physicalSize = const Size(300, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SceneTreePanel(
            scope: scope,
            entities: ops,
            isHidden: (e) => scope.view.isHidden(e.id),
            isLocked: (e) => scope.view.isLocked(e.id),
            onToggleHidden: (e) => scope.view.toggleHidden(e.id),
            onToggleLocked: (e) => scope.view.toggleLocked(e.id),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(scope.view.isHidden(a.id), isTrue);
  });
}
