// What the Problems dock says about tile maps: tiles that cannot be drawn,
// collision nobody registered, terrains short of tiles.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);

  late World world;
  late EditorScope scope;
  late Map<String, String> files;

  setUp(() {
    world = World()..initialize();
    scope = testScope(world: world);
    files = {};
  });

  List<SceneProblem> check() => BuiltInValidators.levelMaps(
    ValidationContext(
      scope: scope,
      fileExists: files.containsKey,
      readText: (p) => files[p],
    ),
  );

  LevelMapData mapWith(
    TilesetData ts, {
    String path = 'assets/t.tileset.json',
  }) {
    files[path] = jsonEncode(ts.toJson());
    final map = LevelMapData()..addTileset(path);
    map.addLayer(name: 'Ground');
    return map;
  }

  Entity place(LevelMapData map, {double rotation = 0}) =>
      world.createEntityWithComponents([
        TransformComponent(rotation: rotation),
        LevelMapComponent(inline: map),
      ], name: 'Map');

  TilesetData tileset() =>
      TilesetData(name: 'grass', image: 'g.png', columns: 4, tileCount: 8);

  test('a sound map says nothing', () {
    final map = mapWith(tileset());
    map.layers.single.cells.setCell(0, 0, TileCell.make(0, 3));
    place(map);
    expect(check(), isEmpty);
  });

  test('a second map is a warning on it, not on the Level Map', () {
    final ts = tileset();
    final level = place(mapWith(ts))..name = LevelMaps.primaryName;
    final extra = place(mapWith(ts));
    final problems = check();
    expect(problems, hasLength(1));
    expect(problems.single.entity, same(extra));
    expect(problems.single.severity, ProblemSeverity.warning);
    expect(problems.single.message, contains('second map'));
    expect(problems.single.message, contains(level.name));
  });

  test('what names a map layer is under a map that has it, or it is '
      'warned of; a piece of the map is no second map', () {
    final map = mapWith(tileset());
    final level = place(map)
      ..name = LevelMaps.primaryName
      ..addComponent(ChildrenComponent());
    Entity child(String name, int layerId, {Entity? of}) {
      final e = world.createEntityWithComponents([
        TransformComponent(),
        LayerComponent(mapLayer: layerId),
        if (of != null) ParentComponent(parentId: of.id),
      ], name: name);
      of?.getComponent<ChildrenComponent>()!.addChild(e.id);
      return e;
    }

    final ground = map.layers.single.id;
    child('Loose', ground);
    child('Lost', ground + 7, of: level);
    child('Fine', ground, of: level);
    final piece = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: LevelMapData()..addLayer(name: 'Cut')),
      LayerComponent(mapLayer: ground),
      ParentComponent(parentId: level.id),
    ], name: 'Tiles');
    level.getComponent<ChildrenComponent>()!.addChild(piece.id);

    final problems = check();
    expect(problems.map((p) => p.entity?.name), ['Loose', 'Lost']);
    expect(problems.first.message, contains('not on a map'));
    expect(problems.last.message, contains('no longer has'));
  });

  test('a missing tileset is an error', () {
    final map = LevelMapData()..addTileset('assets/gone.tileset.json');
    map.addLayer();
    place(map);
    expect(check().single.message, contains('does not exist'));
  });

  test('tiles past the end of a tileset re-cut smaller are an error', () {
    final map = mapWith(tileset());
    map.layers.single.cells
      ..setCell(0, 0, TileCell.make(0, 8))
      ..setCell(1, 0, TileCell.make(0, 9));
    place(map);
    final problem = check().single;
    expect(problem.severity, ProblemSeverity.error);
    expect(problem.message, contains('2 tiles past the end'));
  });

  test('tiles of a slot the map no longer has are an error', () {
    final map = mapWith(tileset());
    map.layers.single.cells.setCell(0, 0, TileCell.make(3, 0));
    place(map);
    expect(check().single.message, contains('no longer has'));
  });

  test('collision of an unregistered kind is a warning', () {
    final ts = tileset()
      ..tileOrNew(0).collision = TileCollision.full(32, 32, kind: 'lava');
    place(mapWith(ts));
    expect(check().single.message, contains('"lava"'));
  });

  test('a turned map, and a map with no layers, are warnings', () {
    final map = mapWith(tileset())..layers.clear();
    place(map, rotation: 0.5);
    final messages = check().map((p) => p.message).toList();
    expect(messages, hasLength(2));
    expect(messages.any((m) => m.contains('not turned or scaled')), isTrue);
    expect(messages.any((m) => m.contains('no layers')), isTrue);
  });

  test('a corner terrain short of combinations says how many', () {
    final ts = tileset();
    final set = WangSetData(name: 'Grass');
    WangTemplate.corner16.applyTo(set, firstTile: 0, tilesetColumns: 4);
    set.wangIds
      ..remove(3)
      ..remove(9);
    ts
      ..tileCount = 16
      ..wangSets.add(set);
    place(mapWith(ts));
    expect(check().single.message, contains('lacks 2 combinations'));
  });

  test('a one-terrain edge set counts "nothing" as one of its values', () {
    final ts = tileset();
    final set = WangSetData(type: WangType.edge, colors: [WangColorData()]);
    for (var n = 0; n < 16; n++) {
      int c(int bit) => n & bit != 0 ? 1 : 0;
      set.wangIds[n] = [c(1), 0, c(2), 0, c(4), 0, c(8), 0];
    }
    ts
      ..tileCount = 16
      ..wangSets.add(set);
    place(mapWith(ts));
    expect(check(), isEmpty, reason: 'all 16 road pieces are there');
  });

  group('what the game ships', () {
    List<SceneProblem> shipping() => BuiltInValidators.unshippedTileAssets(
      ValidationContext(
        scope: scope,
        fileExists: files.containsKey,
        readText: (p) => files[p],
      ),
    );

    const pubspec = '''
name: game
flutter:
  uses-material-design: true
  assets:
    - assets/scenes/
    - "assets/tilesets/"
    # Tile maps.
    - assets/maps/
dev_dependencies:
  assets:
    - not/this/
''';

    test('reads the asset folders the pubspec lists', () {
      files['pubspec.yaml'] = pubspec;
      final listed = BuiltInValidators.shippedAssets(
        ValidationContext(scope: scope, readText: (p) => files[p]),
      );
      expect(listed, ['assets/scenes/', 'assets/tilesets/', 'assets/maps/']);
      expect(
        BuiltInValidators.isShipped('assets/maps/a.tilemap.json', listed!),
        isTrue,
      );
      expect(
        BuiltInValidators.isShipped('assets/maps/cave/a.tilemap.json', listed),
        isFalse,
        reason: 'asset folders do not reach into the folders inside them',
      );
    });

    test('a tileset or image the game would not find is reported', () {
      files['pubspec.yaml'] = pubspec;
      final shipped = mapWith(
        TilesetData(
          name: 'a',
          image: 'assets/art/a.png',
          columns: 1,
          tileCount: 1,
        ),
        path: 'assets/tilesets/a.tileset.json',
      );
      shipped.addTileset('assets/art/b.tileset.json');
      files['assets/art/b.tileset.json'] = jsonEncode(
        TilesetData(name: 'b', image: 'assets/tilesets/b.png').toJson(),
      );
      place(shipped);
      final problems = shipping();
      expect(problems.map((p) => p.message), [
        contains('"assets/art/a.png"'),
        contains('"assets/art/b.tileset.json"'),
      ]);
      expect(problems.first.hint, contains('- assets/art/'));
    });

    test('with no pubspec there is nothing to say', () {
      place(mapWith(tileset(), path: 'assets/art/t.tileset.json'));
      expect(shipping(), isEmpty);
    });
  });
}
