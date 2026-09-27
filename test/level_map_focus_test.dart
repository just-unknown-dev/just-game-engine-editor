// While the Level Designer is open only its Level Map, and what is under it,
// can be worked on: everything else in the scene is out of reach — not
// picked, selected or dragged — and not drawn in the viewport. The tree
// lists it faint, with its eye shut.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);

  group('what may be selected', () {
    late EditorSceneState state;
    late World world;
    late Entity a, b, c;

    setUp(() {
      state = EditorSceneState();
      addTearDown(state.dispose);
      world = World();
      a = world.createEntity(name: 'a');
      b = world.createEntity(name: 'b');
      c = world.createEntity(name: 'c');
    });

    bool notB(Entity e) => e.name != 'b';

    test('narrowing it lets go of what it refuses, keeping the rest', () {
      state
        ..selectEntity(b)
        ..toggleMultiSelect(a)
        ..toggleMultiSelect(c);

      state.setSelectable(notB);

      expect(state.multiSelectedIds.value, {a.id, c.id});
      expect(state.selectedEntity.value, c, reason: 'the primary stays');
    });

    test('a refused primary hands over to what is left, or to nothing', () {
      state
        ..selectEntity(a)
        ..toggleMultiSelect(b);
      state.setSelectable(notB);
      expect(state.selectedEntity.value, a);
      expect(state.multiSelectedIds.value, {a.id});

      state
        ..setSelectable(null)
        ..selectEntity(b)
        ..setSelectable(notB);
      expect(state.hasAnySelection, isFalse);
    });

    test('what it refuses cannot be selected any way at all', () {
      state
        ..setSelectable(notB)
        ..selectEntity(b);
      expect(state.selectedEntity.value, isNull);

      state
        ..selectEntity(a)
        ..toggleMultiSelect(b);
      expect(state.multiSelectedIds.value, {a.id});

      state.selectRange([a, b, c], anchor: b);
      expect(state.multiSelectedIds.value, {a.id, c.id});
      expect(state.selectedEntity.value, a);
    });

    test('with no test everything can be selected again', () {
      state
        ..setSelectable(notB)
        ..setSelectable(null)
        ..selectEntity(b);
      expect(state.selectedEntity.value, b);
      expect(state.canSelect(b), isTrue);
    });
  });

  group('the Level Map and what is under it', () {
    test('are in it; nothing else is', () {
      final world = World();
      Entity make(String name, {Entity? under, bool map = false}) {
        final e = world.createEntityWithComponents([
          TransformComponent(),
          if (map) LevelMapComponent(inline: LevelMapData()),
        ], name: name);
        if (under != null) {
          e.addComponent(ParentComponent(parentId: under.id));
        }
        return e;
      }

      final group = make('World');
      final map = make('Level Map', under: group, map: true);
      final crate = make('Crate', under: map);
      final lid = make('Lid', under: crate);
      final player = make('Player');

      expect(LevelMapFocus.contains(world, map), isTrue);
      expect(LevelMapFocus.contains(world, crate), isTrue);
      expect(LevelMapFocus.contains(world, lid), isTrue);
      expect(LevelMapFocus.contains(world, group), isFalse);
      expect(LevelMapFocus.contains(world, player), isFalse);
    });
  });

  group('the scene tree, with only the map in reach', () {
    late EditorScope scope;
    late EntityOps ops;
    late SceneTreeController controller;
    late Entity map, crate, player;

    Entity entity(String name, {Entity? under, bool isMap = false}) {
      final e = scope.world.createEntityWithComponents([
        TransformComponent(),
        if (isMap) LevelMapComponent(inline: LevelMapData()),
      ], name: name);
      scope.sceneState.registerEntity(e);
      if (under != null) {
        placeEntity(
          e,
          world: scope.world,
          sceneState: scope.sceneState,
          slot: HierarchySlot(parentId: under.id, index: -1),
        );
      }
      return e;
    }

    setUp(() {
      scope = testScope();
      ops = EntityOps(
        scope: scope,
        world: () => scope.world,
        sceneState: scope.sceneState,
        camera: Camera.new,
      );
      controller = SceneTreeController(world: () => scope.world);
      addTearDown(controller.dispose);
      scope.sceneState.openScene(Scene(name: 'level'), const {});
      player = entity('Player');
      map = entity(LevelMaps.primaryName, isMap: true);
      crate = entity('Crate', under: map);
      controller.expand(map.id);
      scope.sceneState.setSelectable(
        (e) => LevelMapFocus.contains(scope.world, e),
      );
    });

    Future<void> pumpTree(WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SceneTreePanel(
              scope: scope,
              entities: ops,
              controller: controller,
              isHidden: (e) => scope.view.isHidden(e.id),
              onToggleHidden: (e) => scope.view.toggleHidden(e.id),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    SceneTreeRowTile tileOf(WidgetTester tester, String name) =>
        tester.widget<SceneTreeRowTile>(
          find.ancestor(
            of: find.text(name),
            matching: find.byType(SceneTreeRowTile),
          ),
        );

    testWidgets('says why, and draws what is out of reach faint', (
      tester,
    ) async {
      await pumpTree(tester);

      expect(find.textContaining('only the Level Map'), findsOneWidget);
      expect(tileOf(tester, 'Player').isDisabled, isTrue);
      expect(tileOf(tester, LevelMaps.primaryName).isDisabled, isFalse);
      expect(tileOf(tester, 'Crate').isDisabled, isFalse);

      scope.sceneState.setSelectable(null);
      await tester.pump();
      expect(find.textContaining('only the Level Map'), findsNothing);
      expect(tileOf(tester, 'Player').isDisabled, isFalse);
    });

    testWidgets('its eye is shut, and says why', (tester) async {
      await pumpTree(tester);

      Finder eyeOf(String name) => find.descendant(
        of: find.ancestor(
          of: find.text(name),
          matching: find.byType(SceneTreeRowTile),
        ),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SceneTreeRowButton &&
              (w.icon == Icons.visibility_off_outlined ||
                  w.icon == Icons.visibility_outlined),
        ),
      );
      final playerEye = tester.widget<SceneTreeRowButton>(eyeOf('Player'));
      expect(playerEye.icon, Icons.visibility_off_outlined);
      expect(playerEye.tooltip, contains('Level Designer'));
      expect(
        tester.widget<SceneTreeRowButton>(eyeOf('Crate')).icon,
        Icons.visibility_outlined,
      );

      await tester.tap(eyeOf('Player'));
      await tester.pump();
      expect(
        scope.view.isHidden(player.id),
        isFalse,
        reason: 'the designer hid it; the eye has nothing to toggle',
      );
    });

    testWidgets('a click on what is out of reach does nothing', (tester) async {
      await pumpTree(tester);
      await tester.tap(find.text('Crate'));
      await tester.pump();
      expect(scope.sceneState.selectedEntity.value, crate);

      await tester.tap(find.text('Player'));
      await tester.pump(const Duration(seconds: 1));

      expect(scope.sceneState.selectedEntity.value, crate);
      expect(controller.renaming.value, isNull);
    });

    testWidgets('the arrow keys walk past it', (tester) async {
      await pumpTree(tester);
      await tester.tap(find.text('Crate'));
      await tester.pump();

      // Player is the first row, above the map: nothing to go up to.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(scope.sceneState.selectedEntity.value, map);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(scope.sceneState.selectedEntity.value, map);
      expect(player.isAlive, isTrue);
    });
  });

  group('with the Level Designer open', () {
    late JustGameEditorPlugin plugin;
    late World world;
    late Entity map, crate, player;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      Engine.resetInstance();
      final engine = Engine();
      await engine.initialize();
      plugin = JustGameEditorPlugin(engine: engine);
      await plugin.onInitialize();
      plugin
        ..setVisible(true)
        ..sceneState.openScene(Scene(name: 'level'), const {});
      world = plugin.engine.world;
      // The game's own; the editor's filters go on it as the designer opens.
      world.addSystem(RenderSystem());
      player = world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Player');
      map = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: LevelMapData()),
      ], name: LevelMaps.primaryName);
      crate = world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Crate');
      placeEntity(
        crate,
        world: world,
        sceneState: plugin.sceneState,
        slot: HierarchySlot(parentId: map.id, index: -1),
      );
    });

    tearDown(() {
      plugin.dispose();
      Engine.resetInstance();
    });

    bool drawn(Entity e) => world.getSystem<RenderSystem>()!.shouldRender!(e);

    test('only the map can be selected, picked or seen', () {
      plugin.sceneState
        ..selectEntity(player)
        ..toggleMultiSelect(crate);

      plugin.openLevelDesigner();
      final controller = plugin.designer.value!.controller;

      expect(plugin.sceneState.multiSelectedIds.value, {crate.id});
      expect(plugin.sceneState.canSelect(player), isFalse);
      expect(controller.isPickable(player), isFalse);
      expect(plugin.viewport.isPickable!(player), isFalse);
      expect(controller.isPickable(crate), isTrue);
      expect(controller.isPickable(map), isTrue);
      expect(drawn(player), isFalse);
      expect(
        controller.isShownInViewport(player),
        isFalse,
        reason: 'what overlays and the minimap ask',
      );
      expect(drawn(crate), isTrue);
      expect(drawn(map), isTrue);
    });

    test('closing it puts everything back in reach', () {
      plugin
        ..openLevelDesigner()
        ..closeLevelDesigner();

      expect(plugin.sceneState.canSelect(player), isTrue);
      expect(plugin.viewport.isPickable!(player), isTrue);
      expect(drawn(player), isTrue);
    });

    test('a play-test reaches everything, as does a workspace over it', () {
      plugin.openLevelDesigner();

      plugin.play();
      expect(plugin.sceneState.canSelect(player), isTrue);
      expect(drawn(player), isTrue);
      plugin.stop();
      expect(plugin.sceneState.canSelect(player), isFalse);

      // The interface editor works on the HUDs, which are not on the map.
      plugin.scope.openWorkspace(BuiltInWorkspaces.ui);
      expect(plugin.sceneState.canSelect(player), isTrue);
      plugin.scope.closeWorkspace();
      expect(plugin.sceneState.canSelect(player), isFalse);
    });
  });
}
