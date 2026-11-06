// Everything the Level Designer places goes under the Level Map, on a map
// layer: a prefab file drawn with Draw, an entity made or pasted "here" —
// the map, and the layer, made in the same undo step when there are none.
import 'dart:io';

import 'package:flutter/material.dart' show Colors, Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import '../support/test_scope.dart';
import 'package:just_game_engine_editor/src/level_map/map_placement.dart';
import 'package:just_game_engine_editor/src/prefabs/prefab_instances.dart';

const _crate = 'assets/prefabs/crate.prefab.json';

final _crateFile = PrefabFile(
  name: 'Crate',
  entities: [
    PrefabEntity(
      id: 'box',
      name: 'Box',
      components: [
        {
          'type': 'TransformComponent',
          'fields': {
            'position': {'x': 0.0, 'y': 0.0, 'z': 0.0},
          },
        },
      ],
    ),
    PrefabEntity(
      id: 'lid',
      name: 'Lid',
      parent: 'box',
      components: [
        {
          'type': 'TransformComponent',
          'fields': {
            'position': {'x': 0.0, 'y': -8.0, 'z': 0.0},
          },
        },
      ],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late EditorScope scope;
  late LevelDesignerSession session;

  List<Entity> maps() => world.query([LevelMapComponent]).toList();
  Entity named(String name) =>
      world.entities.firstWhere((e) => e.isAlive && e.name == name);
  // The top of the crate's instance, named after it.
  Entity crate() => world.entities.firstWhere(
    (e) => e.isAlive && e.hasComponent<PrefabInstanceComponent>(),
  );

  setUp(() {
    world = World()..initialize();
    scope = testScope(world: world);
    scope.sceneState.openScene(EditorScene(name: 'level'));
    session = LevelDesignerSession(
      scope: scope,
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => const ModifierKeys(),
    );
    addTearDown(session.dispose);
    session.controller.snapEnabled.value = false;
  });

  group('a prefab file drawn', () {
    setUp(() async {
      final dir = Directory.systemTemp.createTempSync('jge_draw_prefab');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/$_crate')
        ..createSync(recursive: true)
        ..writeAsStringSync(_crateFile.encode());
      final prefabs = PrefabInstances(scope, root: dir.path);
      scope.container.registerSingleton<PrefabInstances>(prefabs);
      scope.context.overrideLoaders(
        prefabs: (path) async =>
            PrefabFile.parse(File('${dir.path}/$path').readAsStringSync()),
      );
      await prefabs.library.load(_crate);
      final file = PrefabDefinition(
        id: 'file:$_crate',
        name: 'Crate',
        category: 'Prefab files',
        icon: Icons.inventory_2_outlined,
        color: Colors.blue,
        placement: PrefabPlacement.point,
        instanceOf: _crate,
        build: (_, _) => const [],
      );
      session.sessionPrefabs.register(file);
      session
        ..setTool(BuiltInTools.draw)
        ..controller.activePrefabId.value = file.id;
    });

    test('in a scene with no Level Map, goes under one made for it, on its '
        'layer, selected; one undo takes both away', () {
      session
        ..onPointerDown(const Offset(100, 50), 32)
        ..onPointerUp(const Offset(100, 50), 32);
      final map = maps().single;
      final box = crate();
      expect(box.name, startsWith('Crate'));
      expect(box.hasComponent<PrefabInstanceComponent>(), isTrue);
      expect(LevelMaps.ownerOf(world, box), same(map));
      expect(LevelMaps.memberLayer(world, box), isNotNull);
      expect(named('Lid').getComponent<ParentComponent>()!.parentId, box.id);
      expect(session.sceneState.selectedEntity.value, box);
      expect(scope.history.undoEntries, hasLength(1));

      scope.history.undo();
      expect(maps(), isEmpty);
      expect(world.entities.where((e) => e.isAlive), isEmpty);
      scope.history.redo();
      final again = crate();
      expect(LevelMaps.memberLayer(world, again), isNotNull);
      expect(LevelMaps.ownerOf(world, again), same(maps().single));
    });

    test('on a map with a layer, goes on that layer', () {
      final data = BuiltInPrefabs.newLevelMap();
      world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: data),
      ], name: LevelMaps.primaryName);
      session.controller.activeLayerId.value = data.layers.single.sortLayerId;
      session
        ..onPointerDown(const Offset(100, 50), 32)
        ..onPointerUp(const Offset(100, 50), 32);
      expect(LevelMaps.memberLayer(world, crate()), data.layers.single);
    });
  });

  group('made or pasted here', () {
    test('a new entity goes on the map\'s layer at the depth', () {
      final made = MapPlacement.createAt(
        scope,
        world,
        const Offset(40, 60),
        depth: session.controller.activeLayerId.value,
      )!;
      expect(LevelMaps.memberLayer(world, made), isNotNull);
      expect(made.getComponent<TransformComponent>()!.position.x, 40);
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(world.entities.where((e) => e.isAlive), isEmpty);
    });

    test('a paste goes on the map\'s layer, whatever layer it was copied '
        'from', () {
      final copied = world.createEntityWithComponents([
        TransformComponent(),
        Rectangle2DComponent(width: 10, height: 10),
        LayerComponent(mapLayer: 99),
      ], name: 'Copied');
      scope.sceneState.registerEntity(copied);
      scope.sceneState.clipboard.value = [
        for (final c in copied.components) ?scope.codec.encode(c),
      ];
      final pasted = MapPlacement.pasteAt(
        scope,
        world,
        const Offset(200, 20),
        depth: session.controller.activeLayerId.value,
      )!;
      final layer = LevelMaps.memberLayer(world, pasted);
      expect(layer, isNotNull);
      expect(pasted.getComponent<LayerComponent>()!.mapLayer, layer!.id);
      expect(pasted.getComponent<TransformComponent>()!.position.x, 200);
      expect(pasted.components.whereType<Rectangle2DComponent>(), hasLength(1));
    });

    test('nothing copied: nothing pasted', () {
      expect(
        MapPlacement.pasteAt(scope, world, Offset.zero, depth: 'main'),
        isNull,
      );
      expect(maps(), isEmpty);
    });
  });
}
