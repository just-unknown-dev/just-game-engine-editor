// One undo stack for the whole editor: the scope owns it, and what was
// done while a panel was open survives that panel closing.

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

  Entity platform(String name, {double x = 0}) =>
      scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(x, 0, 0)),
        RectangleComponent(width: 32, height: 32),
      ], name: name);

  group('the scope owns it', () {
    test('there is one, and it is there before any panel opens', () {
      expect(scope.history, isNotNull);
      expect(scope.history.canUndo.value, isFalse);
      // The same one every time it is asked for.
      expect(identical(scope.history, scope.history), isTrue);
    });

    test('deleting is undoable with no designer open', () {
      final entity = platform('Platform_0');
      scope.sceneState.selectEntity(entity);

      ops.deleteSelection(scope.history);

      expect(scope.world.findEntityByName('Platform_0'), isNull);
      expect(scope.history.canUndo.value, isTrue);

      scope.history.undo();

      expect(scope.world.findEntityByName('Platform_0'), isNotNull);
    });

    test('a session takes the scope\'s stack rather than making one', () {
      final entity = platform('Platform_0');
      scope.sceneState.selectEntity(entity);
      ops.deleteSelection(scope.history);

      final session = LevelDesignerSession(
        scope: scope,
        uniqueName: ops.uniqueName.call,
        onDuplicate: () {},
        onDelete: () {},
        onArray: (count, step) {},
      );
      addTearDown(session.dispose);

      // What was done before it opened is still undoable inside it.
      expect(identical(session.history, scope.history), isTrue);
      expect(session.history.canUndo.value, isTrue);
      expect(session.history.nextUndoLabel.value, contains('Platform_0'));
    });

    test('closing a session keeps the stack', () {
      final session = LevelDesignerSession(
        scope: scope,
        uniqueName: ops.uniqueName.call,
        onDuplicate: () {},
        onDelete: () {},
        onArray: (count, step) {},
      );
      final entity = platform('Platform_0');
      scope.sceneState.selectEntity(entity);
      ops.deleteSelection(session.history);

      session.dispose();

      // The session is gone; the edit it made is still undoable.
      expect(scope.history.canUndo.value, isTrue);
      scope.history.undo();
      expect(scope.world.findEntityByName('Platform_0'), isNotNull);
    });
  });

  group('the inspector', () {
    /// The inspector over [entity], at inspector width.
    Future<void> pumpInspector(WidgetTester tester, Entity entity) async {
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: buildComponentSections(
                  entity: entity,
                  sceneState: scope.sceneState,
                  scope: scope,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('removing a component is undoable', (tester) async {
      final entity = platform('Platform_0');
      final before = entity.components.length;
      await pumpInspector(tester, entity);
      final remove = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').startsWith('Remove '),
      );
      expect(remove, findsWidgets);

      await tester.tap(remove.first);
      await tester.pump();
      expect(entity.components.length, before - 1);
      expect(scope.history.canUndo.value, isTrue);

      scope.history.undo();
      expect(entity.components.length, before, reason: 'back, as it was');
    });

    testWidgets('a field edit is undoable', (tester) async {
      final entity = platform('Platform_0');
      // Every renderable is keyed under RenderableComponent — one drawn
      // thing per entity is this engine's rule.
      final rect =
          entity.getComponent<RenderableComponent>()! as RectangleComponent;
      await pumpInspector(tester, entity);

      // Width and height share one "Size" row, W then H.
      final width = find
          .descendant(
            of: find.ancestor(
              of: find.text('Size'),
              matching: find.byType(AxesFieldRow),
            ),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(width, '96');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(rect.width, 96);
      expect(scope.history.canUndo.value, isTrue);

      scope.history.undo();

      expect(rect.width, 32);
    });

    testWidgets('a run of edits to one field is one undo step', (tester) async {
      final entity = platform('Platform_0');
      // Every renderable is keyed under RenderableComponent — one drawn
      // thing per entity is this engine's rule.
      final rect =
          entity.getComponent<RenderableComponent>()! as RectangleComponent;
      await pumpInspector(tester, entity);

      // Width and height share one "Size" row, W then H.
      final width = find
          .descendant(
            of: find.ancestor(
              of: find.text('Size'),
              matching: find.byType(AxesFieldRow),
            ),
            matching: find.byType(TextField),
          )
          .first;
      for (final value in ['40', '50', '60']) {
        await tester.enterText(width, value);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
      }
      expect(rect.width, 60);

      // A scrub emits a value per pixel of drag; one undo puts it back to
      // where the drag began, not to the pixel before.
      scope.history.undo();

      expect(rect.width, 32);
      expect(scope.history.canUndo.value, isFalse);
    });
  });
}
