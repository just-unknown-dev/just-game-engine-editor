// Map files are shared between scenes, so the editor never writes one it was
// not asked to: "Move to a file" will not go over another scene's map, a
// map edit discarded with its scene stays discarded, a save that cannot
// write a map says so and keeps it unsaved, and an undo step whose map is
// gone does nothing rather than painting another map.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/level_map/level_map_documents.dart';
import 'package:just_game_engine_editor/src/core/level_map/tile_commands.dart';

void main() {
  late Directory project;
  late EditorScope scope;
  late LevelMapDocuments docs;

  World world() => scope.world;

  Entity newMap({String name = 'Level Map'}) {
    final data = LevelMapData(tileWidth: 16, tileHeight: 16)
      ..addTileset('assets/tilesets/grass.tileset.json')
      ..addLayer(name: 'Ground');
    return world().createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: data),
    ], name: name);
  }

  setUp(() {
    project = Directory.systemTemp.createTempSync('map_files_safety');
    scope = testScope();
    scope.sceneState.openScene(EditorScene(name: 'level_02'));
    docs = LevelMapDocuments(
      world: world,
      sceneState: scope.sceneState,
      projectRoot: project.path,
    );
    addTearDown(docs.dispose);
  });

  tearDown(() {
    try {
      project.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may hold it a moment longer.
    }
  });

  File file(String path) => File('${project.path}/$path');

  group('Move to a file (EC-3)', () {
    test('never over a map that is there: it is refused', () async {
      const path = 'assets/maps/level map.map.json';
      file(path)
        ..createSync(recursive: true)
        ..writeAsStringSync('level_01 map');
      final map = newMap();
      await expectLater(
        docs.extractToAsset(map, path),
        throwsA(isA<FileSystemException>()),
      );
      expect(file(path).readAsStringSync(), 'level_01 map');
      expect(map.getComponent<LevelMapComponent>()!.usesFile, isFalse);
    });

    test('a path that leaves the project is refused', () async {
      await expectLater(
        docs.extractToAsset(newMap(), '../outside.map.json'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the name offered is safe and free', () {
      file('assets/maps/level_02_map.map.json').createSync(recursive: true);
      expect(
        docs.freeMapPath('assets/maps', 'level_02 map'),
        'assets/maps/level_02_map_2.map.json',
      );
      expect(
        docs.freeMapPath('assets/maps', '../../evil:name'),
        'assets/maps/evil_name.map.json',
      );
    });
  });

  group('saving map files (EC-33)', () {
    test(
      'one that cannot be written stays unsaved; the rest are written',
      () async {
        final good = LevelMapData()..addLayer(name: 'A');
        final bad = LevelMapData()..addLayer(name: 'B');
        scope.context.tiles
          ..putMap('assets/maps/good.map.json', good)
          ..putMap('assets/maps/bad.map.json', bad);
        // A folder where the file would go: it cannot be written.
        Directory(
          '${project.path}/assets/maps/bad.map.json',
        ).createSync(recursive: true);
        docs
          ..markEdited(
            const LevelMapRef(entityId: 0, path: 'assets/maps/good.map.json'),
          )
          ..markEdited(
            const LevelMapRef(entityId: 0, path: 'assets/maps/bad.map.json'),
          );

        final failed = await docs.saveDirty();

        expect(failed.keys, ['assets/maps/bad.map.json']);
        expect(docs.dirtyPaths.value, {'assets/maps/bad.map.json'});
        expect(file('assets/maps/good.map.json').existsSync(), isTrue);
        expect(
          Directory(
            '${project.path}/assets/maps',
          ).listSync().where((e) => e.path.endsWith('.saving')),
          isEmpty,
          reason: 'no half-written file is left',
        );
      },
    );

    test('an edit made while it was written stays unsaved', () async {
      final data = LevelMapData()..addLayer(name: 'A');
      const path = 'assets/maps/live.map.json';
      scope.context.tiles.putMap(path, data);
      docs.markEdited(const LevelMapRef(entityId: 0, path: path));
      final saving = docs.saveDirty();
      data.touch(); // an edit arrives before the write is done
      expect(await saving, isEmpty);
      expect(docs.dirtyPaths.value, {path});
    });
  });

  group('edits not saved (EC-4)', () {
    test(
      'discarded: read from disk again, not written by the next save',
      () async {
        const path = 'assets/maps/shared.map.json';
        file(path)
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode(LevelMapData().toJson()));
        final edited = LevelMapData()..addLayer(name: 'Discarded');
        scope.context.tiles.putMap(path, edited);
        docs.markEdited(const LevelMapRef(entityId: 0, path: path));

        docs.discardUnsaved();

        expect(docs.hasDirty, isFalse);
        expect(scope.context.tiles.loadedMap(path), isNull);
        expect(await docs.saveDirty(), isEmpty);
        expect(
          LevelMapData.fromJson(
            jsonDecode(file(path).readAsStringSync()) as Map<String, dynamic>,
          ).layers,
          isEmpty,
          reason: 'the file is as it was',
        );
      },
    );
  });

  group('undo of a map that is gone (EC-36)', () {
    test('does nothing rather than painting another map', () {
      final first = newMap();
      final second = newMap(name: 'Second map');
      final ref = docs.resolve(second)!.ref;
      final layerId = docs.resolve(second)!.data.layers.single.id;
      final stroke = TileStroke(
        docs: docs,
        ref: ref,
        layer: docs.resolve(second)!.data.layers.single,
      )..set(const TileCoord(1, 1), TileCell.make(0, 3));
      final command = stroke.finish('Paint')!;
      world().destroyEntity(second);

      command.undo();
      command.redo();

      final primary = first.getComponent<LevelMapComponent>()!.inline!;
      expect(primary.layerById(layerId)?.cells.cellAt(1, 1) ?? 0, 0);
    });

    test('finds its map by name when it was made again under a new id', () {
      final map = newMap();
      final ref = docs.resolve(map)!.ref;
      world().destroyEntity(map);
      final again = newMap();
      expect(
        docs.dataFor(ref),
        same(again.getComponent<LevelMapComponent>()!.inline),
      );
    });
  });

  group('a map\'s shape, recorded (EC-28)', () {
    test(
      'settings and layer settings come back; cells are left as they are',
      () {
        final map = LevelMapData(tileWidth: 16, tileHeight: 16)
          ..addTileset('assets/tilesets/a.tileset.json');
        final layer = map.addLayer(name: 'Ground')..opacity = 0.5;
        layer.properties.set('ambient', 'wind');
        final shape = MapStructure.capture(map);

        map.tileWidth = 32;
        map.tilesets.add('assets/tilesets/b.tileset.json');
        layer
          ..name = 'Renamed'
          ..opacity = 1;
        layer.properties.set('ambient', 'rain');
        layer.cells.setCell(0, 0, TileCell.make(0, 1));
        shape.restoreInto(map);

        expect(map.tileWidth, 16);
        expect(map.tilesets, ['assets/tilesets/a.tileset.json']);
        expect(layer.name, 'Ground');
        expect(layer.opacity, 0.5);
        expect(layer.properties['ambient'], 'wind');
        expect(layer.cells.cellAt(0, 0), TileCell.make(0, 1));

        // What is edited after a restore is not the recorded shape.
        layer.properties.set('ambient', 'snow');
        shape.restoreInto(map);
        expect(layer.properties['ambient'], 'wind');
      },
    );
  });
}
