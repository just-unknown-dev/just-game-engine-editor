// The side panel with a tile tool in hand: its sections follow the tools,
// the Tileset panel fills the brush, and the Layers panel — the map's layers
// and the entities, by depth — changes them, each change one undo step.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/level_designer_workspace.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/panels/level_layers_panel.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/panels/prefab_palette_panel.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/panels/tileset_palette_panel.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/tools/tiles/tile_tool_base.dart';

void main() {
  late World world;
  late EditorScope scope;
  late LevelDesignerSession session;
  late Entity map;
  late LevelMapData data;

  setUp(() {
    world = World()..initialize();
    world.context.tiles.putTileset(
      'assets/tilesets/test.tileset.json',
      TilesetData(
        name: 'Grass',
        image: '',
        imageWidth: 64,
        imageHeight: 32,
        tileWidth: 16,
        tileHeight: 16,
        columns: 4,
        tileCount: 8,
      )..tileOrNew(5).probability = 3,
    );
    registerLevelMapSystems(world);
    scope = testScope(world: world);
    session = LevelDesignerSession(
      scope: scope,
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: ModifierKeys.fromHardwareKeyboard,
    );
    addTearDown(session.dispose);
    data = BuiltInPrefabs.newLevelMap(tileSize: 16)
      ..addTileset('assets/tilesets/test.tileset.json');
    map = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: data),
    ], name: 'Level map');
    world.update(0);
    scope.tiles.selectMap(map);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(900, 1100)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorScopeProvider(
            scope: scope,
            child: LevelDesignerWorkspace(
              session: session,
              gridSize: 16,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
  }

  group('sections', () {
    testWidgets('follow the tools in hand, and remember a click', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(PrefabPalettePanel), findsOneWidget);
      expect(find.byType(TilesetPalettePanel), findsNothing);
      expect(find.text('TILESET'), findsOneWidget, reason: 'its title stays');

      session.setTool(TileTools.stamp);
      await tester.pump();
      expect(find.byType(PrefabPalettePanel), findsNothing);
      expect(find.byType(TilesetPalettePanel), findsOneWidget);
      expect(find.byType(LevelLayersPanel), findsOneWidget);

      // Opened by hand with a tile tool: open with tile tools from now on.
      await tester.tap(find.text('PREFABS'));
      await tester.pump();
      expect(find.byType(PrefabPalettePanel), findsOneWidget);
      session.setTool(BuiltInTools.select);
      await tester.pump();
      expect(find.byType(TilesetPalettePanel), findsNothing);
      session.setTool(TileTools.fill);
      await tester.pump();
      expect(find.byType(PrefabPalettePanel), findsOneWidget);
      expect(find.byType(TilesetPalettePanel), findsOneWidget);
    });
  });

  group('tileset', () {
    /// Every tileset's grid: the basic shapes first, then the map's.
    Finder grids() => find.descendant(
      of: find.byType(TilesetPalettePanel),
      matching: find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_TilesetPainter',
      ),
    );

    /// The map's own tileset, Grass.
    Finder grid() => grids().last;

    Offset tile(WidgetTester tester, int col, int row) =>
        tester.getTopLeft(grid()) + Offset(col * 16 + 8, row * 16 + 8);

    testWidgets('lists the basic shapes, then the map\'s tilesets, one '
        'under another; each folds away', (tester) async {
      session.setTool(TileTools.stamp);
      await pump(tester);
      expect(find.text('Basic shapes'), findsOneWidget);
      expect(find.text('built in · not on the map'), findsOneWidget);
      expect(find.text('Grass'), findsOneWidget);
      expect(grids(), findsNWidgets(2));
      expect(
        tester.getTopLeft(find.text('Basic shapes')).dy,
        lessThan(tester.getTopLeft(find.text('Grass')).dy),
      );

      await tester.tap(find.text('Basic shapes'));
      await tester.pump();
      expect(grids(), findsOneWidget, reason: 'folded away');
      expect(scope.tiles.collapsedTilesets.value, {
        BuiltInTilesets.basicShapes,
      });
    });

    testWidgets('a basic shape picked joins its tileset to the map, one '
        'undo step', (tester) async {
      session.setTool(TileTools.stamp);
      await pump(tester);
      await tester.tapAt(tester.getTopLeft(grids().first) + const Offset(8, 8));
      await tester.pump();
      final slot = data.slotOf(BuiltInTilesets.basicShapes);
      expect(slot, 1);
      expect(scope.tiles.stamp.value!.cells.single.cell, TileCell.make(1, 0));
      expect(find.text('built in'), findsOneWidget);

      scope.history.undo();
      expect(data.tilesets, ['assets/tilesets/test.tileset.json']);
    });

    testWidgets('in a scene with no map, a basic shape picked makes the '
        'Level Map, with it', (tester) async {
      world.destroyEntity(map);
      scope.tiles.reset();
      session.setTool(TileTools.stamp);
      await pump(tester);
      expect(grids(), findsOneWidget, reason: 'the basic shapes alone');
      await tester.tapAt(tester.getTopLeft(grids().first) + const Offset(8, 8));
      await tester.pump();
      final made = LevelMaps.primaryEntity(world)!;
      expect(made.getComponent<LevelMapComponent>()!.inline!.tilesets, [
        BuiltInTilesets.basicShapes,
      ]);
      scope.history.undo();
      expect(world.query([LevelMapComponent]), isEmpty, reason: 'one step');
    });

    testWidgets('a click puts one tile in the brush', (tester) async {
      session.setTool(TileTools.stamp);
      await pump(tester);
      await tester.tapAt(tile(tester, 2, 1));
      await tester.pump();
      expect(scope.tiles.stamp.value!.cells.single.cell, TileCell.make(0, 6));
    });

    testWidgets('a drag makes a block, laid out as in the tileset', (
      tester,
    ) async {
      session.setTool(TileTools.stamp);
      await pump(tester);
      final gesture = await tester.startGesture(tile(tester, 0, 0));
      await gesture.moveTo(tile(tester, 1, 1));
      await gesture.up();
      await tester.pump();
      final stamp = scope.tiles.stamp.value!;
      expect(stamp.cells, hasLength(4));

      // Painted, it is the same 2 × 2 block.
      final layer = data.layers.single;
      final target = scope.tiles.target(world)!;
      for (final (cell, value) in stamp.placeAt(
        const TileCoord(5, 5),
        target.geometry,
      )) {
        layer.cells.setCell(cell.x, cell.y, value);
      }
      final painted = {
        for (final (x, y, v) in layer.cells.cells) TileCoord(x, y): v,
      };
      final x0 = painted.keys.map((c) => c.x).reduce((a, b) => a < b ? a : b);
      final y0 = painted.keys.map((c) => c.y).reduce((a, b) => a < b ? a : b);
      expect(painted[TileCoord(x0, y0)], TileCell.make(0, 0));
      expect(painted[TileCoord(x0 + 1, y0)], TileCell.make(0, 1));
      expect(painted[TileCoord(x0, y0 + 1)], TileCell.make(0, 4));
      expect(painted[TileCoord(x0 + 1, y0 + 1)], TileCell.make(0, 5));
    });

    testWidgets('Ctrl+click gathers tiles to pick between', (tester) async {
      session.setTool(TileTools.stamp);
      await pump(tester);
      await tester.tapAt(tile(tester, 0, 0));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tapAt(tile(tester, 1, 1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      final stamp = scope.tiles.stamp.value!;
      expect(stamp.isRandom, isTrue);
      expect(stamp.choices, [TileCell.make(0, 0), TileCell.make(0, 5)]);
      expect(stamp.weights, [1, 3], reason: 'each tile\'s probability');
    });

    testWidgets('picking a tile with the eraser in hand goes to the stamp', (
      tester,
    ) async {
      session.setTool(TileTools.erase);
      await pump(tester);
      await tester.tapAt(tile(tester, 3, 0));
      await tester.pump();
      expect(session.controller.toolId.value, TileTools.stamp);
    });

    testWidgets('a tileset still painted cannot be taken off the map', (
      tester,
    ) async {
      session.setTool(TileTools.stamp);
      data.layers.single.cells.setCell(0, 0, TileCell.make(0, 1));
      await pump(tester);
      await tester.tap(find.byTooltip('More').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Remove from the map'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(data.tilesets, ['assets/tilesets/test.tileset.json']);
      expect(session.controller.status.value, contains('still painted'));
    });
  });

  group('tile layers', () {
    Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
    }

    testWidgets('adds, reorders and deletes layers, each one undo step', (
      tester,
    ) async {
      session.setTool(TileTools.stamp);
      await pump(tester);
      expect(find.text('Ground'), findsWidgets);

      await tapTooltip(tester, 'Add a map layer at Main');
      expect(data.layers.map((l) => l.name), ['Ground', 'Main']);
      expect(scope.tiles.layerId.value, data.layers.last.id, reason: 'painted');

      await tapTooltip(tester, 'Lower: draw behind the map layer below');
      expect(data.layers.map((l) => l.name), ['Main', 'Ground']);

      await tapTooltip(tester, 'Delete the map layer, and what is on it');
      expect(data.layers.map((l) => l.name), ['Ground']);

      scope.history.undo();
      scope.history.undo();
      await tester.pump();
      expect(data.layers.map((l) => l.name), ['Ground', 'Main']);
      scope.history.undo();
      expect(data.layers.map((l) => l.name), ['Ground']);
    });

    testWidgets('a layer deleted or duplicated takes what is on it along, '
        'in one step; the selection moves onto a layer', (tester) async {
      session.setTool(TileTools.stamp);
      final ground = data.layers.single;
      final rock = world.createEntityWithComponents([
        TransformComponent(),
        LayerComponent(mapLayer: ground.id),
      ], name: 'Rock');
      scope.sceneState
        ..registerEntity(map)
        ..registerEntity(rock);
      placeEntity(
        rock,
        world: world,
        sceneState: scope.sceneState,
        slot: HierarchySlot(parentId: map.id, index: -1),
      );
      List<Entity> on(MapLayerData layer) => [
        for (final e in world.query([LayerComponent]))
          if (LevelMaps.memberLayer(world, e) == layer) e,
      ];
      await pump(tester);

      await tapTooltip(
        tester,
        'Duplicate the map layer: its tiles, and what is on it',
      );
      final copy = data.layers.last;
      expect(on(copy).single.name, startsWith('Rock'));
      expect(on(copy).single, isNot(same(rock)));
      scope.history.undo();
      await tester.pump();
      expect(data.layers, [ground]);
      expect(world.query([LayerComponent]), hasLength(1));

      await tapTooltip(tester, 'Delete the map layer, and what is on it');
      expect(data.layers, isEmpty);
      expect(world.findEntityByName('Rock'), isNull);
      scope.history.undo();
      await tester.pump();
      expect(on(data.layers.single).single.name, 'Rock');

      final crate = world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Crate');
      scope.sceneState
        ..registerEntity(crate)
        ..selectEntity(crate);
      await tester.pump();
      await tapTooltip(tester, 'Move the selection onto this map layer');
      expect(LevelMaps.memberLayer(world, crate), same(data.layers.single));
    });

    testWidgets('duplicates a layer with its tiles', (tester) async {
      session.setTool(TileTools.stamp);
      data.layers.single.cells.setCell(2, 3, TileCell.make(0, 4));
      await pump(tester);
      await tapTooltip(
        tester,
        'Duplicate the map layer: its tiles, and what is on it',
      );
      expect(data.layers, hasLength(2));
      final copy = data.layers.last;
      expect(copy.name, 'Ground copy');
      expect(copy.cells.cellAt(2, 3), TileCell.make(0, 4));
      expect(copy.id, isNot(data.layers.first.id));

      // The copy's cells are its own.
      copy.cells.setCell(2, 3, TileCell.empty);
      expect(data.layers.first.cells.cellAt(2, 3), TileCell.make(0, 4));
    });

    testWidgets('eye, lock and collides are saved on the layer', (
      tester,
    ) async {
      session.setTool(TileTools.stamp);
      await pump(tester);
      final ground = data.layers.single;
      expect(ground.collides, isTrue);

      await tapTooltip(tester, 'Hide map layer');
      expect(ground.visible, isFalse);
      await tapTooltip(tester, 'Lock map layer: keep the tools off it');
      expect(ground.locked, isTrue);
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is Tooltip &&
              (w.message ?? '').startsWith('Tiles on this layer collide'),
        ),
      );
      await tester.pump();
      expect(ground.collides, isFalse);
      expect(scope.sceneState.isDirty.value, isTrue);

      scope.history.undo();
      expect(ground.collides, isTrue);
    });

    testWidgets('renames a layer in its settings', (tester) async {
      session.setTool(TileTools.stamp);
      await pump(tester);
      await tapTooltip(tester, 'Layer settings');
      final name = find.descendant(
        of: find.byType(TextEditorRow),
        matching: find.byType(TextField),
      );
      await tester.enterText(name.first, 'Floor');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(data.layers.single.name, 'Floor');
      scope.history.undo();
      expect(data.layers.single.name, 'Ground');
    });

    testWidgets('Create Level Map places one and paints it', (tester) async {
      world.destroyEntity(map);
      scope.tiles.reset();
      session.setTool(TileTools.stamp);
      await pump(tester);
      expect(find.textContaining('No Level Map yet'), findsWidgets);

      await tester.tap(find.text('Create Level Map').first);
      await tester.pump();
      final maps = world.query([LevelMapComponent]).toList();
      expect(maps, hasLength(1));
      expect(scope.tiles.mapEntityId.value, maps.single.id);
      scope.history.undo();
      expect(world.query([LevelMapComponent]), isEmpty);
    });
  });

  group('layers, by depth', () {
    Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
    }

    double topOf(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text).first).dy;

    testWidgets('each depth lists its map layers and its entities, front '
        'first, and is open whatever the tool', (tester) async {
      world.createEntityWithComponents([
        TransformComponent(),
        LayerComponent(layerId: 'background'),
      ], name: 'Hill');
      session.setTool(BuiltInTools.select);
      await pump(tester);
      expect(find.byType(LevelLayersPanel), findsOneWidget);
      expect(topOf(tester, 'FOREGROUND'), lessThan(topOf(tester, 'MAIN')));
      expect(topOf(tester, 'MAIN'), lessThan(topOf(tester, 'BACKGROUND')));
      expect(topOf(tester, 'Ground'), greaterThan(topOf(tester, 'MAIN')));
      expect(topOf(tester, 'Ground'), lessThan(topOf(tester, 'BACKGROUND')));
      expect(find.text('1 entity'), findsOneWidget);

      // A layer added at a depth draws there, and is the one painted.
      await tapTooltip(tester, 'Add a map layer at Background');
      final back = data.layers.firstWhere((l) => l.name == 'Background');
      expect(back.sortLayerId, 'background');
      expect(scope.tiles.layerId.value, back.id);
      expect(session.controller.activeLayerId.value, 'background');
      expect(
        topOf(tester, 'Background'),
        greaterThan(topOf(tester, 'BACKGROUND')),
      );
      scope.history.undo();
      expect(data.layers.map((l) => l.name), ['Ground']);
    });

    testWidgets('a depth\'s eye hides its entities in the viewport only, '
        'never in the game', (tester) async {
      final hill = world.createEntityWithComponents([
        TransformComponent(),
        RectangleComponent(width: 10, height: 10),
        LayerComponent(layerId: 'background'),
      ], name: 'Hill');
      await pump(tester);
      const hide = 'Hide the entities at this depth (editor only)';
      final count = find.byTooltip(hide).evaluate().length;
      for (var i = 0; i < count; i++) {
        await tester.tap(find.byTooltip(hide).first);
        await tester.pump();
      }
      expect(session.controller.isLayerHidden('background'), isTrue);
      expect(session.controller.isShownInViewport(hill), isFalse);
      // A play-test, or the designer closed, still shows it.
      expect(hill.getComponent<LayerComponent>()!.visible, isTrue);
      expect(
        hill.components
            .whereType<RectangleComponent>()
            .single
            .renderable
            .visible,
        isTrue,
      );
    });

    testWidgets('a layer added at a depth but Main, in a scene with no map, '
        'is decoration', (tester) async {
      world.destroyEntity(map);
      scope.tiles.reset();
      await pump(tester);
      await tapTooltip(tester, 'Add a map layer at Background');
      final layer = world
          .query([LevelMapComponent])
          .single
          .getComponent<LevelMapComponent>()!
          .inline!
          .layers
          .single;
      expect(layer.sortLayerId, 'background');
      expect(layer.collides, isFalse);
    });

    testWidgets('the map settings open from the gear, each change one undo '
        'step', (tester) async {
      session.setTool(TileTools.stamp);
      await pump(tester);
      await tapTooltip(tester, 'Map settings: grid and tile size');
      expect(find.text('Tile W'), findsOneWidget);
      final field = find.descendant(
        of: find.widgetWithText(ScrubFieldRow, 'Tile W'),
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, '24');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(data.tileWidth, 24);
      scope.history.undo();
      expect(data.tileWidth, 16);
    });

    testWidgets('moving the selection to a depth is one undo step', (
      tester,
    ) async {
      final crate = world.createEntityWithComponents([
        TransformComponent(),
        LayerComponent(layerId: 'main'),
      ], name: 'Crate');
      scope.sceneState.registerEntity(crate);
      scope.sceneState.selectEntity(crate);
      await pump(tester);
      final moves = find.byTooltip('Move the selection to this depth');
      // Front first: Foreground's row is the first.
      await tester.tap(moves.first);
      await tester.pump();
      LayerComponent layerOf() =>
          world.getEntity(crate.id)!.getComponent<LayerComponent>()!;
      expect(layerOf().layerId, 'foreground');
      scope.history.undo();
      expect(layerOf().layerId, 'main');
    });

    testWidgets('with no map yet, adding a layer makes the Level Map', (
      tester,
    ) async {
      world.destroyEntity(map);
      scope.tiles.reset();
      await pump(tester);
      expect(find.text('No Level Map'), findsOneWidget);
      await tapTooltip(tester, 'Add a map layer at Foreground');
      final made = world.query([LevelMapComponent]).single;
      expect(made.name, LevelMaps.primaryName);
      final layer = made
          .getComponent<LevelMapComponent>()!
          .inline!
          .layers
          .single;
      expect(layer.sortLayerId, 'foreground');
      expect(layer.name, 'Foreground');
      scope.history.undo();
      expect(world.query([LevelMapComponent]), isEmpty);
    });
  });
}
