// Tiled's files in and out: maps imported with their tilesets and objects,
// maps exported for Tiled and read back the same, and the Assets dock and
// the viewport knowing what to do with each.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/level_map/level_map_provision.dart';
import 'package:just_game_engine_editor/src/core/level_map/tile_commands.dart';
import 'package:just_game_engine_editor/src/core/level_map/tiled_export.dart';
import 'package:just_game_engine_editor/src/core/level_map/tiled_import.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/extension/built_in_tile_contributions.dart';

/// just_tiled's fixtures: real Tiled 1.10 files.
const _fixtures = '../just_tiled/test/fixtures';

/// Reads from the fixtures (or [memory] first), writes to [memory].
TiledFiles _files(
  Map<String, String> memory, {
  Set<String> present = const {},
}) => TiledFiles(
  root: _fixtures,
  read: (path) async =>
      memory[path] ?? await File('$_fixtures/$path').readAsString(),
  write: (path, text) async => memory[path] = text,
  exists: (path) => memory.containsKey(path) || present.contains(path),
);

TilesetData _grass() {
  final ts = TilesetData.fromImage(
    name: 'grass',
    image: 'assets/tilesets/grass.png',
    imageWidth: 64,
    imageHeight: 32,
    tileWidth: 16,
    tileHeight: 16,
  );
  ts.tileOrNew(1).collision = TileCollision.full(16, 16);
  ts.tileOrNew(2).collision = TileCollision(
    kind: 'oneWay',
    shapes: [
      const TilePolygonShape([Offset(0, 16), Offset(16, 0), Offset(16, 16)]),
    ],
  );
  ts.tileOrNew(4)
    ..animation = const [TileFrame(4, 100), TileFrame(5, 150)]
    ..className = 'water';
  return ts;
}

