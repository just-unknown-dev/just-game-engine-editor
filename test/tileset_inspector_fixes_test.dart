// The tileset editor's and the inspector's release fixes: numbers that are
// not numbers, images let go, saves that are whole and never in pub's
// cache, corners that cross cleanly, colliders that keep their kind.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine/just_game_engine.dart'
    show
        TilesetData,
        TileCollision,
        TileRectShape,
        TilePropertyType,
        TileProperties;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/ui/inspector/physics/collider_edit_session.dart';
import 'package:just_game_engine_editor/src/ui/inspector/physics_field_editors.dart';
import 'package:just_game_engine_editor/src/ui/inspector/property_table_editor.dart';
import 'package:just_game_engine_editor/src/ui/tileset/collision_shape_editor.dart';
import 'package:just_game_engine_editor/src/ui/tileset/tileset_session.dart';
import 'package:just_game_engine_editor/src/ui/tileset/wang_set_editor.dart';

ui.Image _image(int w, int h) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF3A7D44),
  );
  return recorder.endRecording().toImageSync(w, h);
}

TilesetData _tileset() => TilesetData.fromImage(
  name: 'grass',
  image: 'assets/tilesets/grass.png',
  imageWidth: 64,
  imageHeight: 32,
  tileWidth: 16,
  tileHeight: 16,
);

