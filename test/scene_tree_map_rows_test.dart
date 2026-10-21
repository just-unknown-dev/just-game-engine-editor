// A level map in the scene tree: its layers under it, front first, and
// what is on each layer under that — real entities, found by a search,
// selected, dropped onto a layer and dragged off it, every move one undo
// step — and the entities a Tiled map's objects become, on its layers.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/scene_tree/map_item_row.dart';
import 'package:just_tiled/just_tiled.dart' as tiled;

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/entity/entity_ops.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/ui/scene_tree/scene_tree_controller.dart';
import 'package:just_game_engine_editor/src/ui/scene_tree/scene_tree_panel.dart';

void main() {
  late EditorScope scope;
  late EntityOps ops;
  late SceneTreeController controller;
  late Entity map;
  late LevelMapData data;
  late MapLayerData back, front;
  late Entity sign, ledge, crate;

  Entity entity(String name, {MapLayerData? on}) {
    final e = scope.world.createEntityWithComponents([
      TransformComponent(),
      if (on != null) LayerComponent(mapLayer: on.id),
    ], name: name);
    scope.sceneState.registerEntity(e);
    if (on != null) {
      placeEntity(
        e,
        world: scope.world,
        sceneState: scope.sceneState,
        slot: HierarchySlot(parentId: map.id, index: -1),
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
      camera: () => GameCameraEditorView.of(Camera()),
    );
    controller = SceneTreeController(world: () => scope.world);
    addTearDown(controller.dispose);
    scope.sceneState.openScene(EditorScene(name: 'level'));
    data = LevelMapData();
    back = data.addLayer(name: 'Back');
    front = data.addLayer(name: 'Front');
    map = scope.world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: data),
    ], name: LevelMaps.primaryName);
    scope.sceneState.registerEntity(map);
    sign = entity('Sign', on: back);
    ledge = entity('Ledge', on: front);
    crate = entity('Crate');
  });

  SceneTree build({TreeFilter filter = TreeFilter.none}) =>
      SceneTreeModel.build(
        world: scope.world,
        rootOrder: [map.id, crate.id],
        expanded: controller.expanded.value,
        expandedLayers: controller.expandedLayers.value,
        filter: filter,
        mapOf: (e) => e.getComponent<LevelMapComponent>()?.inline,
      );

  /// A row as `name` for an entity, `[layer]` for a map layer.
  String label(TreeRow r) => switch (r.item) {
    MapLayerTreeItem(:final layerId) => '[${data.layerById(layerId)!.name}]',
    _ => r.entity.name!,
  };

  group('the model', () {
    test('a map lists its layers front first, and an open layer what is on '
        'it', () {
      expect(build().rows.first.hasChildren, isTrue);
      controller.expand(map.id);
      expect(build().rows.map(label), [
        'Level Map',
        '[Front]',
        '[Back]',
        'Crate',
      ]);

      controller.toggleLayer(map.id, front.id);
      final rows = build().rows;
      expect(rows.map(label), [
        'Level Map',
        '[Front]',
        'Ledge',
        '[Back]',
        'Crate',
      ]);
      expect(rows[2].depth, 2);
      expect(rows[2].item, isNull, reason: 'an entity row like any other');
      expect(build().indexOf(ledge.id), 2);
    });

    test('a child of the map on none of its layers comes after them', () {
      final note = entity('Note');
      placeEntity(
        note,
        world: scope.world,
        sceneState: scope.sceneState,
        slot: HierarchySlot(parentId: map.id, index: -1),
      );
      controller.expand(map.id);
      final rows = build().rows;
      expect(rows.map(label), [
        'Level Map',
        '[Front]',
        '[Back]',
        'Note',
        'Crate',
      ]);
      expect(rows[3].depth, 1);
    });

    test('a search finds what is on a layer, and shows its way there; a '
        'layer\'s name finds the layer', () {
      var rows = build(filter: const TreeFilter(text: 'ledge')).rows;
      expect(rows.map(label), ['Level Map', '[Front]', 'Ledge']);
      expect(rows.first.isMatch, isFalse, reason: 'the map only leads there');

      rows = build(filter: const TreeFilter(text: 'back')).rows;
      expect(rows.map(label), ['Level Map', '[Back]']);
      expect(rows[1].isMatch, isTrue);
    });

    test('selecting an entity on a layer opens the map and the layer', () {
      controller.reveal(sign.id);
      expect(build().rows.map(label), contains('Sign'));
    });
  });

  group('onto a layer and off it', () {
    test('onto a layer: under the map, on that layer, one undo', () {
      ops.reparentAll([crate], map, mapLayer: back.id);
      expect(LevelMaps.ownerOf(scope.world, crate), same(map));
      expect(LevelMaps.memberLayer(scope.world, crate), same(back));
      scope.history.undo();
      expect(LevelMaps.ownerOf(scope.world, crate), isNull);
      expect(
        crate.hasComponent<LayerComponent>(),
        isFalse,
        reason: 'the layer component it was given goes with the undo',
      );
    });

    test('off the map: off its layer too, and back with an undo', () {
      ops.reparentAll([sign], null);
      expect(sign.getComponent<LayerComponent>()!.mapLayer, isNull);
      expect(LevelMaps.ownerOf(scope.world, sign), isNull);
      scope.history.undo();
      expect(LevelMaps.memberLayer(scope.world, sign), same(back));
    });

    test('from one layer to another', () {
      ops.reparentAll([sign], map, mapLayer: front.id);
      expect(LevelMaps.memberLayer(scope.world, sign), same(front));
      scope.history.undo();
      expect(LevelMaps.memberLayer(scope.world, sign), same(back));
    });
  });

  group('the panel', () {
    Future<void> pumpTree(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(320, 600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SceneTreePanel(
              scope: scope,
              entities: ops,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('an entity selected on a layer is shown there', (tester) async {
      await pumpTree(tester);
      expect(find.text('Sign'), findsNothing, reason: 'its layer is shut');
      scope.sceneState.selectEntity(sign);
      await tester.pump();
      await tester.pump();
      expect(find.text('Sign'), findsOneWidget);
      expect(find.byType(Scrollbar), findsOneWidget);
    });

    testWidgets('a layer row counts what is on it, and takes an entity '
        'dropped on it', (tester) async {
      controller.expand(map.id);
      await pumpTree(tester);
      expect(find.text('1 entity'), findsNWidgets(2));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Crate')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.moveTo(tester.getCenter(find.text('Back')));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(LevelMaps.memberLayer(scope.world, crate), same(back));
      expect(find.text('2 entities'), findsOneWidget);
    });

    testWidgets('a layer row paints its layer; its eye and padlock are '
        'saved, and undo', (tester) async {
      controller.expand(map.id);
      await pumpTree(tester);
      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(scope.tiles.layerId.value, back.id);

      await tester.tap(find.byTooltip('Hide map layer').last);
      await tester.pump();
      expect(back.visible, isFalse);
      await tester.tap(find.byTooltip('Lock map layer').last);
      await tester.pump();
      expect(back.locked, isTrue);
      scope.history
        ..undo()
        ..undo();
      expect((back.visible, back.locked), (true, false));
    });

    testWidgets('a layer row picked is the selection until something else '
        'is; its layer stays painted', (tester) async {
      controller.expand(map.id);
      await pumpTree(tester);
      Color? backgroundOf(String name) => tester
          .widget<Container>(
            find
                .descendant(
                  of: find.ancestor(
                    of: find.text(name),
                    matching: find.byType(MapItemRow),
                  ),
                  matching: find.byType(Container),
                )
                .first,
          )
          .color;

      scope.sceneState.selectEntity(crate);
      await tester.pump();
      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(scope.tiles.layerId.value, back.id);
      expect(backgroundOf('Back'), EditorTheme.selectionBg);
      expect(
        scope.sceneState.hasAnySelection,
        isFalse,
        reason: 'one selection in the tree',
      );

      // An entity picked takes the selection off it — the bug was that
      // nothing did.
      await tester.tap(find.text('Crate'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(scope.sceneState.selectedEntity.value, same(crate));
      expect(backgroundOf('Back'), isNot(EditorTheme.selectionBg));
      expect(scope.tiles.layerId.value, back.id, reason: 'still painted');

      // So does a click on the empty part of the tree.
      scope.sceneState.clearSelection();
      controller.pickedLayer.value = (map.id, back.id);
      await tester.pump();
      expect(backgroundOf('Back'), EditorTheme.selectionBg);
      await tester.tapAt(const Offset(160, 560));
      await tester.pump();
      expect(controller.pickedLayer.value, isNull);
      expect(backgroundOf('Back'), isNot(EditorTheme.selectionBg));
    });

    testWidgets('the arrow keys walk the entities, past the map\'s rows', (
      tester,
    ) async {
      controller.expand(map.id);
      await pumpTree(tester);
      await tester.tap(find.text(LevelMaps.primaryName));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(scope.sceneState.selectedEntity.value, same(crate));
    });
  });

  group('a Tiled map, in the editor', () {
    const tmx = '''<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" orientation="orthogonal" renderorder="right-down" width="2" height="2" tilewidth="16" tileheight="16" infinite="0" nextlayerid="3" nextobjectid="5">
 <objectgroup id="2" name="Things">
  <object id="1" name="Start" type="PlayerSpawn" x="5" y="5"><point/></object>
  <object id="2" name="Door" type="Trigger" x="0" y="0" width="16" height="32"/>
  <object id="3" name="Floor" type="Solid" x="0" y="64" width="128" height="16"/>
  <object id="4" name="Rock" x="40" y="40" width="10" height="10"><ellipse/></object>
 </objectgroup>
</map>
''';

    test('every object is an entity on the layer its object layer became; '
        'its class names a prefab by id, name or alias', () async {
      List<Component> marked(double width) => [
        TransformComponent(),
        RectangleComponent(width: width, height: 1),
      ];
      final prefabs = PrefabRegistry()
        ..register(
          PrefabDefinition(
            id: 'game.gate',
            name: 'Gate',
            category: 'Test',
            icon: Icons.door_front_door,
            color: Colors.brown,
            aliases: const ['trigger'],
            build: (at, size) => marked(7),
          ),
        )
        ..register(
          PrefabDefinition(
            id: 'game.ground',
            name: 'Ground',
            category: 'Test',
            icon: Icons.crop_16_9,
            color: Colors.green,
            aliases: const ['Solid'],
            build: (at, size) => marked(9),
          ),
        );
      final plan = await TiledImporter(
        TiledFiles(root: '.', read: (_) async => tmx),
      ).read('things.tmx');
      final things = plan.map.layers.single;
      expect(things.name, 'Things');
      expect(things.cells.usedBounds, isNull, reason: 'a layer of no tiles');

      final specs = TiledImporter.entities(
        plan,
        origin: Offset.zero,
        codec: scope.codec,
        uniqueName: (p) => p,
        prefabs: prefabs,
        mapName: LevelMaps.primaryName,
      );
      expect(specs.map((s) => s.name), [
        LevelMaps.primaryName,
        'Start',
        'Door',
        'Floor',
        'Rock',
      ]);
      double? widthOf(String name) => specs
          .firstWhere((s) => s.name == name)
          .decode()
          .whereType<RectangleComponent>()
          .firstOrNull
          ?.width;
      expect(widthOf('Door'), 7, reason: 'the class, an alias');
      expect(widthOf('Floor'), 9);
      expect(widthOf('Rock'), isNull, reason: 'no class: a plain entity');
      for (final spec in specs.skip(1)) {
        expect(spec.parentName, LevelMaps.primaryName);
        expect(
          spec.decode().whereType<LayerComponent>().single.mapLayer,
          things.id,
        );
      }
    });

    test('exported, a layer of no tiles is still a layer', () async {
      final data = LevelMapData(tileWidth: 16, tileHeight: 16)
        ..addLayer(name: 'Deco');
      final exported = TiledInterop.exportMap(
        data,
        const [],
        imageSource: (_) => '',
      );
      expect((exported.layers.single as tiled.TileLayer).name, 'Deco');
    });
  });
}
