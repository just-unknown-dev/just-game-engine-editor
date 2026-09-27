// Terrains: defining them in the Tileset Editor, and painting them with
// the terrain tool so the tiles around a stroke join it — on every map
// that has square-cornered cells, and a clear refusal on the one that
// does not.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

const _path = 'assets/tilesets/terrain.tileset.json';

/// 16 tiles of 16 px, 4 wide, laid out as the 16-corner template: colour 1
/// grass, colour 2 dirt. Tile 0 is all dirt, tile 15 all grass.
TilesetData _terrainTileset() {
  final ts = TilesetData.fromImage(
    name: 'terrain',
    image: '',
    imageWidth: 64,
    imageHeight: 64,
    tileWidth: 16,
    tileHeight: 16,
  );
  final set = WangSetData(
    name: 'Ground',
    colors: [
      WangColorData(name: 'Grass', color: 0xFF4CAF50),
      WangColorData(name: 'Dirt', color: 0xFF8D6E63),
    ],
  );
  WangTemplate.corner16.applyTo(set, firstTile: 0, tilesetColumns: 4);
  ts.wangSets.add(set);
  return ts;
}

ui.Image _image(int w, int h) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF3A7D44),
  );
  return recorder.endRecording().toImageSync(w, h);
}

void main() {
  setUpAll(registerCoreCodecs);

  group('the tileset\'s terrains', () {
    TilesetSession session() => TilesetSession(
      TilesetData.fromImage(
        name: 't',
        image: '',
        imageWidth: 64,
        imageHeight: 64,
        tileWidth: 16,
        tileHeight: 16,
      ),
      path: _path,
      root: '.',
      loadImage: (_) async => _image(64, 64),
      writeText: (_, _) async {},
    );

    test('sets and terrains are added, painted and removed', () {
      final s = session();
      addTearDown(s.dispose);
      final set = s.addWangSet(name: 'Ground');
      expect(s.data.wangSets.single.colors, hasLength(1));
      final dirt = s.addWangColor(set);
      expect(dirt, 2);

      s.setWangSlot(set, 5, WangSetData.topLeft, 1);
      s.setWangSlot(set, 5, WangSetData.topRight, 2);
      expect(s.data.wangSets[set].wangIds[5], [0, 2, 0, 0, 0, 0, 0, 1]);

      // Taking terrain 1 away: its corners go, the ones after move down.
      s.removeWangColor(set, 1);
      expect(s.data.wangSets[set].wangIds[5], [0, 1, 0, 0, 0, 0, 0, 0]);
      expect(s.data.wangSets[set].colors.single.name, 'Terrain 2');

      s.undo();
      expect(s.data.wangSets[set].wangIds[5], [0, 2, 0, 0, 0, 0, 0, 1]);
    });

    test('turning a corner set into an edge set drops its corners', () {
      final s = session();
      addTearDown(s.dispose);
      final set = s.addWangSet();
      s.setWangSlot(set, 1, WangSetData.topLeft, 1);
      s.setWangSlot(set, 2, WangSetData.top, 1);
      s.setWangType(set, WangType.edge);
      final ids = s.data.wangSets[set].wangIds;
      expect(ids.containsKey(1), isFalse, reason: 'it had only a corner');
      expect(ids[2], [1, 0, 0, 0, 0, 0, 0, 0]);
    });

    test('a template fills a set in one step, and coverage says so', () {
      final s = session();
      addTearDown(s.dispose);
      final set = s.addWangSet();
      s.applyTemplate(set, WangTemplate.corner16, 0);
      expect(s.data.wangSets[set].wangIds, hasLength(16));
      final c = s.coverage(set);
      expect((c.tiles, c.combinations, c.possible), (16, 16, 16));

      s.setWangSlot(set, 3, WangSetData.topLeft, 0);
      s.setWangSlot(set, 3, WangSetData.topRight, 0);
      s.setWangSlot(set, 3, WangSetData.bottomLeft, 0);
      s.setWangSlot(set, 3, WangSetData.bottomRight, 0);
      expect(s.coverage(set).combinations, 15);

      s.undo();
      s.undo();
      s.undo();
      s.undo();
      s.undo();
      expect(s.data.wangSets[set].wangIds, isEmpty);
    });

    test('a click in a tile lands on its nearest corner or edge', () {
      expect(
        wangSlotAt(const Offset(2, 3), 16, 16, WangType.corner),
        WangSetData.topLeft,
      );
      expect(
        wangSlotAt(const Offset(15, 14), 16, 16, WangType.corner),
        WangSetData.bottomRight,
      );
      expect(
        wangSlotAt(const Offset(15, 7), 16, 16, WangType.edge),
        WangSetData.right,
      );
      expect(
        wangSlotAt(const Offset(2, 8), 16, 16, WangType.mixed),
        WangSetData.left,
      );
      expect(
        wangSlotAt(const Offset(1, 1), 16, 16, WangType.mixed),
        WangSetData.topLeft,
      );
    });
  });

  group('the terrain tool', () {
    late World world;
    late EditorScope scope;
    late LevelDesignerSession session;
    late LevelMapData data;
    final wang = _terrainTileset().wangSets.single;

    setUp(() {
      TileAssets.clear();
      TileAssets.putTileset(_path, _terrainTileset());
      world = World()..initialize();
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
    });

    void useMap(LevelMapData d) {
      data = d..addTileset(_path);
      d.addLayer(name: 'Ground');
      world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: d),
      ], name: 'Map');
    }

    MapGeometry g() => MapGeometry.of(data);
    TileChunkStore cells() => data.layers.single.cells;

    /// All dirt, 8 × 8 on the lattice.
    void dirt() {
      for (var v = -1; v < 7; v++) {
        for (var u = -1; u < 7; u++) {
          final c = g().fromLattice(TileCoord(u, v));
          cells().setCell(c.x, c.y, TileCell.make(0, 0));
        }
      }
    }

    List<int> idAt(TileCoord lattice) {
      final c = g().fromLattice(lattice);
      return wang.wangIds[TileCell.localIdOf(cells().cellAt(c.x, c.y))]!;
    }

    final maps = <String, LevelMapData Function()>{
      'orthogonal': () => LevelMapData(tileWidth: 16, tileHeight: 16),
      'isometric': () => LevelMapData(
        orientation: MapOrientation.isometric,
        tileWidth: 32,
        tileHeight: 16,
      ),
      'staggered': () => LevelMapData(
        orientation: MapOrientation.staggered,
        tileWidth: 32,
        tileHeight: 16,
      ),
    };

    for (final entry in maps.entries) {
      test('on ${entry.key} maps, a corner painted turns the four cells '
          'around it, as one step', () {
        useMap(entry.value());
        dirt();
        session.setTool(TileTools.terrain);
        scope.tiles.terrain.value = const TerrainChoice(
          slot: 0,
          set: 0,
          color: 1,
        );

        // Just inside the top-left corner of the cell at lattice (3, 3).
        final cell = g().fromLattice(const TileCoord(3, 3));
        final poly = g().cellPolygon(cell.x, cell.y);
        final centre = g().cellCenter(cell.x, cell.y);
        final at = Offset.lerp(poly[0], centre, 0.1)!;
        session.onPointerDown(at, 16);
        session.onPointerUp(at, 16);

        expect(idAt(const TileCoord(3, 3))[WangSetData.topLeft], 1);
        expect(idAt(const TileCoord(2, 3))[WangSetData.topRight], 1);
        expect(idAt(const TileCoord(2, 2))[WangSetData.bottomRight], 1);
        expect(idAt(const TileCoord(3, 2))[WangSetData.bottomLeft], 1);
        // Everything else is still dirt.
        final changed = [
          for (final (x, y, v) in cells().cells)
            if (v != TileCell.make(0, 0)) TileCoord(x, y),
        ];
        expect(changed, hasLength(4));

        scope.history.undo();
        expect(cells().cells.every((c) => c.$3 == TileCell.make(0, 0)), isTrue);
      });
    }

    test('hovering shows the stroke before it is made', () {
      useMap(LevelMapData(tileWidth: 16, tileHeight: 16));
      dirt();
      session.setTool(TileTools.terrain);
      scope.tiles.terrain.value = const TerrainChoice(
        slot: 0,
        set: 0,
        color: 1,
      );
      session.onPointerHover(const Offset(33, 33), 16);
      expect(scope.tiles.preview, hasLength(4));
      expect(cells().cellAt(2, 2), TileCell.make(0, 0), reason: 'only shown');
    });

    test('a drag paints every corner it passes', () {
      useMap(LevelMapData(tileWidth: 16, tileHeight: 16));
      dirt();
      session.setTool(TileTools.terrain);
      scope.tiles.terrain.value = const TerrainChoice(
        slot: 0,
        set: 0,
        color: 1,
      );
      session.onPointerDown(const Offset(17, 17), 16);
      session.onPointerMove(const Offset(79, 17), 16);
      session.onPointerUp(const Offset(79, 17), 16);
      // Corners (1,1) to (5,1): the tops of row 1 are all grass.
      for (var x = 1; x <= 4; x++) {
        final id = wang.wangIds[TileCell.localIdOf(cells().cellAt(x, 1))]!;
        expect(id[WangSetData.topLeft], 1, reason: 'cell $x');
        expect(id[WangSetData.topRight], 1, reason: 'cell $x');
      }
      scope.history.undo();
      expect(cells().cellAt(2, 1), TileCell.make(0, 0), reason: 'one step');
    });

    test('right-click takes the terrain under the pointer', () {
      useMap(LevelMapData(tileWidth: 16, tileHeight: 16));
      // Tile 1: grass at the top-left corner only.
      cells().setCell(0, 0, TileCell.make(0, 1));
      session.setTool(TileTools.terrain);
      session.onPointerDown(
        const Offset(2, 2),
        16,
        button: ToolButton.secondary,
      );
      session.onPointerUp(const Offset(2, 2), 16);
      expect(
        scope.tiles.terrain.value,
        const TerrainChoice(slot: 0, set: 0, color: 1),
      );
      session.onPointerDown(
        const Offset(14, 14),
        16,
        button: ToolButton.secondary,
      );
      session.onPointerUp(const Offset(14, 14), 16);
      expect(scope.tiles.terrain.value!.color, 2);
      expect(session.controller.status.value, contains('Dirt'));
    });

    test('without a terrain chosen, it says where to choose one', () {
      useMap(LevelMapData(tileWidth: 16, tileHeight: 16));
      session.setTool(TileTools.terrain);
      session.onPointerDown(const Offset(8, 8), 16);
      session.onPointerUp(const Offset(8, 8), 16);
      expect(session.controller.status.value, contains('Terrains'));
      expect(cells().cells, isEmpty);
    });

    test('a hexagonal map is refused, with the reason', () {
      useMap(
        LevelMapData(
          orientation: MapOrientation.hexagonal,
          tileWidth: 32,
          tileHeight: 28,
          hexSideLength: 16,
        ),
      );
      session.setTool(TileTools.terrain);
      scope.tiles.terrain.value = const TerrainChoice(
        slot: 0,
        set: 0,
        color: 1,
      );
      session.onPointerDown(const Offset(40, 40), 16);
      session.onPointerUp(const Offset(40, 40), 16);
      expect(session.controller.status.value, contains('hexagonal'));
      expect(cells().cells, isEmpty);
    });

    testWidgets('the Tileset panel lists terrains; choosing one takes up '
        'the terrain tool', (tester) async {
      useMap(LevelMapData(tileWidth: 16, tileHeight: 16));
      session.setTool(TileTools.stamp);
      tester.view
        ..physicalSize = const Size(400, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorScopeProvider(
              scope: scope,
              child: TilesetPalettePanel(session: session),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Terrains'));
      await tester.pump();
      expect(find.text('Grass'), findsOneWidget);
      await tester.tap(find.text('Dirt'));
      await tester.pump();
      expect(
        scope.tiles.terrain.value,
        const TerrainChoice(slot: 0, set: 0, color: 2),
      );
      expect(session.controller.toolId.value, TileTools.terrain);

      session.setTool(TileTools.stamp);
      await tester.pump();
      expect(find.text('Grass'), findsNothing, reason: 'the stamp shows tiles');
    });
  });

  testWidgets('in the Tileset Editor\'s terrain mode, a click paints a '
      'tile\'s corner and Alt+click clears it', (tester) async {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ts = _terrainTileset()..wangSets.single.wangIds.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TilesetEditor(
            root: '.',
            path: _path,
            loadImage: (_) async => _image(64, 64),
            readText: (_) async => jsonEncode(ts.toJson()),
            writeText: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(
      find.byTooltip(
        'Terrains: which corners and edges of which tiles are which',
      ),
    );
    await tester.pump();
    expect(find.text('TERRAIN SETS'), findsOneWidget);
    expect(find.textContaining('0 tiles cover 0 of the 16'), findsOneWidget);

    final grid = tester.getTopLeft(find.byKey(const ValueKey('tileset-grid')));
    // Tile 5 (column 1, row 1) at 300 %: its top-left corner.
    await tester.tapAt(grid + const Offset(48 + 4, 48 + 4));
    await tester.pump();
    final session = tester
        .state<TilesetEditorState>(find.byType(TilesetEditor))
        .session!;
    expect(session.data.wangSets.single.wangIds[5]![WangSetData.topLeft], 1);
    expect(find.textContaining('1 tiles cover 1 of the 16'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.tapAt(grid + const Offset(48 + 4, 48 + 4));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(session.data.wangSets.single.wangIds.containsKey(5), isFalse);
  });
}
