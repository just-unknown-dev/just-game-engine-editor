// Undo for tile edits, and where maps are kept: in the scene or in a file,
// saved with the scene.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  late World world;
  late EditorScope scope;

  setUp(() {
    world = World()..initialize();
    scope = testScope(world: world);
  });

  Entity newMap() => world.createEntityWithComponents([
    TransformComponent(),
    LevelMapComponent(inline: BuiltInPrefabs.newLevelMap()),
  ], name: 'Map');

  TileStroke strokeOn(Entity entity) {
    final target = scope.mapDocs.resolve(entity)!;
    return TileStroke(
      docs: scope.mapDocs,
      ref: target.ref,
      layer: target.data.layers.single,
    );
  }

  int cellAt(Entity e, int x, int y) => e
      .getComponent<LevelMapComponent>()!
      .inline!
      .layers
      .single
      .cells
      .cellAt(x, y);

  test('a stroke is one undo step, and marks the scene unsaved', () {
    final map = newMap();
    final stroke = strokeOn(map)
      ..set(const TileCoord(0, 0), TileCell.make(0, 1))
      ..set(const TileCoord(1, 0), TileCell.make(0, 1))
      ..set(const TileCoord(1, 0), TileCell.make(0, 2));
    scope.history.pushApplied(stroke.finish('Paint tiles')!);

    expect(cellAt(map, 1, 0), TileCell.make(0, 2));
    expect(scope.sceneState.isDirty.value, isTrue);

    scope.history.undo();
    expect(cellAt(map, 0, 0), TileCell.empty);
    expect(
      cellAt(map, 1, 0),
      TileCell.empty,
      reason: 'back to before the stroke',
    );

    scope.history.redo();
    expect(cellAt(map, 1, 0), TileCell.make(0, 2));
  });

  test('two strokes are two steps, however alike', () {
    final map = newMap();
    for (final x in [0, 1]) {
      final s = strokeOn(map)..set(TileCoord(x, 0), TileCell.make(0, 1));
      scope.history.pushApplied(s.finish('Paint tiles')!);
    }
    scope.history.undo();
    expect(cellAt(map, 0, 0), TileCell.make(0, 1));
    expect(cellAt(map, 1, 0), TileCell.empty);
  });

  test('a stroke that changes nothing is no step at all', () {
    final map = newMap();
    final stroke = strokeOn(map)..set(const TileCoord(0, 0), TileCell.empty);
    expect(stroke.finish('Paint tiles'), isNull);
  });

  test('a stroke can be taken back mid-drag', () {
    final map = newMap();
    strokeOn(map)
      ..set(const TileCoord(0, 0), TileCell.make(0, 1))
      ..revert();
    expect(cellAt(map, 0, 0), TileCell.empty);
  });

  test('undo finds the map by its entity after the map was replaced', () {
    final map = newMap();
    final stroke = strokeOn(map)
      ..set(const TileCoord(2, 2), TileCell.make(0, 3));
    scope.history.pushApplied(stroke.finish('Paint tiles')!);
    // A play-test stopping decodes a new map from the snapshot.
    final c = map.getComponent<LevelMapComponent>()!;
    c.inline = LevelMapData.fromJson(c.inline!.toJson());

    scope.history.undo();
    expect(cellAt(map, 2, 2), TileCell.empty);
  });

  test('an undo step whose map is gone does nothing', () {
    final map = newMap();
    final stroke = strokeOn(map)
      ..set(const TileCoord(0, 0), TileCell.make(0, 1));
    scope.history.pushApplied(stroke.finish('Paint tiles')!);
    world.destroyEntity(map);
    expect(scope.history.undo, returnsNormally);
  });

  group('the map\'s shape', () {
    test('a layer removed and put back comes back with its tiles', () {
      final map = newMap();
      final ref = scope.mapDocs.resolve(map)!.ref;
      final add = MapStructureCommand.record(
        label: 'Add layer',
        docs: scope.mapDocs,
        ref: ref,
        change: (m) => m.addLayer(name: 'Decor').cells.setCell(4, 4, 7),
      )!;
      scope.history.pushApplied(add);
      final remove = MapStructureCommand.record(
        label: 'Delete layer',
        docs: scope.mapDocs,
        ref: ref,
        change: (m) => m.layers.removeWhere((l) => l.name == 'Decor'),
      )!;
      scope.history.pushApplied(remove);
      final data = map.getComponent<LevelMapComponent>()!.inline!;
      expect(data.layers.map((l) => l.name), ['Ground']);

      scope.history.undo();
      expect(data.layers.map((l) => l.name), ['Ground', 'Decor']);
      expect(data.layers.last.cells.cellAt(4, 4), 7);

      scope.history.undo();
      expect(data.layers.map((l) => l.name), ['Ground']);
    });

    test('dragging a setting is one step, and undo puts it back', () {
      final map = newMap();
      final ref = scope.mapDocs.resolve(map)!.ref;
      final data = map.getComponent<LevelMapComponent>()!.inline!;
      final id = data.layers.single.id;
      for (final opacity in [0.9, 0.7, 0.5]) {
        scope.history.pushApplied(
          MapStructureCommand.record(
            label: 'Opacity',
            docs: scope.mapDocs,
            ref: ref,
            change: (m) => m.layerById(id)!.opacity = opacity,
            mergeKey: ('opacity', id),
          )!,
        );
      }
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(data.layers.single.opacity, 1);
    });

    test("a layer's material and shadows undo too", () {
      final map = newMap();
      final ref = scope.mapDocs.resolve(map)!.ref;
      final data = map.getComponent<LevelMapComponent>()!.inline!;
      final id = data.layers.single.id;
      scope.history.pushApplied(
        MapStructureCommand.record(
          label: 'Material',
          docs: scope.mapDocs,
          ref: ref,
          change: (m) => m.layerById(id)!
            ..material = 'assets/fx/water.material2d.json'
            ..castsShadows = true
            ..shadowDepth = 30,
        )!,
      );
      scope.history.undo();
      final layer = data.layers.single;
      expect(layer.material, isEmpty);
      expect(layer.castsShadows, isFalse);
      expect(layer.shadowDepth, isNot(30));
      scope.history.redo();
      expect(data.layers.single.material, 'assets/fx/water.material2d.json');
      expect(data.layers.single.castsShadows, isTrue);
    });

    test('a renamed material is renamed on the layers drawn with it', () {
      final map = newMap();
      final data = map.getComponent<LevelMapComponent>()!.inline!;
      data.layers.single.material = 'assets/fx/water.material2d.json';
      final changed = scope.mapDocs.renamed(
        'assets/fx/water.material2d.json',
        'assets/fx/sea.material2d.json',
      );
      expect(changed, 1);
      expect(data.layers.single.material, 'assets/fx/sea.material2d.json');
    });
  });

  group('in its own file', () {
    late Directory project;

    setUp(() {
      project = Directory.systemTemp.createTempSync('tile_docs');
      addTearDown(() {
        if (project.existsSync()) project.deleteSync(recursive: true);
      });
    });

    LevelMapDocuments docsIn() => LevelMapDocuments(
      world: () => world,
      sceneState: scope.sceneState,
      projectRoot: project.path,
    );

    test('a map moves to a file and back, one undo step each way', () async {
      final docs = docsIn();
      final map = newMap();
      final c = map.getComponent<LevelMapComponent>()!;
      c.inline!.layers.single.cells.setCell(3, 3, TileCell.make(0, 5));

      final extract = await docs.extractToAsset(
        map,
        'assets/maps/a.tilemap.json',
      );
      scope.history.pushApplied(extract!);
      expect(c.mapPath, 'assets/maps/a.tilemap.json');
      expect(c.inline, isNull);
      final saved =
          jsonDecode(
                File(
                  '${project.path}/assets/maps/a.tilemap.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(
        LevelMapData.fromJson(saved).layers.single.cells.cellAt(3, 3),
        TileCell.make(0, 5),
      );
      expect(docs.resolve(map)!.isFile, isTrue);

      scope.history.undo();
      expect(c.mapPath, isEmpty);
      expect(c.inline!.layers.single.cells.cellAt(3, 3), TileCell.make(0, 5));

      scope.history.redo();
      final embed = docs.embed(map)!;
      scope.history.pushApplied(embed);
      expect(c.mapPath, isEmpty);
      expect(c.inline!.layers.single.cells.cellAt(3, 3), TileCell.make(0, 5));
    });

    test('an edited map file is written when the scene is saved', () async {
      final docs = docsIn();
      final map = newMap();
      scope.history.pushApplied(
        (await docs.extractToAsset(map, 'assets/maps/b.tilemap.json'))!,
      );
      final target = docs.resolve(map)!;
      final stroke = TileStroke(
        docs: docs,
        ref: target.ref,
        layer: target.data.layers.single,
      )..set(const TileCoord(9, 9), TileCell.make(0, 2));
      scope.history.pushApplied(stroke.finish('Paint tiles')!);
      expect(docs.dirtyPaths.value, {'assets/maps/b.tilemap.json'});

      await docs.saveDirty();

      expect(docs.hasDirty, isFalse);
      final saved = LevelMapData.fromJson(
        jsonDecode(
              File(
                '${project.path}/assets/maps/b.tilemap.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      expect(saved.layers.single.cells.cellAt(9, 9), TileCell.make(0, 2));
    });
  });

  test('the tile state follows the selection and forgets the old scene', () {
    final map = newMap();
    scope.sceneState.selectEntity(map);
    expect(scope.tiles.mapEntityId.value, map.id);
    expect(scope.tiles.layerId.value, isNotNull);

    scope.tiles.reset();
    expect(scope.tiles.mapEntityId.value, isNull);
    // With only one map in the world, it is the one being painted anyway.
    expect(scope.tiles.target(world)?.entity, map);
  });
}
