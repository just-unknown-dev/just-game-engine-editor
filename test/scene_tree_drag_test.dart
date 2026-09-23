// Dragging rows about: what a drop on a row means, and that a drag which
// moved several things undoes as one.

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

  List<EntityId> childrenOf(Entity entity) =>
      entity.getComponent<ChildrenComponent>()?.childIds ?? const [];

  group('what a drop on a row means', () {
    // A tree row is this tall.
    const height = kSceneTreeRowTileHeight;

    test('the body of a row means inside it', () {
      expect(dropZoneFor(height / 2, height), DropZone.onto);
      // Eight pixels down used to mean "between": the band was a share of
      // the row, which left most of a row meaning something other than
      // what it looks like it means.
      expect(dropZoneFor(8, height), DropZone.onto);
      expect(dropZoneFor(height - 8, height), DropZone.onto);
    });

    test('the very edges mean between', () {
      expect(dropZoneFor(0, height), DropZone.above);
      expect(dropZoneFor(3, height), DropZone.above);
      expect(dropZoneFor(height, height), DropZone.below);
      expect(dropZoneFor(height - 1, height), DropZone.below);
    });

    test('a row too short to have edges is mostly body', () {
      expect(dropZoneFor(6, 12), DropZone.onto);
      expect(dropZoneFor(1, 12), DropZone.above);
    });

    test('most of a row means inside it', () {
      var onto = 0;
      var steps = 0;
      for (var dy = 0.0; dy <= height; dy += 0.5) {
        if (dropZoneFor(dy, height) == DropZone.onto) onto++;
        steps++;
      }
      expect(onto / steps, greaterThan(0.6));
    });
  });

  group('where things land', () {
    test('dropping into a row puts them inside it, last', () {
      final into = node('Into');
      node('Already', under: into);
      final a = node('A');
      final b = node('B');

      ops.reparentAll([a, b], into);

      expect(childrenOf(into).length, 3);
      expect(childrenOf(into).last, b.id);
      expect(a.getComponent<ParentComponent>()!.parentId, into.id);
    });

    test('dropping between two rows lands at that place', () {
      final parent = node('Parent');
      final first = node('First', under: parent);
      final last = node('Last', under: parent);
      final moved = node('Moved');

      // What the panel works out for a drop on the top edge of "Last".
      ops.reparentAll([moved], parent, index: 1);

      expect(childrenOf(parent), [first.id, moved.id, last.id]);
    });

    test('a drag that moved several things undoes in one', () {
      final from = node('From');
      final to = node('To');
      final a = node('A', under: from);
      final b = node('B', under: from);
      final steps = scope.history.canUndo.value;

      ops.reparentAll([a, b], to);
      expect(childrenOf(to), [a.id, b.id]);

      scope.history.undo();

      expect(childrenOf(from), [a.id, b.id]);
      expect(childrenOf(to), isEmpty);
      // One step, not one per entity.
      expect(scope.history.canUndo.value, steps);
    });

    test('dropping on nothing moves things to the top level', () {
      final parent = node('Parent');
      final child = node('Child', under: parent);

      // What a drop past the last row does.
      ops.reparentAll([child], null);

      expect(child.getComponent<ParentComponent>()?.parentId, isNull);
      expect(childrenOf(parent), isEmpty);
      expect(scope.sceneState.rootOrder(scope.world), contains(child.id));
    });

    test('a row cannot be dropped into itself or its own child', () {
      final parent = node('Parent');
      final child = node('Child', under: parent);
      final steps = scope.history.canUndo.value;

      ops.reparentAll([parent], child);
      ops.reparentAll([parent], parent);

      expect(childrenOf(child), isEmpty);
      expect(childrenOf(parent), [child.id]);
      expect(scope.history.canUndo.value, steps, reason: 'nothing happened');
    });
  });

  group('on screen', () {
    testWidgets('a drag carries the whole selection, not just the row', (
      tester,
    ) async {
      final a = node('A');
      final b = node('B');
      node('C');
      scope.sceneState
        ..toggleMultiSelect(a)
        ..toggleMultiSelect(b);

      tester.view.physicalSize = const Size(300, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SceneTreePanel(scope: scope, entities: ops),
          ),
        ),
      );
      await tester.pump();

      // Held, then moved: that is a drag, and it says what is coming
      // with it.
      final held = await tester.startGesture(tester.getCenter(find.text('A')));
      await tester.pump(const Duration(milliseconds: 400));
      await held.moveBy(const Offset(0, 10));
      await tester.pump();

      expect(find.text('2 entities'), findsOneWidget);

      await held.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a click that moves a little is a click, not a drag', (
      tester,
    ) async {
      final a = node('A');
      node('B');
      tester.view.physicalSize = const Size(300, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SceneTreePanel(scope: scope, entities: ops),
          ),
        ),
      );
      await tester.pump();

      // A shaky hand on the way to a click. This used to start a drag —
      // the label flashed up at the pointer like a tooltip, and the
      // click itself was thrown away, so the row never got selected.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('A')),
      );
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.moveBy(const Offset(6, 3));
      await tester.pump();
      expect(find.text('A'), findsOneWidget, reason: 'no drag label');
      await gesture.up();
      await tester.pump();

      expect(scope.sceneState.selectedEntity.value?.id, a.id);
    });
  });

  group('a drag that is actually let go of', () {
    /// Picks [from] up and drops it on [to], at [dy] pixels down that row.
    Future<void> dragOnto(
      WidgetTester tester,
      String from,
      String to, {
      double dy = kSceneTreeRowTileHeight / 2,
    }) async {
      // The whole 22-pixel row, not the text sitting in the middle of it.
      final target = tester.getRect(
        find.ancestor(
          of: find.text(to),
          matching: find.byType(SceneTreeRowTile),
        ),
      );
      final held = await tester.startGesture(tester.getCenter(find.text(from)));
      await tester.pump(const Duration(milliseconds: 400));
      // Into the row, then to the exact height being aimed at.
      await held.moveTo(target.center);
      await tester.pump();
      await held.moveTo(Offset(target.center.dx, target.top + dy));
      await tester.pump();
      await held.up();
      await tester.pumpAndSettle();
    }

    Future<void> pumpTree(WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SceneTreePanel(scope: scope, entities: ops),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('dropping on the body of a row puts it inside', (tester) async {
      final box = node('Box');
      final moved = node('Moved');
      await pumpTree(tester);

      await dragOnto(tester, 'Moved', 'Box');

      // The middle of a row means "in here" — measured against the row,
      // which is 22 pixels tall, not against the whole list.
      expect(moved.getComponent<ParentComponent>()?.parentId, box.id);
      expect(childrenOf(box), [moved.id]);
    });

    testWidgets('dropping on the edge of a row puts it beside', (tester) async {
      final parent = node('Parent');
      final first = node('First', under: parent);
      node('Second', under: parent);
      final moved = node('Moved');
      await pumpTree(tester);
      // Selecting a row opens what it is inside, which is how the
      // children come to be rows of their own.
      scope.sceneState.selectEntity(first);
      await tester.pump();
      expect(find.text('Second'), findsOneWidget);

      await dragOnto(tester, 'Moved', 'Second', dy: 1);

      expect(moved.getComponent<ParentComponent>()?.parentId, parent.id);
      expect(childrenOf(parent).indexOf(moved.id), 1, reason: 'above Second');
    });
  });
}
