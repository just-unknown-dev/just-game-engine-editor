// Tiles cut out of a map layer into a piece of the map: an entity under the
// Level Map, on the layer the tiles were on, drawing them exactly where they
// were — on every kind of map — as one undo step.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);

  late World world;
  late EditorScope scope;

  setUp(() {
    world = World()..initialize();
    scope = testScope(world: world);
    scope.sceneState.openScene(Scene(name: 'level'));
  });

  ({Entity map, LevelMapData data, MapLayerData layer}) level(
    LevelMapData data, {
    Offset at = Offset.zero,
  }) {
    final layer = data.addLayer(name: 'Ground');
    final map = world.createEntityWithComponents([
      TransformComponent(position: Vector3(at.dx, at.dy, 0)),
      LevelMapComponent(inline: data),
    ], name: LevelMaps.primaryName);
    scope.sceneState.registerEntity(map);
    return (map: map, data: data, layer: layer);
  }

  Offset origin(Entity e) {
    final p = e.getComponent<TransformComponent>()!.position;
    return Offset(p.x, p.y);
  }

  test('the tiles leave the layer for a piece of the map that draws them '
      'where they were; one undo puts them back', () {
    final (:map, :data, :layer) = level(
      LevelMapData(tileWidth: 32, tileHeight: 32)..addTileset('t.json'),
      at: const Offset(100, 50),
    );
    final a = TileCell.make(0, 1), b = TileCell.make(0, 2);
    final c = TileCell.make(0, 3, TileCell.flipH);
    layer.cells
      ..setCell(2, 1, a)
      ..setCell(3, 1, b)
      ..setCell(2, 2, c);
    final target = scope.mapDocs.resolve(map)!;
    final steps = scope.history.undoEntries.length;

    final piece = TilesToEntity.cut(scope, world, target, layer, {
      const TileCoord(2, 1),
      const TileCoord(3, 1),
      const TileCoord(2, 2),
      const TileCoord(5, 5),
    })!;
    expect(piece.name, startsWith('Tiles'));
    expect(LevelMaps.ownerOf(world, piece), same(map));
    expect(LevelMaps.memberLayer(world, piece), same(layer));
    expect(LevelMaps.isPiece(world, piece), isTrue);
    expect(origin(piece), const Offset(100 + 64, 50 + 32));
    final cut = piece.getComponent<LevelMapComponent>()!.inline!;
    expect(cut.tilesets, data.tilesets);
    final cells = cut.layers.single.cells;
    expect(
      (cells.cellAt(0, 0), cells.cellAt(1, 0), cells.cellAt(0, 1)),
      (a, b, c),
    );
    expect(layer.cells.usedBounds, isNull, reason: 'gone from the layer');
    expect(scope.history.undoEntries, hasLength(steps + 1));
    expect(scope.sceneState.selectedEntity.value, same(piece));
    expect(scope.tiles.selection.value, isEmpty);
    expect(
      scope.tiles.target(world)!.entity,
      same(map),
      reason: 'the tile tools stay on the Level Map',
    );

    scope.history.undo();
    expect(layer.cells.cellAt(3, 1), b);
    expect(world.findEntityByName(piece.name!), isNull);
    scope.history.redo();
    final again = world.findEntityByName(piece.name!)!;
    expect(LevelMaps.ownerOf(world, again), same(map));
    expect(layer.cells.usedBounds, isNull);
  });

  group('on every kind of map, every tile stays where it was', () {
    final kinds = {
      'isometric': LevelMapData(
        orientation: MapOrientation.isometric,
        tileWidth: 64,
        tileHeight: 32,
      ),
      'staggered, rows': LevelMapData(
        orientation: MapOrientation.staggered,
        tileWidth: 64,
        tileHeight: 32,
      ),
      'staggered, even rows shifted': LevelMapData(
        orientation: MapOrientation.staggered,
        staggerIndex: TileStaggerIndex.even,
        tileWidth: 64,
        tileHeight: 32,
      ),
      'hexagonal, columns': LevelMapData(
        orientation: MapOrientation.hexagonal,
        staggerAxis: TileStaggerAxis.x,
        hexSideLength: 16,
        tileWidth: 32,
        tileHeight: 32,
      ),
    };
    for (final MapEntry(key: kind, value: data) in kinds.entries) {
      test(kind, () {
        final (:map, data: _, :layer) = level(data, at: const Offset(7, 9));
        // An odd corner, in both directions.
        final chosen = {
          const TileCoord(3, 3),
          const TileCoord(4, 3),
          const TileCoord(3, 4),
          const TileCoord(5, 5),
        };
        for (final c in chosen) {
          layer.cells.setCell(c.x, c.y, TileCell.make(0, c.x + c.y));
        }
        final target = scope.mapDocs.resolve(map)!;
        final g = target.geometry;
        final before = {
          for (final c in chosen)
            layer.cells.cellAt(c.x, c.y): origin(map) + g.cellCenter(c.x, c.y),
        };

        final piece = TilesToEntity.cut(scope, world, target, layer, chosen)!;
        final cut = piece.getComponent<LevelMapComponent>()!.inline!;
        final pg = MapGeometry.of(cut);
        final after = {
          for (final (x, y, v) in cut.layers.single.cells.cells)
            v: origin(piece) + pg.cellCenter(x, y),
        };
        expect(after.keys.toSet(), before.keys.toSet());
        for (final value in before.keys) {
          expect(
            (after[value]! - before[value]!).distance,
            lessThan(1e-9),
            reason: 'tile $value',
          );
        }
      });
    }
  });

  test('a layer with parallax, a locked one, or a selection of no tiles is '
      'refused, and says why', () {
    final (:map, data: _, :layer) = level(LevelMapData());
    layer.cells.setCell(0, 0, TileCell.make(0, 1));
    final target = scope.mapDocs.resolve(map)!;
    final said = <String>[];

    expect(
      TilesToEntity.cut(scope, world, target, layer, {
        const TileCoord(4, 4),
      }, say: said.add),
      isNull,
    );
    layer.parallaxX = 0.5;
    expect(
      TilesToEntity.cut(scope, world, target, layer, {
        const TileCoord(0, 0),
      }, say: said.add),
      isNull,
    );
    layer
      ..parallaxX = 1
      ..locked = true;
    expect(
      TilesToEntity.cut(scope, world, target, layer, {
        const TileCoord(0, 0),
      }, say: said.add),
      isNull,
    );
    expect(said, [
      'The selection holds no tiles',
      contains('parallax'),
      contains('locked'),
    ]);
    expect(layer.cells.cellAt(0, 0), TileCell.make(0, 1));
  });
}
