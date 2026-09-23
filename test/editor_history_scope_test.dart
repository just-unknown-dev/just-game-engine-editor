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
      camera: Camera.new,
    );
    scope.sceneState.openScene(Scene(name: 'level_test'), const {});
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

  group('the UI mode and the designer share it', () {
    test('a UI drag and a world edit undo off one stack, newest first', () {
      final canvas = ops.createUi('canvas')!;
      final text = ops.createUi('text', parent: canvas)!;
      final slot = text.getComponent<UiSlotComponent>()!;
      final world = platform('Platform_0');

      // What the UI mode pushes for a drag.
      scope.history.push(
        ComponentFieldCommand(
          label: 'Move ${text.name}',
          component: slot,
          before: slot.offset,
          after: const Offset(40, 0),
          write: (c, v) => (c as UiSlotComponent).offset = v as Offset,
          sceneState: scope.sceneState,
        ),
      );
      // Then something in the world.
      scope.sceneState.selectEntity(world);
      ops.deleteSelection(scope.history);

      expect(slot.offset, const Offset(40, 0));
      expect(scope.world.findEntityByName('Platform_0'), isNull);

      scope.history.undo();
      expect(
        scope.world.findEntityByName('Platform_0'),
        isNotNull,
        reason: 'the newest edit first',
      );
      expect(slot.offset, const Offset(40, 0));

      scope.history.undo();
      expect(slot.offset, Offset.zero);
    });
  });
}