void main() {
  group('TI-13 the tileset never holds a number that is not one', () {
    test('NaN is refused, and an edit that would hold one is taken back', () {
      final s = TilesetSession(
        _tileset(),
        root: '.',
        loadImage: (_) async => _image(64, 32),
        writeText: (_, _) async {},
      );
      addTearDown(s.dispose);
      s.selection.value = {1};
      s.setProbability(double.nan);
      expect(s.data.tile(1), isNull);
      s.setTileOffset(double.infinity, 0);
      expect(s.data.tileOffsetX, 0);
      expect(s.isDirty, isFalse);

      // Whatever path a non-number takes in, it does not stay.
      s.apply('Offset', (ts) => ts.tileOffsetX = double.nan);
      expect(s.data.tileOffsetX, 0);
      expect(s.message.value, startsWith('Not changed'));
      expect(() => s.isDirty, returnsNormally);
      expect(s.canUndo, isFalse);
    });
  });

  group('TI-15 the images it owns are let go', () {
    test(
      'replaced and closed: disposed when its own, kept when shared',
      () async {
        final given = <ui.Image>[];
        Future<ui.Image> load(String _) async => given.last;

        given.add(_image(64, 32));
        final own = TilesetSession(
          _tileset(),
          root: '.',
          loadImage: load,
          disposesImages: true,
        );
        await Future<void>.delayed(Duration.zero);
        final first = own.image.value!;
        given.add(_image(64, 32));
        await own.reloadImage();
        expect(first.debugDisposed, isTrue);
        final second = own.image.value!;
        own.dispose();
        expect(second.debugDisposed, isTrue);

        final shared = _image(64, 32);
        given.add(shared);
        final borrowed = TilesetSession(
          _tileset(),
          root: '.',
          loadImage: load,
          disposesImages: false,
        );
        await Future<void>.delayed(Duration.zero);
        await borrowed.reloadImage();
        borrowed.dispose();
        expect(shared.debugDisposed, isFalse);
        shared.dispose();
      },
    );

    test(
      'a new tileset cut from a size it is told reads no image for it',
      () async {
        var loads = 0;
        final s = await TilesetSession.create(
          image: 'assets/a.png',
          name: 'a',
          tileWidth: 16,
          tileHeight: 16,
          root: '.',
          imageWidth: 64,
          imageHeight: 32,
          loadImage: (_) async {
            loads++;
            return _image(64, 32);
          },
          writeText: (_, _) async {},
        );
        addTearDown(s.dispose);
        await Future<void>.delayed(Duration.zero);
        expect(loads, 1, reason: 'the one it draws, not one to measure');
        expect(s.data.tileCount, 8);
      },
    );
  });

  test('TI-10 a tileset in pub\'s cache is not written; a project one is '
      'written whole', () async {
    final root = Directory.systemTemp.createTempSync('tileset_fixes');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // A temp folder; Windows may hold it a moment.
      }
    });
    final cache = Directory('${root.path}/Pub/Cache/hosted/tiles-1.0.0')
      ..createSync(recursive: true);
    File(
      '${cache.path}/pubspec.yaml',
    ).writeAsStringSync('name: tiles\nflutter:\n  assets:\n    - assets/\n');
    final shared = File('${cache.path}/assets/g.tileset.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(_tileset().toJson()));
    File('${root.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'tiles',
              'rootUri': '../Pub/Cache/hosted/tiles-1.0.0/',
              'packageUri': 'lib/',
            },
          ],
        }),
      );
    final rootPath = root.path.replaceAll(r'\', '/');
    PackageAssetPaths.of(rootPath).invalidate();
    final s = await TilesetSession.open(
      'packages/tiles/assets/g.tileset.json',
      root: rootPath,
      loadImage: (_) async => _image(64, 32),
    );
    addTearDown(s.dispose);
    expect(s.canSaveTo('packages/tiles/assets/g.tileset.json'), isFalse);
    expect(s.canSaveTo('../elsewhere.tileset.json'), isFalse);
    final before = shared.readAsStringSync();
    s.selection.value = {0};
    s.setClass('spikes');
    await expectLater(s.save(), throwsStateError);
    expect(shared.readAsStringSync(), before);

    await s.save(to: 'assets/tilesets/g.tileset.json');
    final copy = File('${root.path}/assets/tilesets/g.tileset.json');
    expect(copy.existsSync(), isTrue);
    expect(File('${copy.path}.saving').existsSync(), isFalse);
    expect(s.isDirty, isFalse);
  });

  testWidgets('TI-18/TI-19 a box corner dragged past the other stays '
      'anchored; two drags are two steps', (tester) async {
    final ts = _tileset();
    ts.tileOrNew(0).collision = TileCollision(
      shapes: [TileRectShape(const Rect.fromLTWH(0, 0, 10, 10))],
    );
    final s = TilesetSession(
      ts,
      root: '.',
      loadImage: (_) async => _image(64, 32),
      writeText: (_, _) async {},
    );
    addTearDown(s.dispose);
    s.selection.value = {0};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: ShapeCanvas(session: s, tileId: 0)),
        ),
      ),
    );
    // The tile as drawn: the canvas's paint, not the column round it.
    final canvas = tester.getTopLeft(
      find
          .descendant(
            of: find.byType(ShapeCanvas),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    const scale = ShapeCanvas.extent / 16;
    Offset at(double x, double y) =>
        canvas +
        const Offset(ShapeCanvas.pad, ShapeCanvas.pad) +
        Offset(x, y) * scale;
    Rect rect() =>
        (s.data.tile(0)!.collision!.shapes.single as TileRectShape).rect;

    // The top-left corner, past the bottom-right one and on.
    final drag = await tester.startGesture(at(0, 0));
    await drag.moveTo(at(5, 5));
    await drag.moveTo(at(12, 12));
    await drag.moveTo(at(13, 13));
    await drag.up();
    await tester.pump();
    expect(rect(), const Rect.fromLTRB(10, 10, 13, 13));

    // A second drag of the same corner: its own step.
    final again = await tester.startGesture(at(13, 13));
    await again.moveTo(at(15, 15));
    await again.up();
    await tester.pump();
    expect(rect(), const Rect.fromLTRB(10, 10, 15, 15));
    s.undo();
    expect(rect(), const Rect.fromLTRB(10, 10, 13, 13));
    s.undo();
    expect(rect(), const Rect.fromLTWH(0, 0, 10, 10));
  });

  testWidgets('TI-27 removing the last terrain leaves the eraser chosen', (
    tester,
  ) async {
    final s = TilesetSession(
      _tileset(),
      root: '.',
      loadImage: (_) async => _image(64, 32),
      writeText: (_, _) async {},
    );
    addTearDown(s.dispose);
    s.addWangSet();
    int? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WangSetEditor(
              session: s,
              set: 0,
              color: 1,
              onSet: (_) {},
              onColor: (c) => chosen = c,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Remove the terrain'));
    await tester.pump();
    expect(s.data.wangSets.single.colors, isEmpty);
    expect(chosen, 0);
  });

  testWidgets('TI-26 a property that is there is not added again', (
    tester,
  ) async {
    final props = TileProperties()..set('damage', 5, TilePropertyType.int);
    final sets = <String>[];
    String? said;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PropertyTableEditor(
            properties: props,
            onSet: (name, _, _) => sets.add(name),
            onRemove: (_) {},
            onInvalid: (m) => said = m,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).last, 'damage');
    await tester.tap(find.byTooltip('Add the property'));
    await tester.pump();
    expect(sets, isEmpty);
    expect(said, contains('already'));
  });

  group('TI-14 the collider keeps its kind in the viewport', () {
    late EditorScope scope;
    late EditorView view;
    late ColliderEditSession session;

    setUp(() {
      scope = testScope();
      final camera = jge.Camera()..viewportSize = const Size(800, 600);
      view = GameCameraEditorView.of(camera);
      session = ColliderEditSession.of(scope);
    });

    jge.Entity body(jge.Collider2D collider) =>
        scope.world.createEntityWithComponents([
          jge.TransformComponent(position: jge.Vector3(100, 100, 0)),
          jge.RigidBody2D(),
          collider,
        ], name: 'Thing');

    ColliderHandle handle(ColliderHandleKind kind, int index) =>
        session.handles().firstWhere((h) => h.kind == kind && h.index == index);

    void drag(ColliderHandle h, Offset by) {
      final from = view.worldToScreen(session.toWorld(h.local));
      expect(session.onPointerDown(from, view), isTrue);
      session
        ..onPointerMove(from + by / 2, view)
        ..onPointerMove(from + by, view)
        ..onPointerUp();
    }

    test('a turned box moved and resized is still that box, turned', () {
      final c = jge.Collider2D(shape: jge.ColliderShape2D.box)
        ..size = jge.Vector2(40, 20)
        ..rotation = math.pi / 6;
      final e = body(c);
      session.toggle(e);
      drag(handle(ColliderHandleKind.center, 0), const Offset(10, 0));
      expect(c.shape, jge.ColliderShape2D.box);
      expect(c.rotation, closeTo(math.pi / 6, 1e-9));
      expect((c.size.x, c.size.y), (40, 20));
      expect(c.offset.dx, closeTo(10, 0.5));

      drag(handle(ColliderHandleKind.side, 1), const Offset(20, 0));
      expect(c.shape, jge.ColliderShape2D.box);
      expect(c.rotation, closeTo(math.pi / 6, 1e-9));
      expect(c.size.x, greaterThan(40));
      expect(c.size.y, 20);
    });

    test('a rounded polygon keeps its points and its corners', () {
      final c = jge.Collider2D(shape: jge.ColliderShape2D.polygon)
        ..points = const [
          Offset(-10, -10),
          Offset(10, -10),
          Offset(10, 10),
          Offset(-10, 10),
        ]
        ..cornerRadius = 4;
      final e = body(c);
      session.toggle(e);
      drag(handle(ColliderHandleKind.vertex, 2), const Offset(4, 4));
      expect(c.shape, jge.ColliderShape2D.polygon);
      expect(c.cornerRadius, 4);
      expect(c.points, hasLength(4));
      expect(c.points[2], const Offset(14, 14));
      // Points are added to a polygon, not to a box.
      expect(
        session.handles().any((h) => h.kind == ColliderHandleKind.insert),
        isTrue,
      );
      c.shape = jge.ColliderShape2D.box;
      expect(
        session.handles().any((h) => h.kind == ColliderHandleKind.insert),
        isFalse,
      );
    });
  });

  test('TI-33 the layer counts are worked out once per change', () {
    final scope = testScope();
    final a = PhysicsFieldEditors.bodyCounts(scope);
    expect(identical(PhysicsFieldEditors.bodyCounts(scope), a), isTrue);
    scope.sceneState.refresh();
    expect(identical(PhysicsFieldEditors.bodyCounts(scope), a), isFalse);
  });
}
