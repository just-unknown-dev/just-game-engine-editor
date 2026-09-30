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
      camera: () => GameCameraEditorView.of(Camera()),
    );
    scope.sceneState.openScene(Scene(name: 'level_test'));
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

  testWidgets('hiding, and pinning the inspector, with no designer', (
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

    // The padlock pins the inspector to the row — Unity's inspector
    // lock. Locking against picking lives in the row's menu now.
    await tester.tap(find.byIcon(Icons.push_pin_outlined));
    await tester.pump();
    expect(scope.view.isPinned(a.id), isTrue);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(scope.view.isHidden(a.id), isTrue);
  });

  testWidgets('a switched-off entity cannot be edited from the inspector', (
    tester,
  ) async {
    final a = node('A');
    scope.sceneState.selectEntity(a);
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntityInspectorPanel(
            scope: scope,
            sceneState: scope.sceneState,
            world: scope.world,
            onDetachFromParent: (_) {},
            onGroupSelection: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Switched off'), findsNothing);

    a.isActive = false;
    scope.sceneState.refresh();
    await tester.pump();

    // Said in words, and meant: the sections below are behind an
    // IgnorePointer, so nothing can be changed on an entity that is not
    // running.
    expect(find.textContaining('Switched off in the game'), findsOneWidget);
    final ignoring = tester.widgetList<IgnorePointer>(
      find.byType(IgnorePointer),
    );
    expect(ignoring.any((w) => w.ignoring), isTrue);
  });

  testWidgets('a pinned inspector stays on its entity', (tester) async {
    final a = node('A');
    final b = node('B');
    a.addComponent(TagComponent('pinned_one'));
    scope.sceneState.selectEntity(a);
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntityInspectorPanel(
            scope: scope,
            sceneState: scope.sceneState,
            world: scope.world,
            onDetachFromParent: (_) {},
            onGroupSelection: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('pinned_one'), findsOneWidget);

    scope.view.togglePinned(a.id);
    scope.sceneState.selectEntity(b);
    await tester.pump();

    // Selection moved; what is shown did not. That is the whole point of
    // the pin — reading one thing while picking another.
    expect(scope.sceneState.selectedEntity.value?.id, b.id);
    expect(find.text('pinned_one'), findsOneWidget);

    // And the panel says why it is not following the selection, with
    // the way out beside it.
    expect(find.textContaining('Pinned to A'), findsOneWidget);
    await tester.tap(find.text('Unpin'));
    await tester.pump();
    expect(scope.view.pinned.value, isNull);
    expect(find.text('pinned_one'), findsNothing);
  });

  test('only one thing is pinned at a time', () {
    final a = node('A');
    final b = node('B');

    scope.view.togglePinned(a.id);
    scope.view.togglePinned(b.id);

    expect(scope.view.isPinned(a.id), isFalse, reason: 'the pin moved');
    expect(scope.view.isPinned(b.id), isTrue);

    scope.view.togglePinned(b.id);
    expect(scope.view.pinned.value, isNull, reason: 'and releases');
  });

  testWidgets('a locked entity says so in the inspector too', (tester) async {
    final a = node('A');
    scope.sceneState.selectEntity(a);
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntityInspectorPanel(
            scope: scope,
            sceneState: scope.sceneState,
            world: scope.world,
            onDetachFromParent: (_) {},
            onGroupSelection: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Locked against picking'), findsNothing);

    scope.view.toggleLocked(a.id);
    await tester.pump();

    // Said, and undone from where it is said — the row's menu is the
    // other way, which is a long way from the panel you are reading.
    expect(find.textContaining('Locked against picking'), findsOneWidget);
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    expect(scope.view.isLocked(a.id), isFalse);
  });
}