void main() {
  group('importing a map', () {
    test('tile layers, tilesets and objects come across', () async {
      final memory = <String, String>{};
      final plan = await TiledImporter(_files(memory)).read('ortho_finite.tmx');
      final map = plan.map;
      expect(map.orientation, MapOrientation.orthogonal);
      expect(map.tilesets, ['assets/tilesets/ortho_finite_grass.tileset.json']);
      // Groups are flattened: their names, opacity and offset carried in.
      // The object layer is a layer too, for its objects' entities.
      expect(map.layers.map((l) => l.name), [
        'Ground',
        'Things',
        'Decor/Flowers',
        'Decor/Moss',
      ]);
      expect(map.layers[1].cells.usedBounds, isNull);
      expect(map.layers[2].opacity, 0.5);
      expect(map.layers[2].offsetX, 4);
      expect(map.layers[3].visible, isFalse);
      final ground = map.layers.first;
      expect(ground.name, 'Ground');
      expect(ground.collides, isTrue, reason: 'its collides property');
      expect(ground.cells.cellAt(0, 0), TileCell.make(0, 0));
      expect(ground.cells.cellAt(0, 1), TileCell.make(0, 0, TileCell.flipH));
      expect(plan.newTilesets.keys, map.tilesets);
      expect(plan.result.objects, hasLength(7));
      expect(plan.warnings.join(' '), contains('image layer'));

      final written = await TiledImporter(_files(memory)).writeTilesets(plan);
      expect(written, map.tilesets);
      expect(memory[written.single], contains('"collision"'));
    });

    test('objects become entities: a mapper\'s, a prefab by class, or a '
        'plain one where the object was', () async {
      final plan = await TiledImporter(_files({})).read('ortho_finite.tmx');
      final prefabs = PrefabRegistry()
        ..register(
          PrefabDefinition(
            id: 'test.trigger',
            name: 'Trigger',
            category: 'Test',
            icon: Icons.bolt,
            color: Colors.red,
            build: (position, size) => [
              TransformComponent(
                position: Vector3(position.dx, position.dy, 0),
              ),
              RectangleComponent(width: size.width, height: size.height),
            ],
          ),
        );
      final spawns = <TiledObjectInfo>[];
      final names = <String>{};
      String unique(String p) {
        var n = p;
        for (var i = 2; !names.add(n); i++) {
          n = '$p$i';
        }
        return n;
      }

      final specs = TiledImporter.entities(
        plan,
        origin: const Offset(100, 50),
        codec: testScope().codec,
        uniqueName: unique,
        prefabs: prefabs,
        mappers: [
          TiledObjectMapper(
            id: 'test.spawn',
            matches: (o) => o.className == 'PlayerSpawn',
            build: (o) {
              spawns.add(o);
              return [
                TransformComponent(
                  position: Vector3(o.center.dx, o.center.dy, 0),
                ),
              ];
            },
          ),
        ],
      );
      expect(specs, hasLength(8), reason: 'the map and 7 objects');
      expect(specs.first.name, 'ortho_finite');
      expect(specs.skip(1).map((s) => s.parentName).toSet(), {
        'ortho_finite',
      }, reason: 'each object is on a layer of the map');
      expect(
        specs.first.decode().whereType<LevelMapComponent>().single.inline,
        isNotNull,
      );

      expect(spawns.single.name, 'Spawn');
      expect(
        spawns.single.center,
        const Offset(116, 82),
        reason: 'a point is where it is',
      );

      final zone = specs.firstWhere((s) => s.name == 'Zone').decode();
      expect(
        zone.whereType<RectangleComponent>().single.width,
        32,
        reason: 'the Trigger prefab',
      );
      final zoneTransform = zone.whereType<TransformComponent>().single;
      final zoneAt = zoneTransform.position;
      // The Zone is turned 15° in Tiled, about its top-left corner at
      // (100, 50): its middle is that corner plus half its size (16, 8),
      // turned with it.
      final turn = 15 * math.pi / 180;
      expect(
        zoneAt.x,
        closeTo(100 + 16 * math.cos(turn) - 8 * math.sin(turn), 1e-9),
        reason: 'the middle of the object, turned as Tiled turns it',
      );
      expect(
        zoneAt.y,
        closeTo(50 + 16 * math.sin(turn) + 8 * math.cos(turn), 1e-9),
      );
      expect(
        zoneTransform.angle,
        closeTo(turn, 1e-9),
        reason: 'a prefab built for it is turned as the object is',
      );

      // A tile object hangs from its bottom-left corner.
      final tile = specs.last
          .decode()
          .whereType<TransformComponent>()
          .single
          .position;
      expect((tile.x, tile.y), (156.0, 90.0));
    });

    test(
      'external tilesets, TSX and TSJ, are named after their files',
      () async {
        final plan = await TiledImporter(_files({})).read('external.tmx');
        expect(plan.map.tilesets, [
          'assets/tilesets/terrain.tileset.json',
          'assets/tilesets/props.tileset.json',
        ]);
        final cells = plan.map.layers.single.cells;
        expect(cells.cellAt(0, 0), TileCell.make(0, 2));
        expect(cells.cellAt(1, 0), TileCell.make(1, 1));
      },
    );

    test('a tileset already in the project is used, not overwritten', () async {
      // The one there was converted from this same TSX: the same picture.
      final first = await TiledImporter(_files({})).read('external.tmx');
      const existing = 'assets/tilesets/terrain.tileset.json';
      final memory = <String, String>{
        existing: jsonEncode(first.result.tilesets.first!.toJson()),
      };
      final plan = await TiledImporter(_files(memory)).read('external.tmx');
      expect(plan.newTilesets.keys, ['assets/tilesets/props.tileset.json']);
      expect(plan.map.tilesets.first, existing);
      expect(
        plan.warnings.join(' '),
        contains('terrain.tileset.json as it is'),
      );
    });

    test('another tileset of the same name is left alone; this one is '
        'named beside it (EC-34)', () async {
      const existing = 'assets/tilesets/terrain.tileset.json';
      final forest = TilesetData.fromImage(
        name: 'terrain',
        image: 'assets/forest/terrain.png',
        imageWidth: 64,
        imageHeight: 32,
        tileWidth: 16,
        tileHeight: 16,
      );
      final memory = <String, String>{existing: jsonEncode(forest.toJson())};
      final importer = TiledImporter(_files(memory));
      final plan = await importer.read('external.tmx');
      const named = 'assets/tilesets/terrain_2.tileset.json';
      expect(plan.newTilesets.keys, contains(named));
      expect(plan.map.tilesets.first, named);
      expect(plan.warnings.join(' '), contains('is another tileset'));
      await importer.writeTilesets(plan);
      expect(
        jsonDecode(memory[existing]!)['image'],
        'assets/forest/terrain.png',
        reason: 'the forest tileset is not written over',
      );
      expect(memory.containsKey(named), isTrue);
    });

    test(
      'an unreadable tileset of the same name is not written over',
      () async {
        final memory = <String, String>{};
        final plan = await TiledImporter(
          _files(memory, present: {'assets/tilesets/terrain.tileset.json'}),
        ).read('external.tmx');
        expect(
          plan.newTilesets.keys,
          isNot(contains('assets/tilesets/terrain.tileset.json')),
        );
      },
    );

    for (final (file, orientation) in const [
      ('isometric.tmx', MapOrientation.isometric),
      ('staggered.tmx', MapOrientation.staggered),
      ('hexagonal.tmx', MapOrientation.hexagonal),
      ('infinite.tmx', MapOrientation.orthogonal),
      ('ortho.tmj', MapOrientation.orthogonal),
    ]) {
      test('$file comes across as a ${orientation.name} map', () async {
        final plan = await TiledImporter(_files({})).read(file);
        expect(plan.map.orientation, orientation);
        expect(plan.map.layers, isNotEmpty);
        expect(
          plan.map.layers.expand((l) => l.cells.cells),
          isNotEmpty,
          reason: 'it has tiles',
        );
      });
    }

    test('a hexagonal map keeps its turned tiles', () async {
      final plan = await TiledImporter(_files({})).read('hexagonal.tmx');
      final cells = plan.map.layers.single.cells;
      expect(cells.cellAt(1, 0), TileCell.make(0, 0, TileCell.rotate120));
      expect(
        cells.cellAt(2, 0),
        TileCell.make(0, 1, TileCell.flipH | TileCell.rotate120),
      );
      expect(plan.map.hexSideLength, 6);
    });

    test('a TSX converts to a tileset on its own', () async {
      final memory = <String, String>{};
      final to = await TiledImporter(
        _files(memory),
      ).convertTileset('tilesets/terrain.tsx');
      expect(to, 'assets/tilesets/terrain.tileset.json');
      final ts = TilesetData.fromJson(
        jsonDecode(memory[to]!) as Map<String, dynamic>,
      );
      expect(ts.image, 'terrain.png', reason: 'where the TSX says, from it');
    });
  });

  group('exporting a map', () {
    LevelMapData level(MapOrientation orientation) {
      final map = LevelMapData(
        orientation: orientation,
        tileWidth: orientation == MapOrientation.orthogonal ? 16 : 32,
        tileHeight: 16,
        hexSideLength: orientation == MapOrientation.hexagonal ? 8 : 0,
      )..addTileset('assets/tilesets/grass.tileset.json');
      final ground = map.addLayer(name: 'Ground')..collides = true;
      final deco = map.addLayer(name: 'Deco')..opacity = 0.5;
      ground.cells
        ..setCell(0, 0, TileCell.make(0, 1))
        ..setCell(1, 0, TileCell.make(0, 2, TileCell.flipH))
        ..setCell(2, 1, TileCell.make(0, 3, TileCell.flipV | TileCell.flipD))
        ..setCell(-3, 5, TileCell.make(0, 4));
      deco.cells.setCell(4, 4, TileCell.make(0, 5));
      return map;
    }

    for (final ending in const ['tmx', 'tmj']) {
      for (final orientation in MapOrientation.values) {
        test('as .$ending, ${orientation.name}: read back, it is the same '
            'map', () async {
          final memory = <String, String>{};
          final files = _files(memory);
          final grass = _grass();
          final map = level(orientation);
          final written = await TiledExporter(files).export(
            map,
            to: 'assets/maps/level.$ending',
            tilesetAt: (_) => grass,
          );
          expect(written, [
            'assets/maps/grass.${ending == 'tmx' ? 'tsx' : 'tsj'}',
            'assets/maps/level.$ending',
          ]);
          expect(memory[written.first], contains('../tilesets/grass.png'));

          final back = await TiledImporter(
            files,
          ).read('assets/maps/level.$ending');
          expect(back.map.orientation, orientation);
          expect(back.map.tilesets, ['assets/tilesets/grass.tileset.json']);
          for (var i = 0; i < map.layers.length; i++) {
            final a = map.layers[i];
            final b = back.map.layers[i];
            expect(b.name, a.name);
            expect(
              {for (final c in b.cells.cells) (c.$1, c.$2): c.$3},
              {for (final c in a.cells.cells) (c.$1, c.$2): c.$3},
            );
          }
          expect(back.map.layers.first.collides, isTrue);
          expect(back.map.layers.last.opacity, 0.5);

          final ts = back.result.tilesets.single!;
          expect(ts.image, 'assets/tilesets/grass.png');
          expect(ts.tile(2)!.collision!.kind, 'oneWay');
          expect(ts.tile(4)!.animation, grass.tile(4)!.animation);
          expect(ts.tile(4)!.className, 'water');
        });
      }
    }

    test('never over a file that is there: names beside it (EC-5)', () async {
      const tsx = 'assets/maps/grass.tsx';
      const tmx = 'assets/maps/level.tmx';
      final memory = <String, String>{tsx: "the project file", tmx: 'edited'};
      final written = await TiledExporter(_files(memory)).export(
        level(MapOrientation.orthogonal),
        to: tmx,
        tilesetAt: (_) => _grass(),
      );
      expect(written, ['assets/maps/grass_2.tsx', 'assets/maps/level_2.tmx']);
      expect(memory[tsx], "the project file");
      expect(memory[tmx], 'edited');
      expect(memory['assets/maps/level_2.tmx'], contains('grass_2.tsx'));
    });

    test('paths are written relative to the file', () {
      expect(
        relativePath('assets/maps', 'assets/tilesets/grass.png'),
        '../tilesets/grass.png',
      );
      expect(relativePath('assets/maps', 'assets/maps/a.png'), 'a.png');
      expect(relativePath('', 'assets/a.png'), 'assets/a.png');
      expect(relativePath('a/b/c', 'x.png'), '../../../x.png');
    });
  });

  group('in the editor', () {
    test('a map imported into the scene is one undo step', () async {
      final scope = testScope();
      scope.sceneState.openScene(EditorScene(name: 'level'));
      final memory = <String, String>{};
      final made = await BuiltInTileContributions.importIntoScene(
        scope,
        'ortho_finite.tmx',
        at: Offset.zero,
        using: _files(memory),
      );
      // The map, and its 7 objects on the layers their object layers became.
      expect(made, 8);
      final maps = scope.world.query([LevelMapComponent]).toList();
      expect(maps, hasLength(1));
      final objects = [
        for (final id
            in maps.single.getComponent<ChildrenComponent>()!.childIds)
          scope.world.getEntity(id)!,
      ];
      expect(objects, hasLength(7));
      for (final o in objects) {
        expect(
          LevelMaps.memberLayer(scope.world, o),
          isNotNull,
          reason: o.name,
        );
      }
      expect(scope.tiles.mapEntityId.value, maps.single.id);
      expect(
        memory.keys,
        contains('assets/tilesets/ortho_finite_grass.tileset.json'),
      );

      scope.history.undo();
      expect(scope.world.query([LevelMapComponent]), isEmpty);
      expect(scope.world.entities.where((e) => e.name == 'Spawn'), isEmpty);
    });

    test('into a scene whose Level Map is empty, the import takes its '
        'place, as one undo step', () async {
      final scope = testScope();
      scope.sceneState.openScene(EditorScene(name: 'level'));
      final blank = scope.world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: BuiltInPrefabs.newLevelMap()),
      ], name: LevelMaps.primaryName);
      LevelMapData data() => blank.getComponent<LevelMapComponent>()!.inline!;
      final made = await BuiltInTileContributions.importIntoScene(
        scope,
        'ortho_finite.tmx',
        at: Offset.zero,
        using: _files({}),
      );
      expect(made, 8);
      expect(scope.world.query([LevelMapComponent]).single, same(blank));
      expect(LevelMapProvision.isBlank(data()), isFalse);
      expect(scope.world.entities, hasLength(8), reason: 'and 7 objects');
      expect(
        blank.getComponent<ChildrenComponent>()!.childIds,
        hasLength(7),
        reason: 'on its layers',
      );

      scope.history.undo();
      expect(LevelMapProvision.isBlank(data()), isTrue);
      expect(scope.world.entities, [same(blank)]);
    });

    test('a scene whose Level Map has something on it keeps it', () async {
      final scope = testScope();
      scope.sceneState.openScene(EditorScene(name: 'level'));
      final painted = BuiltInPrefabs.newLevelMap();
      painted.layers.single.cells.setCell(0, 0, TileCell.make(0, 1));
      scope.world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: painted),
      ], name: LevelMaps.primaryName);
      final made = await BuiltInTileContributions.importIntoScene(
        scope,
        'ortho_finite.tmx',
        at: Offset.zero,
        using: _files({}),
      );
      expect(made, 0);
      expect(scope.world.entities, hasLength(1), reason: 'nothing imported');
    });

    test(
      'a map imported as a file lands in assets/maps, under a free name',
      () async {
        final scope = testScope();
        // A map from before the rename holds the name as well.
        final memory = <String, String>{'assets/maps/staggered.map.json': '{}'};
        final to = await BuiltInTileContributions.importAsMapFile(
          scope,
          'staggered.tmx',
          using: _files(memory),
        );
        expect(to, 'assets/maps/staggered_2.map.json');
        final map = LevelMapData.fromJson(
          jsonDecode(memory[to]!) as Map<String, dynamic>,
        );
        expect(map.orientation, MapOrientation.staggered);
      },
    );

    test('a rename reaches the maps and tilesets in memory', () {
      final world = World()..initialize();
      final scope = testScope(world: world);
      final inline = LevelMapData()
        ..addTileset('assets/tilesets/a.tileset.json');
      world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: inline),
      ]);
      final file = LevelMapData()..addTileset('assets/tilesets/a.tileset.json');
      world.context.tiles.putMap('assets/maps/one.tilemap.json', file);
      world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(mapPath: 'assets/maps/one.tilemap.json'),
      ]);

      expect(
        scope.mapDocs.renamed(
          'assets/tilesets/a.tileset.json',
          'assets/tilesets/b.tileset.json',
        ),
        2,
      );
      expect(inline.tilesets, ['assets/tilesets/b.tileset.json']);
      expect(file.tilesets, ['assets/tilesets/b.tileset.json']);

      // A map file moved keeps its unsaved edits under the new name.
      scope.mapDocs.markEdited(
        const LevelMapRef(entityId: -1, path: 'assets/maps/one.tilemap.json'),
      );
      scope.mapDocs.renamed(
        'assets/maps/one.tilemap.json',
        'assets/maps/two.tilemap.json',
      );
      expect(
        world.context.tiles.loadedMap('assets/maps/two.tilemap.json'),
        same(file),
      );
      expect(scope.mapDocs.dirtyPaths.value, {'assets/maps/two.tilemap.json'});
    });

    test('the Assets dock knows the files and what to do with them', () {
      expect(AssetKinds.editorKindOf('a/b.tileset.json'), AssetKind.tileset);
      expect(AssetKinds.editorKindOf('a/b.map.json'), AssetKind.levelMap);
      expect(AssetKinds.editorKindOf('a/b.tilemap.json'), AssetKind.levelMap);
      for (final f in ['a.tmx', 'a.tmj', 'a.tsx', 'a.TSJ']) {
        expect(AssetKinds.editorKindOf(f), AssetKind.tiled, reason: f);
      }
      final scope = testScope();
      List<String> offered(String path) => [
        for (final a in scope.assetActions)
          if (a.appliesTo(path, isDirectory: false)) a.id,
      ];
      expect(offered('assets/maps/l.tmx'), [
        'tiles.import_scene',
        'tiles.import_file',
      ]);
      expect(offered('assets/maps/t.tsx'), ['tiles.convert_tileset']);
      expect(offered('assets/maps/l.map.json'), ['tiles.export_tmx']);
      expect(offered('assets/maps/l.tilemap.json'), ['tiles.export_tmx']);
    });

    test('a map file of either name is a map, never a sprite atlas', () {
      for (final path in ['assets/maps/cave.map.json', 'a/B.TILEMAP.JSON']) {
        expect(
          JustGameEditorPlugin.isSpriteAtlasPath(path),
          isFalse,
          reason: path,
        );
        expect(JustGameEditorPlugin.canDropAsset(path), isTrue, reason: path);
        expect(
          tiledStem(path).toLowerCase(),
          path.contains('cave') ? 'cave' : 'b',
        );
      }
    });
  });

  group('dropped on the viewport', () {
    late JustGameEditorPlugin plugin;
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      plugin = JustGameEditorPlugin(engine: engine);
      await plugin.attach(plugin.engine);
      plugin.sceneState.openScene(EditorScene(name: 'level'));
      plugin.engine.cameraSystem.mainCamera.viewportSize = const Size(800, 600);
    });
    tearDown(() {
      plugin.dispose();
    });

    test('a tileset makes a map to paint with, or joins the one there', () {
      const path = 'assets/tilesets/grass.tileset.json';
      expect(JustGameEditorPlugin.canDropAsset(path), isTrue);
      final map = plugin.dropAsset(path, const Offset(400, 300))!;
      final data = map.getComponent<LevelMapComponent>()!.inline!;
      expect(data.tilesets, [path]);
      expect(plugin.scope.tiles.mapEntityId.value, map.id);

      final again = plugin.dropAsset(
        'assets/tilesets/rocks.tileset.json',
        Offset.zero,
      );
      expect(again, same(map));
      expect(data.tilesets, [path, 'assets/tilesets/rocks.tileset.json']);
      expect(plugin.scope.tiles.slot.value, 1);
      plugin.history.undo();
      expect(data.tilesets, [path]);
      // The map was made for the first: one undo takes both away.
      expect(map.name, LevelMaps.primaryName);
      plugin.history.undo();
      expect(plugin.engine.world.query([LevelMapComponent]), isEmpty);
    });

    test('a map file becomes the Level Map: made for it, or the empty one '
        'switched to it; one painted on is kept', () {
      final world = plugin.engine.world;
      final e = plugin.dropAsset('assets/maps/cave.map.json', Offset.zero)!;
      expect(
        e.getComponent<LevelMapComponent>()!.mapPath,
        'assets/maps/cave.map.json',
      );
      expect(e.name, LevelMaps.primaryName);
      plugin.history.undo();
      expect(world.query([LevelMapComponent]), isEmpty);

      final blank = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: BuiltInPrefabs.newLevelMap()),
      ], name: LevelMaps.primaryName);
      LevelMapComponent map() => blank.getComponent<LevelMapComponent>()!;
      expect(
        plugin.dropAsset('assets/maps/old.tilemap.json', Offset.zero),
        same(blank),
      );
      expect(map().mapPath, 'assets/maps/old.tilemap.json');
      plugin.history.undo();
      expect(map().usesFile, isFalse);

      map().inline!.layers.single.cells.setCell(0, 0, TileCell.make(0, 1));
      expect(
        plugin.dropAsset('assets/maps/cave.map.json', Offset.zero),
        isNull,
      );
      expect(map().usesFile, isFalse, reason: 'the painted map is kept');
      expect(world.query([LevelMapComponent]), hasLength(1));
      expect(JustGameEditorPlugin.canDropAsset('assets/maps/cave.tmx'), isTrue);
    });
  });
}
