// Tiles selected with Select tiles, and what to do with them — make them an
// entity, copy, cut, delete, let go — offered where the author looks: a
// right-click on the level, and the inspector.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/level_map/tile_selection_ops.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/tools/tiles/tile_tool_base.dart';
import 'package:just_game_engine_editor/src/ui/overlay/viewport_menu.dart';
import 'package:just_game_engine_editor/src/ui/panels/entity_inspector_panel.dart';

void main() {
  /// A Level Map on [world] with two tiles on its Ground layer, both
  /// selected.
  ({Entity map, MapLayerData ground}) mapWithSelection(
    World world,
    EditorScope scope,
  ) {
    final data = LevelMapData(tileWidth: 32, tileHeight: 32);
    final ground = data.addLayer(name: 'Ground');
    ground.cells
      ..setCell(0, 0, TileCell.make(0, 1))
      ..setCell(1, 0, TileCell.make(0, 2));
    final map = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: data),
    ], name: LevelMaps.primaryName);
    scope.sceneState.registerEntity(map);
    scope.tiles
      ..selectMap(map)
      ..selection.value = {const TileCoord(0, 0), const TileCoord(1, 0)};
    return (map: map, ground: ground);
  }

  List<Entity> pieces(World world) => [
    for (final e in world.query([LevelMapComponent]))
      if (LevelMaps.isPiece(world, e)) e,
  ];

  test('with tiles selected, a right-click is the menu\'s, not a pick', () {
    final world = World()..initialize();
    final scope = testScope(world: world);
    final session = LevelDesignerSession(
      scope: scope,
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => const ModifierKeys(),
    );
    addTearDown(session.dispose);
    session.setTool(TileTools.select);
    expect(session.claimsSecondary(), isTrue, reason: 'nothing selected');
    mapWithSelection(world, scope);
    expect(session.claimsSecondary(), isFalse);
  });

  test('a selection begun on tiles of another layer — the one being painted '
      'empty there — is of the layer they are on', () {
    final world = World()..initialize();
    final scope = testScope(world: world);
    final session = LevelDesignerSession(
      scope: scope,
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => const ModifierKeys(),
    );
    addTearDown(session.dispose);
    final (:map, :ground) = mapWithSelection(world, scope);
    // Flowers in front, on a layer drawn half a tile lower: empty over the
    // ground, and the one painted, as the top layer is by default.
    final data = map.getComponent<LevelMapComponent>()!.inline!;
    final front = data.addLayer(name: 'Front')
      ..offsetY = 16
      ..cells.setCell(5, 5, TileCell.make(0, 9));
    scope.tiles
      ..selection.value = const {}
      ..layerId.value = front.id;
    session
      ..setTool(TileTools.select)
      ..onPointerDown(const Offset(16, 16), 32)
      ..onPointerMove(const Offset(48, 16), 32)
      ..onPointerUp(const Offset(48, 16), 32);
    expect(scope.tiles.layerId.value, ground.id);
    expect(scope.tiles.selection.value, {
      const TileCoord(0, 0),
      const TileCoord(1, 0),
    });
    expect(TileSelectionOps.tileCount(scope, world), 2);
    expect(session.controller.status.value, contains('Ground'));

    // On a tile of the layer being painted, it stays that layer's.
    scope.tiles
      ..selection.value = const {}
      ..layerId.value = front.id;
    session
      ..onPointerDown(const Offset(176, 192), 32)
      ..onPointerUp(const Offset(176, 192), 32);
    expect(scope.tiles.layerId.value, front.id);
  });

  group('the right-click menu', () {
    late JustGameEditorPlugin plugin;

    setUp(() async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      plugin = JustGameEditorPlugin(engine: engine, startVisible: false);
      plugin.sceneState.openScene(EditorScene(name: 'level'));
      addTearDown(plugin.dispose);
    });

    testWidgets('is about the selected tiles, and makes them an entity', (
      tester,
    ) async {
      final world = plugin.engine.world;
      plugin.openLevelDesigner();
      final (map: _, :ground) = mapWithSelection(world, plugin.scope);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showViewportMenu(
                  context,
                  plugin,
                  entity: null,
                  globalPosition: const Offset(200, 200),
                  worldPoint: const Offset(16, 16),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final item in [
        'Make the 2 tiles an entity',
        'Copy tiles',
        'Cut tiles',
        'Delete tiles',
        'Select none',
      ]) {
        expect(find.text(item), findsOneWidget, reason: item);
      }
      expect(find.text('New entity here'), findsNothing);

      await tester.tap(find.text('Make the 2 tiles an entity'));
      await tester.pumpAndSettle();
      expect(pieces(world), hasLength(1));
      expect(ground.cells.usedBounds, isNull);
    });
  });

  group('the inspector', () {
    late World world;
    late EditorScope scope;
    late MapLayerData ground;

    setUp(() {
      world = World()..initialize();
      scope = testScope(world: world);
      scope.sceneState.openScene(EditorScene(name: 'level'));
      (map: _, :ground) = mapWithSelection(world, scope);
    });

    Future<void> pumpInspector(
      WidgetTester tester, {
      bool isLevelDesignerOpen = true,
    }) async {
      tester.view
        ..physicalSize = const Size(320, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntityInspectorPanel(
              sceneState: scope.sceneState,
              world: world,
              scope: scope,
              onGroupSelection: () {},
              isLevelDesignerOpen: isLevelDesignerOpen,
            ),
          ),
        ),
      );
    }

    testWidgets('shows nothing of them with the Level Designer shut', (
      tester,
    ) async {
      await pumpInspector(tester, isLevelDesignerOpen: false);
      expect(find.text('2 tiles selected'), findsNothing);
      expect(find.text('Make them an entity'), findsNothing);
      expect(find.text('Nothing selected'), findsOneWidget);
    });

    testWidgets('says what is selected, and copies and deletes it', (
      tester,
    ) async {
      await pumpInspector(tester);
      expect(find.text('2 tiles selected'), findsOneWidget);
      expect(find.text('Level Map ▸ Ground'), findsOneWidget);

      await tester.tap(find.byTooltip('Copy tiles  (Ctrl+C)'));
      await tester.pump();
      expect(scope.tiles.clipboard?.cells, hasLength(2));

      await tester.tap(find.byTooltip('Delete tiles  (Delete)'));
      await tester.pump();
      expect(ground.cells.usedBounds, isNull);
      scope.history.undo();
      expect(ground.cells.cellAt(1, 0), TileCell.make(0, 2));

      await tester.tap(find.byTooltip('Select none  (Esc)'));
      await tester.pump();
      expect(find.text('2 tiles selected'), findsNothing);
    });

    testWidgets('cells with no tiles on the layer say so, and cannot be '
        'made an entity', (tester) async {
      scope.tiles.selection.value = {
        const TileCoord(7, 7),
        const TileCoord(8, 7),
      };
      await pumpInspector(tester);
      expect(find.text('2 empty cells selected'), findsOneWidget);
      expect(find.textContaining('Ground has no tiles there'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Make them an entity'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('makes them an entity', (tester) async {
      await pumpInspector(tester);
      await tester.tap(find.text('Make them an entity'));
      await tester.pump();
      expect(pieces(world), hasLength(1));
      expect(ground.cells.usedBounds, isNull);
      expect(
        find.text('2 tiles selected'),
        findsNothing,
        reason: 'what was selected is an entity now',
      );
    });
  });
}
