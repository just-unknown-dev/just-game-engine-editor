// Raise and Lower in the map's layers panel move a map layer in what is
// drawn — past the next layer in front of or behind it at its depth — and
// are only offered when there is one: never a step that changes nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import '../support/test_scope.dart';
import 'package:just_game_engine_editor/src/level_designer/level_designer_panel.dart';
import 'package:just_game_engine_editor/src/level_designer/level_designer_2d/tools/tiles/tile_tool_base.dart';
import 'package:just_game_engine_editor/src/level_designer/panels/level_layers_panel.dart';
import 'package:just_game_engine_editor/src/level_map/scope_level_maps.dart';

const _raise = 'Raise: draw in front of the map layer above';
const _lower = 'Lower: draw behind the map layer below';

List<String> _names(Iterable<MapLayerData> layers) => [
  for (final l in layers) l.name,
];

MapLayerData _layer(LevelMapData map, String name, {int z = 0}) =>
    map.addLayer(name: name)
      ..sortLayerId = 'main'
      ..zOrder = z;

void main() {
  group('drawnBeside and swapDrawOrder', () {
    test('neighbours by what is drawn at the depth, not by the list', () {
      final map = LevelMapData(tileWidth: 16, tileHeight: 16);
      final a = _layer(map, 'A', z: 1);
      final b = _layer(map, 'B');
      final back = map.addLayer(name: 'Back')
        ..sortLayerId = 'background'
        ..sortLayer = -10;
      // Drawn B, A at Main: A in front though listed first.
      expect(_names(TileTool.drawOrder(map.layers)), ['Back', 'B', 'A']);
      expect(LevelLayersPanel.drawnBeside(map.layers, b, 1), a);
      expect(
        LevelLayersPanel.drawnBeside(map.layers, b, -1),
        isNull,
        reason: 'not past its depth into another',
      );
      expect(LevelLayersPanel.drawnBeside(map.layers, a, 1), isNull);
      expect(LevelLayersPanel.drawnBeside(map.layers, back, 1), isNull);

      LevelLayersPanel.swapDrawOrder(map.layers, b, a);
      expect(_names(TileTool.drawOrder(map.layers)), ['Back', 'A', 'B']);
    });

    test('a swap moves the two past each other and nothing else', () {
      final map = LevelMapData(tileWidth: 16, tileHeight: 16);
      final c = _layer(map, 'C');
      final a = _layer(map, 'A');
      final d = _layer(map, 'D', z: 1);
      final b = _layer(map, 'B', z: 1);
      expect(_names(TileTool.drawOrder(map.layers)), ['C', 'A', 'D', 'B']);
      LevelLayersPanel.swapDrawOrder(map.layers, a, d);
      expect(_names(TileTool.drawOrder(map.layers)), ['C', 'D', 'A', 'B']);
      LevelLayersPanel.swapDrawOrder(map.layers, a, b);
      expect(_names(TileTool.drawOrder(map.layers)), ['C', 'D', 'B', 'A']);
      expect([c, d].every((l) => l.zOrder == 0), isTrue);
    });
  });

  group('the arrows', () {
    late World world;
    late EditorScope scope;
    late LevelDesignerSession session;
    late LevelMapData data;

    setUp(() {
      world = World()..initialize();
      registerLevelMapSystems(world);
      scope = testScope(world: world);
      session = LevelDesignerSession(
        scope: scope,
        uniqueName: (p) => p,
        onDuplicate: () {},
        onDelete: () {},
        onArray: (_, _) {},
        readModifiers: () => const ModifierKeys(),
      );
      addTearDown(session.dispose);
      data = BuiltInPrefabs.newLevelMap(tileSize: 16);
      final map = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: data),
      ], name: 'Level map');
      world.update(0);
      scope.tiles.selectMap(map);
      session.setTool(TileTools.stamp);
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
              child: LevelDesignerPanel(
                session: session,
                gridSize: 16,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
    }

    bool enabled(WidgetTester tester, String tooltip) {
      final button = find.descendant(
        of: find.byTooltip(tooltip),
        matching: find.byType(InkWell),
      );
      return tester.widget<InkWell>(button.first).onTap != null;
    }

    testWidgets('a layer alone at its depth has nothing to pass: neither '
        'arrow, and no undo step', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Add a map layer at Background'));
      await tester.pump();
      expect(_names(data.layers), ['Ground', 'Background']);
      final steps = scope.history.undoEntries.length;
      expect(enabled(tester, _raise), isFalse);
      expect(enabled(tester, _lower), isFalse);
      await tester.tap(find.byTooltip(_lower));
      await tester.pump();
      expect(_names(data.layers), ['Ground', 'Background']);
      expect(scope.history.undoEntries, hasLength(steps));
    });

    testWidgets('at one depth, Raise passes the layer drawn in front of it, '
        'whatever the list says; one undo step', (tester) async {
      final front = data.addLayer(name: 'Front')
        ..sortLayerId = data.layers.first.sortLayerId
        ..sortLayer = data.layers.first.sortLayer;
      data.layers.first.zOrder = 1; // Ground in front, though listed first.
      scope.tiles.selectLayer(front, controller: session.controller);
      await pump(tester);
      expect(_names(TileTool.drawOrder(data.layers)), ['Front', 'Ground']);
      expect(enabled(tester, _raise), isTrue);
      expect(enabled(tester, _lower), isFalse);
      await tester.tap(find.byTooltip(_raise));
      await tester.pump();
      expect(_names(TileTool.drawOrder(data.layers)), ['Ground', 'Front']);
      expect(scope.history.nextUndoLabel.value, 'Raise map layer');
      scope.history.undo();
      expect(_names(TileTool.drawOrder(data.layers)), ['Front', 'Ground']);
    });
  });
}
