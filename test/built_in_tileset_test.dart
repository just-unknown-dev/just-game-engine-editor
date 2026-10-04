// The engine's basic shapes tileset in the editor: no file, so nothing asks
// for one — the checks, the Tileset Editor and the Tiled export all know it
// is built in.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  test('the checks say nothing of a map painted with it', () {
    final world = World()..initialize();
    final scope = testScope(world: world);
    final map = LevelMapData()..addTileset(BuiltInTilesets.basicShapes);
    map.addLayer(name: 'Ground').cells.setCell(0, 0, TileCell.make(0, 23));
    world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: map),
    ], name: LevelMaps.primaryName);
    final looked = <String>[];
    final context = ValidationContext(
      scope: scope,
      fileExists: (path) {
        looked.add(path);
        return false;
      },
      readText: (path) {
        looked.add(path);
        return path == 'pubspec.yaml'
            ? 'flutter:\n  assets:\n    - assets/\n'
            : null;
      },
    );
    expect(BuiltInValidators.levelMaps(context), isEmpty);
    expect(BuiltInValidators.unshippedTileAssets(context), isEmpty);
    expect(
      looked.where((p) => p.startsWith(BuiltInTilesets.prefix)),
      isEmpty,
      reason: 'never looked for as a file',
    );
  });

  test('the Tileset Editor will not open it', () {
    expect(
      TilesetSession.open(BuiltInTilesets.basicShapes, root: '.'),
      throwsA(isA<StateError>()),
    );
  });

  test('exported for Tiled, its picture is written beside its .tsx', () async {
    final map = LevelMapData(tileWidth: 32, tileHeight: 32)
      ..addTileset(BuiltInTilesets.basicShapes);
    map.addLayer(name: 'Ground').cells.setCell(0, 0, TileCell.make(0, 0));
    final text = <String, String>{};
    final bytes = <String, List<int>>{};
    final tiles = EngineContext().tiles;
    addTearDown(tiles.dispose);
    final written =
        await TiledExporter(
          TiledFiles(
            root: '.',
            write: (path, t) async => text[path] = t,
            writeBytes: (path, b) async => bytes[path] = b,
          ),
        ).export(
          map,
          to: 'export/level.tmx',
          tilesetAt: (slot) => tiles.loadedTileset(map.tilesets[slot]!),
        );
    expect(written, [
      'export/basic_shapes.png',
      'export/basic_shapes.tsx',
      'export/level.tmx',
    ]);
    // A PNG: its signature.
    expect(bytes['export/basic_shapes.png']!.take(4), [0x89, 0x50, 0x4E, 0x47]);
    expect(
      text['export/basic_shapes.tsx'],
      contains('source="basic_shapes.png"'),
    );
  });
}
