// The tile tools, driven through a headless designer session: what a drag
// paints, fills, erases and selects, that each gesture is one undo step,
// and that all of it holds on every orientation of map.

import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/level_map/tile_edit_state.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/panels/level_layers_panel.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/tools/tiles/tile_brush_tools.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/tools/tiles/tile_tool_base.dart';

class _Keys {
  bool shift = false;
  bool control = false;
  bool alt = false;

  /// Ctrl on a Mac, the Windows key elsewhere: the one nothing is bound to.
  bool other = false;
  ModifierKeys read() =>
      ModifierKeys(shift: shift, control: control, alt: alt, other: other);
}

final int a = TileCell.make(0, 1);
final int b = TileCell.make(0, 2);
final int c3 = TileCell.make(0, 3);

void main() {
  late World world;
  late EditorScope scope;
  late _Keys keys;
  late LevelDesignerSession session;
  late Entity map;
  late LevelMapData data;

  TileEditState tiles() => scope.tiles;
  MapLayerData layer() => data.layers.last;
  MapGeometry geometry() => MapGeometry.of(data);
  int cell(int x, int y) => layer().cells.cellAt(x, y);
  String status() => session.controller.status.value;

  void useMap(LevelMapData d) {
    data = d;
    map = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: d),
    ], name: 'Map');
  }

  setUp(() {
    world = World()..initialize();
    scope = testScope(world: world);
    keys = _Keys();
    session = LevelDesignerSession(
      scope: scope,
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: keys.read,
    );
    addTearDown(session.dispose);
    useMap(BuiltInPrefabs.newLevelMap());
  });

  Offset at(TileCoord c) => geometry().cellCenter(c.x, c.y);

  void down(TileCoord c, {ToolButton button = ToolButton.primary}) =>
      session.onPointerDown(at(c), 32, button: button);
  void move(TileCoord c) => session.onPointerMove(at(c), 32);
  void up(TileCoord c) => session.onPointerUp(at(c), 32);
  void click(TileCoord c, {ToolButton button = ToolButton.primary}) {
    down(c, button: button);
    up(c);
  }

  void drag(
    TileCoord from,
    TileCoord to, {
    ToolButton button = ToolButton.primary,
  }) {
    down(from, button: button);
    move(to);
    up(to);
  }

  bool key(LogicalKeyboardKey k) => session.handleKey(k, gridSize: 32);

  void paint(Map<TileCoord, int> cells) {
    for (final e in cells.entries) {
      layer().cells.setCell(e.key.x, e.key.y, e.value);
    }
  }

  group('the Level Map, made on demand', () {
    setUp(() {
      world.destroyEntity(map);
      tiles().reset();
      session.setTool(TileTools.stamp);
      tiles().stamp.value = TileStamp.single(a);
    });

    List<Entity> maps() => world.query([LevelMapComponent]).toList();
    int at0(int x, int y) => maps().single
        .getComponent<LevelMapComponent>()!
        .inline!
        .layers
        .single
        .cells
        .cellAt(x, y);

    test('the first stroke makes it, and one undo takes the map and its '
        'tiles away', () {
      drag(const TileCoord(0, 0), const TileCoord(2, 0));
      expect(maps(), hasLength(1));
      expect(maps().single.name, LevelMaps.primaryName);
      expect(at0(2, 0), a);
      expect(scope.history.nextUndoLabel.value, 'Paint tiles');

      scope.history.undo();
      expect(maps(), isEmpty);
      scope.history.redo();
      expect(at0(1, 0), a, reason: 'made again as it was painted');
    });

    test('strokes after it still undo and redo once it is made again', () {
      click(const TileCoord(0, 0));
      tiles().stamp.value = TileStamp.single(b);
      click(const TileCoord(1, 0));
      scope.history
        ..undo()
        ..undo();
      expect(maps(), isEmpty);
      // Made again under a new id: the second stroke still finds it.
      scope.history
        ..redo()
        ..redo();
      expect(at0(0, 0), a);
      expect(at0(1, 0), b);
      scope.history.undo();
      expect(at0(1, 0), TileCell.empty);
      expect(at0(0, 0), a);
    });

    test('hovering, picking up and erasing never make one', () {
      session.onPointerHover(at(const TileCoord(2, 3)), 32);
      click(const TileCoord(2, 3), button: ToolButton.secondary);
      session.setTool(TileTools.erase);
      click(const TileCoord(2, 3));
      expect(maps(), isEmpty);
      expect(status(), contains('made when you first paint'));
    });

    test('a press that paints nothing leaves no map behind', () {
      session.setTool(TileTools.terrain);
      click(const TileCoord(0, 0));
      expect(maps(), isEmpty, reason: 'no terrain chosen');
      // A terrain the new map has no tileset for: nothing to paint.
      tiles().terrain.value = const TerrainChoice(slot: 0, set: 0, color: 1);
      click(const TileCoord(0, 0));
      expect(maps(), isEmpty);
      expect(scope.history.canUndo.value, isFalse);
    });

    test('Create Level Map makes it once; a second selects it', () {
      createLevelMap(session);
      expect(maps(), hasLength(1));
      createLevelMap(session);
      expect(maps(), hasLength(1));
      expect(scope.history.nextUndoLabel.value, 'Create Level Map');
      scope.history.undo();
      expect(maps(), isEmpty);
    });
  });

  group('stamp', () {
    setUp(() => session.setTool(TileTools.stamp));

    test('with nothing in the brush, says so and paints nothing', () {
      click(const TileCoord(0, 0));
      expect(cell(0, 0), TileCell.empty);
      expect(status(), contains('Pick a tile'));
    });

    test('a drag paints every cell it crosses, as one undo step', () {
      tiles().stamp.value = TileStamp.single(a);
      down(const TileCoord(0, 0));
      move(const TileCoord(5, 0)); // one big jump: no gaps
      up(const TileCoord(5, 0));
      for (var x = 0; x <= 5; x++) {
        expect(cell(x, 0), a, reason: 'cell $x');
      }
      expect(scope.sceneState.isDirty.value, isTrue);

      scope.history.undo();
      for (var x = 0; x <= 5; x++) {
        expect(cell(x, 0), TileCell.empty);
      }
    });

    test('a block lands around the pointer', () {
      tiles().stamp.value = TileStamp(
        [
          const StampCell(TileCoord(-1, 0), 0),
          StampCell(const TileCoord(0, 0), a),
          StampCell(const TileCoord(1, 0), b),
        ].where((s) => s.cell != 0).toList(),
      );
      click(const TileCoord(3, 2));
      expect(cell(3, 2), a);
      expect(cell(4, 2), b);
      expect(cell(2, 2), TileCell.empty);
    });

    test('hovering shows what a click would paint; leaving hides it', () {
      tiles().stamp.value = TileStamp.single(a);
      session.onPointerHover(at(const TileCoord(2, 3)), 32);
      expect(tiles().hoverCell, const TileCoord(2, 3));
      expect(tiles().preview, {const TileCoord(2, 3): a});
      session.onPointerExit();
      expect(tiles().preview, isEmpty);
      expect(tiles().hoverCell, isNull);
    });

    test('right-drag picks tiles up into the brush', () {
      paint({const TileCoord(0, 0): a, const TileCoord(1, 0): b});
      drag(
        const TileCoord(0, 0),
        const TileCoord(1, 0),
        button: ToolButton.secondary,
      );
      final stamp = tiles().stamp.value!;
      expect(stamp.cells.map((s) => s.cell), [a, b]);
      expect(tiles().dragArea, isNull);

      // Put down elsewhere, it is the same block.
      click(const TileCoord(5, 5));
      expect([cell(4, 5), cell(5, 5)], [a, b]);
    });

    test('Alt+click picks one tile; an empty cell makes an eraser', () {
      paint({const TileCoord(2, 2): b});
      keys.alt = true;
      click(const TileCoord(2, 2));
      expect(tiles().stamp.value!.cells.single.cell, b);
      click(const TileCoord(9, 9));
      keys.alt = false;
      expect(tiles().stamp.value!.cells.single.cell, TileCell.empty);
      expect(status(), contains('erases'));
    });

    test('X mirrors the brush, Z turns it, and the tiles with it', () {
      tiles().stamp.value = TileStamp([
        StampCell(const TileCoord(0, 0), a),
        StampCell(const TileCoord(1, 0), b),
      ]);
      session.onPointerHover(at(const TileCoord(4, 4)), 32);
      expect(key(LogicalKeyboardKey.keyX), isTrue);
      final mirrored = tiles().stamp.value!;
      expect(
        {for (final s in mirrored.cells) s.offset: s.cell},
        {
          const TileCoord(0, 0): TileCell.mirroredH(a),
          const TileCoord(-1, 0): TileCell.mirroredH(b),
        },
      );
      expect(tiles().preview.length, 2, reason: 'the preview follows');

      expect(key(LogicalKeyboardKey.keyZ), isTrue);
      final turned = tiles().stamp.value!;
      expect(turned.cells.map((s) => s.offset).toSet(), {
        const TileCoord(0, 0),
        const TileCoord(0, -1),
      });

      // Ctrl+Z is still undo, not a turn.
      keys.control = true;
      expect(key(LogicalKeyboardKey.keyZ), isFalse);
      // And a Mac's Ctrl+Z (Cmd is its shortcut key) is neither.
      keys
        ..control = false
        ..other = true;
      expect(key(LogicalKeyboardKey.keyZ), isFalse);
      expect(key(LogicalKeyboardKey.keyX), isFalse);
      expect(tiles().stamp.value, same(turned), reason: 'the brush as it was');
    });

    test('random mode paints one of the brush\'s tiles per cell', () {
      tiles()
        ..stamp.value = TileStamp([
          StampCell(const TileCoord(0, 0), a),
          StampCell(const TileCoord(1, 0), b),
        ])
        ..random.value = true;
      drag(const TileCoord(0, 0), const TileCoord(20, 0));
      final seen = {for (var x = 0; x <= 21; x++) cell(x, 0)}
        ..remove(TileCell.empty);
      expect(seen, {a, b});
    });

    test('a locked layer refuses paint but still lets tiles be picked', () {
      paint({const TileCoord(0, 0): b});
      layer().locked = true;
      tiles().stamp.value = TileStamp.single(a);
      click(const TileCoord(3, 3));
      expect(cell(3, 3), TileCell.empty);
      expect(status(), contains('locked'));

      click(const TileCoord(0, 0), button: ToolButton.secondary);
      expect(tiles().stamp.value!.cells.single.cell, b);
    });
  });

  group('erase', () {
    setUp(() => session.setTool(TileTools.erase));

    test('clears as wide as the brush size, as one step', () {
      paint({
        for (var y = 0; y < 5; y++)
          for (var x = 0; x < 5; x++) TileCoord(x, y): a,
      });
      session.controller.brushSize.value = 3;
      click(const TileCoord(2, 2));
      var cleared = 0;
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          if (cell(x, y) == TileCell.empty) cleared++;
        }
      }
      expect(cleared, 9);
      expect(cell(0, 0), a);
      scope.history.undo();
      expect(cell(2, 2), a);
    });

    test('picking up a tile goes back to the stamp', () {
      paint({const TileCoord(1, 1): a});
      click(const TileCoord(1, 1), button: ToolButton.secondary);
      expect(session.controller.toolId.value, TileTools.stamp);
    });

    test('a hexagonal eraser is a hexagon', () {
      final hex = MapGeometry.of(
        LevelMapData(orientation: MapOrientation.hexagonal, hexSideLength: 16),
      );
      expect(
        TileEraseTool.brushCells(hex, const TileCoord(4, 4), 3),
        hasLength(7),
      );
      expect(
        TileEraseTool.brushCells(geometry(), const TileCoord(4, 4), 3),
        hasLength(9),
      );
    });
  });

  group('fill', () {
    setUp(() {
      session.setTool(TileTools.fill);
      tiles().stamp.value = TileStamp.single(b);
    });

    test('the bucket fills the connected run of the tile clicked', () {
      paint({
        for (var x = 0; x < 5; x++) TileCoord(x, 0): a,
        const TileCoord(7, 0): a,
      });
      click(const TileCoord(2, 0));
      expect([for (var x = 0; x < 5; x++) cell(x, 0)], everyElement(b));
      expect(cell(7, 0), a, reason: 'not joined to the run');
      expect(cell(5, 0), TileCell.empty);
      scope.history.undo();
      expect(cell(2, 0), a);
    });

    test('on open ground the bucket stops at the edge of what is there', () {
      paint({const TileCoord(0, 0): a});
      click(const TileCoord(3, 3));
      // Without a camera: 64 cells around the origin, and past what is painted.
      expect(cell(3, 3), b);
      expect(cell(64, 64), b);
      expect(cell(66, 66), TileCell.empty);
    });

    test('G cycles bucket, rectangle and ellipse', () {
      expect(key(LogicalKeyboardKey.keyG), isTrue);
      expect(tiles().fillShape.value, TileFillShape.rect);
      key(LogicalKeyboardKey.keyG);
      expect(tiles().fillShape.value, TileFillShape.ellipse);
      key(LogicalKeyboardKey.keyG);
      expect(tiles().fillShape.value, TileFillShape.bucket);
      expect(session.controller.toolId.value, TileTools.fill);
    });

    test('a rectangle previews while dragged and fills on release', () {
      tiles().fillShape.value = TileFillShape.rect;
      down(const TileCoord(0, 0));
      move(const TileCoord(2, 1));
      expect(tiles().preview, hasLength(6));
      expect(cell(0, 0), TileCell.empty, reason: 'nothing yet');
      up(const TileCoord(2, 1));
      expect(tiles().preview, isEmpty);
      expect([
        for (var y = 0; y < 2; y++)
          for (var x = 0; x < 3; x++) cell(x, y),
      ], everyElement(b));
      scope.history.undo();
      expect(cell(1, 1), TileCell.empty);
    });

    test('an ellipse leaves the corners of its box', () {
      tiles().fillShape.value = TileFillShape.ellipse;
      drag(const TileCoord(0, 0), const TileCoord(4, 4));
      expect(cell(2, 2), b);
      expect(cell(2, 0), b);
      expect(cell(0, 0), TileCell.empty);
      expect(cell(4, 4), TileCell.empty);
    });

    test('a block repeats as a pattern', () {
      tiles()
        ..fillShape.value = TileFillShape.rect
        ..stamp.value = TileStamp.capture(
          (TileChunkStore()
            ..setCell(0, 0, a)
            ..setCell(1, 0, c3)),
          const [TileCoord(0, 0), TileCoord(1, 0)],
          geometry(),
        );
      drag(const TileCoord(0, 0), const TileCoord(3, 0));
      expect([for (var x = 0; x < 4; x++) cell(x, 0)], [a, c3, a, c3]);
    });
  });

  group('select', () {
    setUp(() => session.setTool(TileTools.select));

    Set<TileCoord> selected() => tiles().selection.value;

    test('a box selects; Shift adds; Ctrl takes away', () {
      drag(const TileCoord(0, 0), const TileCoord(1, 1));
      expect(selected(), hasLength(4));
      keys.shift = true;
      drag(const TileCoord(5, 5), const TileCoord(5, 5));
      expect(selected(), hasLength(5));
      keys
        ..shift = false
        ..control = true;
      drag(const TileCoord(0, 0), const TileCoord(1, 0));
      expect(selected(), {
        const TileCoord(0, 1),
        const TileCoord(1, 1),
        const TileCoord(5, 5),
      });
    });

    test('V cycles box, wand and same tile', () {
      paint({
        const TileCoord(0, 0): a,
        const TileCoord(1, 0): a,
        const TileCoord(3, 0): a,
        const TileCoord(2, 0): b,
      });
      expect(key(LogicalKeyboardKey.keyV), isTrue);
      expect(tiles().selectMode.value, TileSelectMode.wand);
      click(const TileCoord(0, 0));
      expect(selected(), {const TileCoord(0, 0), const TileCoord(1, 0)});

      key(LogicalKeyboardKey.keyV);
      expect(tiles().selectMode.value, TileSelectMode.sameTile);
      click(const TileCoord(3, 0));
      expect(selected(), {
        const TileCoord(0, 0),
        const TileCoord(1, 0),
        const TileCoord(3, 0),
      });
    });

    test('Ctrl+A selects every painted cell; Esc lets go', () {
      paint({const TileCoord(0, 0): a, const TileCoord(9, 3): b});
      keys.control = true;
      expect(key(LogicalKeyboardKey.keyA), isTrue);
      keys.control = false;
      expect(selected(), {const TileCoord(0, 0), const TileCoord(9, 3)});
      expect(key(LogicalKeyboardKey.escape), isTrue);
      expect(selected(), isEmpty);
      // With nothing to let go of, Esc is the designer's again.
      expect(
        session.controller.activeTool!.onKey(
          LogicalKeyboardKey.escape,
          ToolContext(
            world: world,
            controller: session.controller,
            worldPosition: Offset.zero,
            gridSize: 32,
          ),
        ),
        isFalse,
      );
    });

    test('Ctrl+C then Ctrl+V puts the tiles in the stamp tool\'s brush', () {
      paint({const TileCoord(0, 0): a, const TileCoord(1, 0): b});
      drag(const TileCoord(0, 0), const TileCoord(1, 0));
      keys.control = true;
      expect(key(LogicalKeyboardKey.keyC), isTrue);
      expect(tiles().clipboard!.cells, hasLength(2));
      expect(key(LogicalKeyboardKey.keyV), isTrue);
      keys.control = false;
      expect(session.controller.toolId.value, TileTools.stamp);
      click(const TileCoord(5, 5));
      expect([cell(4, 5), cell(5, 5)], [a, b]);
    });

    test('Ctrl+X cuts; Delete clears; each is one step', () {
      paint({const TileCoord(0, 0): a, const TileCoord(1, 0): b});
      drag(const TileCoord(0, 0), const TileCoord(1, 0));
      keys.control = true;
      key(LogicalKeyboardKey.keyX);
      keys.control = false;
      expect([cell(0, 0), cell(1, 0)], everyElement(TileCell.empty));
      expect(tiles().clipboard, isNotNull);
      scope.history.undo();
      expect([cell(0, 0), cell(1, 0)], [a, b]);

      expect(key(LogicalKeyboardKey.delete), isTrue);
      expect(cell(0, 0), TileCell.empty);
      scope.history.undo();
      expect(cell(0, 0), a);
    });

    test('Delete with nothing selected leaves the map entity alone', () {
      scope.sceneState.selectedEntity.value = map;
      expect(key(LogicalKeyboardKey.delete), isTrue);
      expect(map.isAlive, isTrue);
    });

    test('dragging the selection moves its tiles, as one step', () {
      paint({
        const TileCoord(0, 0): a,
        const TileCoord(1, 0): b,
        const TileCoord(0, 2): c3,
      });
      drag(const TileCoord(0, 0), const TileCoord(1, 0));
      down(const TileCoord(0, 0));
      expect(cell(0, 0), TileCell.empty, reason: 'lifted');
      expect(tiles().floating, hasLength(2));
      move(const TileCoord(0, 2));
      up(const TileCoord(0, 2));

      expect([cell(0, 2), cell(1, 2)], [a, b]);
      expect([cell(0, 0), cell(1, 0)], everyElement(TileCell.empty));
      expect(selected(), {const TileCoord(0, 2), const TileCoord(1, 2)});
      expect(tiles().floating, isEmpty);

      scope.history.undo();
      expect([cell(0, 0), cell(1, 0), cell(0, 2)], [a, b, c3]);
    });

    test('a click inside the selection lets go of it and changes nothing', () {
      paint({const TileCoord(0, 0): a});
      drag(const TileCoord(0, 0), const TileCoord(1, 0));
      final steps = scope.history.undoDepth;
      click(const TileCoord(0, 0));
      expect(cell(0, 0), a);
      expect(selected(), isEmpty);
      expect(scope.history.undoDepth, steps);
    });

    test('Ctrl+Shift chords are left to the docks', () {
      keys
        ..control = true
        ..shift = true;
      expect(key(LogicalKeyboardKey.keyA), isFalse);
    });

    test('a selection belongs to its layer', () {
      drag(const TileCoord(0, 0), const TileCoord(1, 0));
      final other = data.addLayer(name: 'Top');
      tiles().layerId.value = other.id;
      expect(selected(), isEmpty);
    });
  });

  group('every orientation', () {
    final maps = <String, LevelMapData Function()>{
      'orthogonal': () => LevelMapData(),
      'isometric': () => LevelMapData(
        orientation: MapOrientation.isometric,
        tileWidth: 64,
        tileHeight: 32,
      ),
      'staggered': () => LevelMapData(
        orientation: MapOrientation.staggered,
        tileWidth: 64,
        tileHeight: 32,
      ),
      'hexagonal': () => LevelMapData(
        orientation: MapOrientation.hexagonal,
        tileWidth: 32,
        tileHeight: 28,
        hexSideLength: 16,
        staggerAxis: TileStaggerAxis.x,
      ),
    };

    for (final entry in maps.entries) {
      group(entry.key, () {
        setUp(() {
          world.destroyEntity(map);
          final d = entry.value();
          d.addLayer(name: 'Ground');
          useMap(d);
        });

        test('a click paints the cell under it', () {
          session.setTool(TileTools.stamp);
          tiles().stamp.value = TileStamp.single(a);
          for (final c in const [
            TileCoord(0, 0),
            TileCoord(3, 1),
            TileCoord(-2, 5),
          ]) {
            click(c);
            expect(cell(c.x, c.y), a, reason: '$c');
          }
          expect(layer().cells.cells.length, 3);
        });

        test('a drag leaves an unbroken line', () {
          session.setTool(TileTools.stamp);
          tiles().stamp.value = TileStamp.single(a);
          drag(const TileCoord(0, 0), const TileCoord(6, 4));
          final painted = {
            for (final (x, y, _) in layer().cells.cells) TileCoord(x, y),
          };
          expect(
            painted,
            containsAll(const [TileCoord(0, 0), TileCoord(6, 4)]),
          );
          // Every painted cell touches another.
          final g = geometry();
          for (final p in painted) {
            final touching = g.neighbours(p).where(painted.contains).length;
            final corner = painted.any(
              (q) =>
                  q != p &&
                  (g.cellCenter(q.x, q.y) - g.cellCenter(p.x, p.y)).distance <
                      1.6 * g.tileWidth,
            );
            expect(touching > 0 || corner, isTrue, reason: '$p is alone');
          }
        });

        test('a moved block keeps its shape', () {
          final g = geometry();
          final block = [
            const TileCoord(2, 2),
            g.neighbours(const TileCoord(2, 2)).first,
          ];
          paint({block[0]: a, block[1]: b});
          session.setTool(TileTools.select);
          keys.shift = true;
          for (final c in block) {
            click(c);
          }
          keys.shift = false;
          expect(tiles().selection.value, block.toSet());

          final to = const TileCoord(5, 6);
          drag(block[0], to);
          final delta = TileCoord(
            g.toStable(to).x - g.toStable(block[0]).x,
            g.toStable(to).y - g.toStable(block[0]).y,
          );
          TileCoord moved(TileCoord c) {
            final s = g.toStable(c);
            return g.fromStable(TileCoord(s.x + delta.x, s.y + delta.y));
          }

          expect(cell(to.x, to.y), a);
          final other = moved(block[1]);
          expect(cell(other.x, other.y), b);
          expect(
            g.neighbours(to),
            contains(other),
            reason: 'still side by side',
          );
        });

        test('the overlays draw everything a tool shows', () {
          world.context.tiles.putTileset(
            't.tileset.json',
            TilesetData(
                name: 't',
                image: '',
                tileWidth: data.tileWidth,
                tileHeight: data.tileHeight,
                columns: 4,
                tileCount: 4,
              )
              ..tileOrNew(1).collision = TileCollision.full(
                data.tileWidth.toDouble(),
                data.tileHeight.toDouble(),
              ),
          );
          data.addTileset('t.tileset.json');
          layer().collides = true;
          final top = data.addLayer(name: 'Top');
          data.layers.first.cells
            ..setCell(0, 0, a)
            ..setCell(1, 1, a);
          registerLevelMapSystems(world);
          world.update(0);
          expect(map.getComponent<LevelMapComponent>()!.runtime, isNotNull);

          session.setTool(TileTools.select);
          tiles()
            ..layerId.value = top.id
            ..showCollision.value = true
            ..highlightLayer.value = true
            ..selection.value = {const TileCoord(0, 0), const TileCoord(1, 0)}
            ..preview = {
              const TileCoord(3, 3): a,
              const TileCoord(4, 3): TileCell.empty,
            }
            ..dragArea = (const TileCoord(0, 0), const TileCoord(2, 2))
            ..floating = {const TileCoord(0, 0): TileCell.mirroredH(a)}
            ..floatOffset = const TileCoord(1, 1)
            ..hoverCell = const TileCoord(2, 2);
          session.camera.viewportSize = const Size(800, 600);
          final recorder = PictureRecorder();
          session.paint(Canvas(recorder), const Size(800, 600), session.camera);
          recorder.endRecording().dispose();

          tiles().syncHighlight(world, active: true);
          final runtime = map.getComponent<LevelMapComponent>()!.runtime!;
          expect(runtime.layerAlpha, {data.layers.first.id: 0.3});
          tiles().syncHighlight(world, active: false);
          expect(runtime.layerAlpha, isEmpty);
        });

        test('the bucket follows the map\'s own neighbours', () {
          final g = geometry();
          final centre = const TileCoord(3, 3);
          paint({centre: a, for (final n in g.neighbours(centre)) n: a});
          session.setTool(TileTools.fill);
          tiles().stamp.value = TileStamp.single(b);
          click(centre);
          expect(
            layer().cells.cells.where((c) => c.$3 == b).length,
            g.neighbours(centre).length + 1,
          );
        });
      });
    }
  });

  test('choosing a layer paints it and places at its depth (LD-32)', () {
    final chosen = data.layers.first;
    tiles().selectLayer(chosen, controller: session.controller);
    expect(tiles().layerId.value, chosen.id);
    expect(session.controller.activeLayerId.value, chosen.sortLayerId);
  });
}
