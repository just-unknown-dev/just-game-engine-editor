// The Tileset Editor: cutting a tileset from an image, giving tiles
// collision, animation and properties with an undo of its own, saving, and
// how the editor opens it.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

ui.Image _image(int w, int h) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF3A7D44),
  );
  return recorder.endRecording().toImageSync(w, h);
}

/// A 64 × 32 image: 4 × 2 tiles of 16.
Future<ui.Image> _load(String path) async => _image(64, 32);

TilesetData _tileset() => TilesetData.fromImage(
  name: 'grass',
  image: 'assets/tilesets/grass.png',
  imageWidth: 64,
  imageHeight: 32,
  tileWidth: 16,
  tileHeight: 16,
);

void main() {
  late Map<String, String> files;

  Future<void> write(String path, String text) async => files[path] = text;

  setUp(() => files = {});

  TilesetSession session() => TilesetSession(
    _tileset(),
    path: 'assets/tilesets/grass.tileset.json',
    root: '.',
    loadImage: _load,
    writeText: write,
  );

  group('session', () {
    test('a new tileset is cut from its image, and is unsaved', () async {
      final s = await TilesetSession.create(
        image: 'assets/tilesets/grass.png',
        name: 'grass',
        tileWidth: 16,
        tileHeight: 16,
        root: '.',
        loadImage: _load,
        writeText: write,
      );
      addTearDown(s.dispose);
      expect(s.data.columns, 4);
      expect(s.data.tileCount, 8);
      expect(s.isDirty, isTrue);
      expect(s.path, isNull);

      await s.save(to: 'assets/tilesets/grass.tileset.json');
      expect(s.isDirty, isFalse);
      expect(s.path, 'assets/tilesets/grass.tileset.json');
      final saved = jsonDecode(files[s.path]!) as Map<String, dynamic>;
      expect(saved['tileCount'], 8);
      expect(saved['image'], 'assets/tilesets/grass.png');
    });

    test('a preset goes on every selected tile, as one step', () {
      final s = session();
      addTearDown(s.dispose);
      s.selection.value = {0, 1};
      s.setCollision(TileCollisionPreset.full.shapesFor(16, 16));
      for (final id in [0, 1]) {
        final c = s.data.tile(id)!.collision!;
        expect(c.isFullCell(16, 16), isTrue);
        expect(TileCollisionPreset.of(c, 16, 16), TileCollisionPreset.full);
      }
      expect(s.isDirty, isTrue);

      s.undo();
      expect(
        s.data.tile(0),
        isNull,
        reason: 'a tile that says nothing is dropped',
      );
      expect(s.isDirty, isFalse);
      s.redo();
      expect(s.data.tile(1)!.collision, isNotNull);
    });

    test('slopes rise the way they say', () {
      final up =
          TileCollisionPreset.slopeUp.shapesFor(16, 16)!.single
              as TilePolygonShape;
      // Low on the left, high on the right: y grows downwards.
      expect(up.points, contains(const Offset(0, 16)));
      expect(up.points, contains(const Offset(16, 0)));
      final low =
          TileCollisionPreset.gentleUpLow.shapesFor(16, 16)!.single
              as TilePolygonShape;
      final high =
          TileCollisionPreset.gentleUpHigh.shapesFor(16, 16)!.single
              as TilePolygonShape;
      // The low tile ends where the high one starts.
      expect(low.points, contains(const Offset(16, 8)));
      expect(high.points, contains(const Offset(0, 8)));
    });

    test('the kind changes only on tiles that collide', () {
      final s = session();
      addTearDown(s.dispose);
      s.selection.value = {0};
      s.setCollision(TileCollisionPreset.topHalf.shapesFor(16, 16));
      s.selection.value = {0, 1};
      s.setCollisionKind('oneWay');
      expect(s.data.tile(0)!.collision!.kind, 'oneWay');
      expect(s.data.tile(1), isNull);
    });

    test('dragging a corner is one undo step, however far', () {
      final s = session();
      addTearDown(s.dispose);
      s.selection.value = {2};
      for (var y = 0; y <= 8; y += 2) {
        s.setShapes(
          2,
          [
            TilePolygonShape([
              const Offset(0, 16),
              Offset(16, y.toDouble()),
              const Offset(16, 16),
            ]),
          ],
          mergeKey: ('corner', 2, 1),
        );
      }
      s.undo();
      expect(s.data.tile(2), isNull);
      expect(s.canUndo, isFalse);
    });

    test('animating a selection makes its lowest tile play them all', () {
      final s = session();
      addTearDown(s.dispose);
      s.selection.value = {6, 4, 5};
      s.animateSelection(durationMs: 90);
      final def = s.data.tile(4)!;
      expect(def.animation.map((f) => f.tileId), [4, 5, 6]);
      expect(def.animation.map((f) => f.durationMs), everyElement(90));
      expect(s.selection.value, {4});

      s.selection.value = {7};
      s.animateSelection();
      expect(s.message.value, contains('two tiles or more'));
    });

    test('properties keep their type; probability merges while scrubbed', () {
      final s = session();
      addTearDown(s.dispose);
      s.selection.value = {3};
      s.setProperty('damage', 2, TilePropertyType.int);
      s.setProperty('damage', 3, TilePropertyType.int);
      expect(s.data.tile(3)!.properties['damage'], 3);
      expect(s.data.tile(3)!.properties.typeOf('damage'), TilePropertyType.int);
      s.undo();
      expect(s.data.tile(3), isNull, reason: 'the two sets were one step');

      s.setProbability(0.5);
      s.setProbability(0.25);
      s.undo();
      expect(s.data.tile(3), isNull);
    });

    test('opens a saved tileset and saves it back the same', () async {
      final saved = session();
      addTearDown(saved.dispose);
      saved.selection.value = {1};
      saved.setCollision(
        TileCollisionPreset.slopeUp.shapesFor(16, 16),
        kind: 'oneWay',
      );
      saved.setClass('ramp');
      await saved.save();

      final opened = await TilesetSession.open(
        'assets/tilesets/grass.tileset.json',
        root: '.',
        readText: (path) async => files[path]!,
        loadImage: _load,
        writeText: write,
      );
      addTearDown(opened.dispose);
      expect(opened.isDirty, isFalse);
      expect(opened.data.tile(1)!.className, 'ramp');
      expect(opened.data.tile(1)!.collision!.kind, 'oneWay');
      final before = files.values.single;
      await opened.save();
      expect(files.values.single, before);
    });
  });

  group('workspace', () {
    Future<void> pumpEditor(
      WidgetTester tester, {
      required String path,
      ValueChanged<String>? onSaved,
      Map<String, String>? readable,
    }) async {
      tester.view
        ..physicalSize = const Size(1400, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TilesetEditor(
              root: '.',
              path: path,
              loadImage: _load,
              readText: (p) async => readable![p]!,
              writeText: write,
              onSaved: onSaved,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('select a tile, give it collision, save', (tester) async {
      const path = 'assets/tilesets/grass.tileset.json';
      String? saved;
      await pumpEditor(
        tester,
        path: path,
        readable: {path: jsonEncode(_tileset().toJson())},
        onSaved: (p) => saved = p,
      );
      expect(find.text('grass.tileset.json'), findsOneWidget);
      expect(find.text('TILESET'), findsOneWidget);

      // 16 px tiles show at 300 %: tile 5 is column 1, row 1.
      final grid = tester.getTopLeft(
        find.byKey(const ValueKey('tileset-grid')),
      );
      await tester.tapAt(grid + const Offset(1 * 48 + 24, 1 * 48 + 24));
      await tester.pump();
      expect(find.text('TILE 5'), findsOneWidget);

      await tester.tap(find.byTooltip('Full'));
      await tester.pump();
      expect(find.text('grass.tileset.json •'), findsOneWidget);

      await ctrl(tester, LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(saved, path);
      final json = jsonDecode(files[path]!) as Map<String, dynamic>;
      expect((json['tiles'] as Map)['5'], isNotNull);
      expect(find.text('grass.tileset.json'), findsOneWidget);

      // Its own undo.
      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(find.text('grass.tileset.json •'), findsOneWidget);
    });

    testWidgets('frames made from a selection list in the inspector, and a '
        'dragged corner is one step', (tester) async {
      const path = 'assets/tilesets/grass.tileset.json';
      final ts = _tileset();
      ts.tileOrNew(7).collision = TileCollision(
        shapes: TileCollisionPreset.slopeUp.shapesFor(16, 16),
      );
      await pumpEditor(
        tester,
        path: path,
        readable: {path: jsonEncode(ts.toJson())},
      );
      final grid = tester.getTopLeft(
        find.byKey(const ValueKey('tileset-grid')),
      );
      Offset tile(int col, int row) =>
          grid + Offset(col * 48 + 24, row * 48 + 24);

      await tester.tapAt(tile(0, 0));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(tile(2, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(find.textContaining('3 TILES'), findsOneWidget);

      await tester.tap(find.text('Animate selection'));
      await tester.pump();
      expect(find.text('TILE 0'), findsOneWidget);
      expect(find.byTooltip('Remove the frame'), findsNWidgets(3));
      expect(tester.takeException(), isNull);

      // Tile 7's slope: drag its top corner halfway down.
      await tester.tapAt(tile(3, 1));
      await tester.pump();
      final canvas = find.descendant(
        of: find.byType(ShapeCanvas),
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.size == const Size(240, 240),
        ),
      );
      final origin = tester.getTopLeft(canvas) + const Offset(10, 10);
      const scale = 220 / 16;
      final gesture = await tester.startGesture(
        origin + const Offset(16, 0) * scale,
      );
      await gesture.moveTo(origin + const Offset(16, 4) * scale);
      await gesture.moveTo(origin + const Offset(16, 8) * scale);
      await gesture.up();
      await tester.pump();
      final state = tester.state<TilesetEditorState>(
        find.byType(TilesetEditor),
      );
      final session = state.session!;
      final shape =
          session.data.tile(7)!.collision!.shapes.single as TilePolygonShape;
      expect(shape.points, contains(const Offset(16, 8)));
      session.undo();
      final back =
          session.data.tile(7)!.collision!.shapes.single as TilePolygonShape;
      expect(back.points, contains(const Offset(16, 0)), reason: 'one step');
      await tester.pump();
    });

    testWidgets('opened on an image, it cuts a new tileset and asks a name '
        'on the first save', (tester) async {
      String? saved;
      await pumpEditor(
        tester,
        path: 'assets/art/meadow.png',
        onSaved: (p) => saved = p,
      );
      expect(find.text('New tileset'), findsOneWidget);
      expect(find.textContaining('4 × 2 = 8 tiles'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pump();
      await tester.pump();
      expect(find.text('New tileset •'), findsOneWidget);

      await ctrl(tester, LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(find.text('Name this tileset'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump();
      expect(saved, 'assets/tilesets/meadow.tileset.json');
      final json = jsonDecode(files[saved]!) as Map<String, dynamic>;
      expect(json['image'], 'assets/art/meadow.png');
      expect(json['name'], 'meadow');
    });

    test('the editor opens tilesets in it, and offers to cut images', () {
      final scope = testScope();
      expect(
        scope.openInWorkspace('assets/tilesets/grass.tileset.json'),
        isTrue,
      );
      expect(
        scope.activeWorkspace.value!.definition.id,
        BuiltInWorkspaces.tileset,
      );

      bool offers(String id, String path) => scope.assetActions.any(
        (a) => a.id == id && a.appliesTo(path, isDirectory: false),
      );
      expect(offers('tiles.create_tileset', 'assets/art/meadow.png'), isTrue);
      expect(
        offers('tiles.create_tileset', 'assets/art/meadow.original.png'),
        isFalse,
      );
      expect(
        offers('tiles.edit_tileset', 'assets/tilesets/grass.tileset.json'),
        isTrue,
      );
    });

    test('panels hear when a tileset has been read again', () {
      final world = World()..initialize();
      final scope = testScope(world: world);
      final docs = scope.mapDocs;
      docs.pollAssets();
      final before = docs.revision.value;
      docs.pollAssets();
      expect(docs.revision.value, before, reason: 'nothing changed');
      TileAssets.evict('assets/tilesets/grass.tileset.json');
      docs.pollAssets();
      expect(docs.revision.value, before + 1);
    });
  });
}
