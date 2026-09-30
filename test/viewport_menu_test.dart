// Right-clicking the level: the menu offers what the tree's does, about
// the entity under the pointer, and acts where the pointer is.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  setUpAll(registerCoreCodecs);

  late Engine engine;
  late JustGameEditorPlugin plugin;

  setUp(() async {
    Engine.resetInstance();
    engine = Engine();
    await engine.initialize();
    plugin = JustGameEditorPlugin(engine: engine, startVisible: false);
    plugin.sceneState.openScene(Scene(name: 'level_test'));
    addTearDown(plugin.dispose);
  });

  Entity node(String name, {Offset at = Offset.zero}) {
    final entity = engine.world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromOffset(at)),
      ChildrenComponent(),
    ], name: name);
    plugin.sceneState.registerEntity(entity);
    return entity;
  }

  /// The menu, opened over [entity] (or over bare level when null).
  Future<void> openMenu(
    WidgetTester tester, {
    Entity? entity,
    Offset worldPoint = const Offset(120, 80),
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showViewportMenu(
                context,
                plugin,
                entity: entity,
                globalPosition: const Offset(200, 200),
                worldPoint: worldPoint,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('what the menu offers', () {
    testWidgets('on an entity: the things the tree offers about it', (
      tester,
    ) async {
      final platform = node('Platform');
      await openMenu(tester, entity: platform);

      expect(find.text('Focus'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      // The item, and the key beside it — the Delete key.
      expect(find.text('Delete'), findsNWidgets(2));
      // Each with the key that does the same.
      expect(find.text('Ctrl+D'), findsOneWidget);
      expect(find.text('Hide it'), findsOneWidget);
      expect(find.text('Lock it'), findsOneWidget);
      expect(find.text('Isolate: hide everything else'), findsOneWidget);
      // Making something is about the level, not about an entity.
      expect(find.text('New entity here'), findsNothing);
    });

    testWidgets('on bare level: what can be made there', (tester) async {
      await openMenu(tester);

      expect(find.text('New entity here'), findsOneWidget);
      expect(find.text('Paste here'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('right-clicking something selects it first', (tester) async {
      node('A');
      final b = node('B');
      plugin.sceneState.selectEntity(
        plugin.engine.world.findEntityByName('A')!,
      );

      await openMenu(tester, entity: b);

      // The menu is never about something other than what was clicked.
      expect(plugin.sceneState.selectedEntity.value?.id, b.id);
    });
  });

  group('what it does', () {
    testWidgets('a new entity lands where the pointer was', (tester) async {
      await openMenu(tester, worldPoint: const Offset(320, -140));
      await tester.tap(find.text('New entity here'));
      await tester.pumpAndSettle();

      final made = plugin.sceneState.selectedEntity.value!;
      final at = made.getComponent<TransformComponent>()!.position;
      expect(at.x, 320);
      expect(at.y, -140);
    });

    testWidgets('paste lands there too', (tester) async {
      final source = node('Source', at: const Offset(10, 10));
      plugin.entities.copyEntity(source);

      await openMenu(tester, worldPoint: const Offset(-40, 60));
      await tester.tap(find.text('Paste here'));
      await tester.pumpAndSettle();

      final pasted = plugin.sceneState.selectedEntity.value!;
      expect(pasted.id, isNot(source.id));
      final at = pasted.getComponent<TransformComponent>()!.position;
      expect(at.x, -40);
      expect(at.y, 60);
    });

    testWidgets('hiding from here is the same hiding the tree does', (
      tester,
    ) async {
      final platform = node('Platform');
      await openMenu(tester, entity: platform);
      await tester.tap(find.text('Hide it'));
      await tester.pumpAndSettle();

      expect(plugin.scope.view.isHidden(platform.id), isTrue);

      // And the menu then offers the way back.
      await openMenu(tester, entity: platform);
      expect(find.text('Show it'), findsOneWidget);
      expect(find.text('Show everything again'), findsOneWidget);
    });
  });

  group('the viewport itself', () {
    test('a right click does not select or start a drag', () {
      final platform = node('Platform');
      plugin.sceneState.selectEntity(platform);
      plugin.viewport.updateCanvasSize(const Size(800, 600));

      plugin.viewport.onPointerDown(
        const PointerDownEvent(
          position: Offset(400, 300),
          buttons: kSecondaryButton,
        ),
      );

      // Selection untouched — the left button does that — and nothing is
      // being dragged.
      expect(plugin.sceneState.selectedEntity.value?.id, platform.id);
      expect(plugin.viewport.isDragging, isFalse);
    });
  });
}
