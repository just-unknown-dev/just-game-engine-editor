// The material tools keeping the user's files safe and the editor light: a
// file that can't be read is never saved over; the compare line and the
// zoom don't build the window again; a package's materials are read where
// the package is and not written into; images the previews read are let
// go; a map that can't be read doesn't hold the preview; the fix for a
// screen material's own values is undone on the screen material; and the
// tools never write outside the project.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_graphics_engine/testing.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

import '../support/real_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String root;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_material_safety');
    root = dir.path.replaceAll(r'\', '/');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // A read a widget test's frozen clock never finished: left for the
        // system's clean-up.
      }
    });
  });

  void write(String path, Object json) => File('$root/$path')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(json is String ? json : jsonEncode(json));

  String read(String path) => File('$root/$path').readAsStringSync();

  Future<void> png(String path, int argb, {int size = 4}) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      ui.Paint()..color = ui.Color(argb),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    File('$root/$path')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes.buffer.asUint8List());
  }

  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  EditorScope newScope() {
    final scope = EditorScope(world: World()..initialize(), modules: const []);
    addTearDown(scope.dispose);
    return scope;
  }

  Future<MaterialWorkspaceState> open3D(
    WidgetTester tester,
    String path,
  ) async {
    bigView(tester);
    final scope = newScope();
    final key = GlobalKey<MaterialWorkspaceState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MaterialWorkspace(
            key: key,
            path: path,
            root: dir.path,
            pictures: MaterialPictures(root: dir.path),
            workspace: WorkspaceContext(
              scope: scope,
              onClose: () {},
              path: path,
            ),
            loadOnStart: false,
          ),
        ),
      ),
    );
    final state = key.currentState!;
    await tester.runAsync(state.load);
    await tester.pump();
    return state;
  }

  Future<Material2DWorkspaceState> open2D(
    WidgetTester tester,
    String path,
  ) async {
    bigView(tester);
    final scope = newScope();
    final key = GlobalKey<Material2DWorkspaceState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Material2DWorkspace(
            key: key,
            path: path,
            root: dir.path,
            workspace: WorkspaceContext(
              scope: scope,
              onClose: () {},
              path: path,
            ),
            loadOnStart: false,
          ),
        ),
      ),
    );
    final state = key.currentState!;
    await tester.runAsync(state.load);
    await tester.pump();
    return state;
  }

  group("a file that can't be read is never saved over", () {
    for (final (what, text) in [
      ('broken JSON', '{"color": 4278190335,'),
      ('a newer format', '{"formatVersion": 99, "color": 4278190335}'),
    ]) {
      testWidgets('3-D: $what', (tester) async {
        write('m.material.json', text);
        final state = await open3D(tester, 'm.material.json');
        expect(find.textContaining("Can't be read"), findsOneWidget);
        expect(find.text('Read it again'), findsOneWidget);
        expect(find.text('Surface'), findsNothing, reason: 'no fields');
        // A preset or a module's change: nothing to edit.
        state.change(MaterialPreset.byId('gold')!.apply);
        expect(state.dirty, isFalse);
        expect(await tester.runAsync(state.save), isFalse);
        expect(read('m.material.json'), text, reason: 'left as it was');

        // Put right, it reads, and edits again.
        write('m.material.json', const MaterialFile(metallic: 0.5).encode());
        await tester.runAsync(state.load);
        await tester.pump();
        expect(find.text('Surface'), findsOneWidget);
        state.change((m) => m.copyWith(metallic: 1));
        expect(state.dirty, isTrue);
      });

      testWidgets('2-D: $what', (tester) async {
        write('m.material2d.json', text);
        final state = await open2D(tester, 'm.material2d.json');
        expect(find.textContaining("Can't be read"), findsOneWidget);
        expect(find.text('Read it again'), findsOneWidget);
        expect(find.text('Preset'), findsNothing, reason: 'no fields');
        state.change(Material2DPreset.of(Material2DKind.sprite).first.apply);
        expect(state.dirty, isFalse);
        expect(await tester.runAsync(state.save), isFalse);
        expect(read('m.material2d.json'), text, reason: 'left as it was');
      });
    }
  });

  group("the window isn't built again", () {
    // The fields' list: a new one whenever the window is built again.
    Widget fields(WidgetTester tester) =>
        tester.widget<ListView>(find.byType(ListView).first);

    testWidgets('3-D: as the compare line is dragged', (tester) async {
      write('m.material.json', const MaterialFile().encode());
      final state = await open3D(tester, 'm.material.json');
      state.setCompare(0.5);
      await tester.pump();
      final before = fields(tester);
      state.setCompare(0.3);
      await tester.pump();
      expect(state.compareAt, 0.3);
      expect(fields(tester), same(before));
    });

    testWidgets('2-D: as the compare line is dragged, or it zooms', (
      tester,
    ) async {
      write('m.material2d.json', {
        'flash': {'amount': 1},
      });
      final state = await open2D(tester, 'm.material2d.json');
      state.setCompare(0.5);
      await tester.pump();
      final before = fields(tester);
      state.setCompare(0.7);
      await tester.pump();
      expect(state.compareAt, 0.7);
      state.zoomBy(1);
      await tester.pump();
      state.fit();
      await tester.pump();
      expect(fields(tester), same(before));
      expect(state.stage.zoom, isNull);
    });
  });

  group("a package's materials", () {
    // A package resolved by pub somewhere else than the project.
    void package() {
      write('.dart_tool/package_config.json', {
        'configVersion': 2,
        'packages': [
          {'name': 'stone_pack', 'rootUri': '../elsewhere/stone_pack/'},
        ],
      });
      write('elsewhere/stone_pack/pubspec.yaml', 'name: stone_pack\n');
    }

    testWidgets('open where the package is', (tester) async {
      package();
      write(
        'elsewhere/stone_pack/rock.material.json',
        const MaterialFile(color: 0xFF112233).encode(),
      );
      final state = await open3D(
        tester,
        'packages/stone_pack/rock.material.json',
      );
      expect(state.material.color, 0xFF112233);
      expect(find.textContaining("Can't be read"), findsNothing);
    });

    test('read as 2-D materials; nothing is made in them', () {
      package();
      write('elsewhere/stone_pack/crt.material2d.json', {'kind': 'screen'});
      final module = BuiltInMaterialsModule(root: root);
      addTearDown(module.dispose);
      expect(
        module.kindOf2D('packages/stone_pack/crt.material2d.json'),
        Material2DKind.screen,
      );
      final writes = {
        BuiltInMaterialsModule.newMaterialId: true,
        BuiltInMaterialsModule.newMaterial2DId: true,
        BuiltInMaterialsModule.newScreenMaterialId: true,
        BuiltInMaterialsModule.textureSetsId: true,
        BuiltInMaterialsModule.newVariantId: false,
        BuiltInMaterialsModule.extractId: false,
        BuiltInMaterialsModule.spriteNormalId: false,
        BuiltInMaterialsModule.tilingNormalId: false,
      };
      final files = {
        BuiltInMaterialsModule.newVariantId: 'crt.material2d.json',
        BuiltInMaterialsModule.extractId: 'lamp.glb',
        BuiltInMaterialsModule.spriteNormalId: 'rock.png',
        BuiltInMaterialsModule.tilingNormalId: 'rock.png',
      };
      for (final action in module.assetActions) {
        final folder = writes[action.id]!;
        final own = folder ? 'assets' : 'assets/${files[action.id]}';
        final theirs = folder
            ? 'packages/stone_pack'
            : 'packages/stone_pack/${files[action.id]}';
        expect(
          action.appliesTo(own, isDirectory: folder),
          isTrue,
          reason: '${action.id} on the project',
        );
        expect(
          action.appliesTo(theirs, isDirectory: folder),
          isFalse,
          reason: '${action.id} on a package',
        );
      }
    });
  });

  group('nothing is written outside the project', () {
    test('no normal map beside a path that climbs out', () async {
      await png('assets/hero.png', 0xFF808080);
      await expectLater(
        NormalMaps.generate(root, '../outside.png'),
        throwsArgumentError,
      );
      await expectLater(
        NormalMaps.generate(root, 'packages/stone_pack/rock.png'),
        throwsArgumentError,
      );
      expect(await NormalMaps.generate(root, 'assets/hero.png'), isNotEmpty);
    });

    test("a model's image from outside the project is copied in", () async {
      final name = 'jge_outside_${DateTime.now().microsecondsSinceEpoch}.png';
      final outside = File('${dir.parent.path}/$name');
      final image = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/'
          'iZk9HQAAAABJRU5ErkJggg==',
        ),
      );
      outside.writeAsBytesSync(image);
      addTearDown(() {
        if (outside.existsSync()) outside.deleteSync();
      });
      final w = GlbWriter();
      final images = (w.json['images'] ??= <Object>[]) as List;
      images.add({'uri': '../../../$name', 'mimeType': 'image/png'});
      final texture = w.addTexture(images.length - 1);
      final paint = w.addMaterial({
        'name': 'Paint',
        'pbrMetallicRoughness': {
          'baseColorTexture': {'index': texture},
        },
      });
      w.setScene([
        w.addNode({
          'mesh': w.addMesh([
            {
              'attributes': {
                'POSITION': w.addFloats(
                  [0, 0, 0, 1, 0, 0, 0, 1, 0],
                  'VEC3',
                  withBounds: true,
                ),
              },
              'material': paint,
            },
          ]),
        }),
      ]);
      Directory('$root/assets/models').createSync(recursive: true);
      File('$root/assets/models/lamp.glb').writeAsBytesSync(w.toGlb());

      final made = await ModelMaterials.extract(root, 'assets/models/lamp.glb');
      final m = MaterialFile.parse(read(made.single));
      expect(m.colorMap, startsWith('assets/models/lamp_textures/'));
      expect(ProjectFiles.isContained(m.colorMap), isTrue);
      expect(File('$root/${m.colorMap}').readAsBytesSync(), image);
    });
  });

  test('numbered texture sets stay apart', () {
    final sets = TextureSets.find([
      't/aerial_rocks_04_nor_gl_4k.jpg',
      't/aerial_rocks_02_diff_4k.jpg',
      't/aerial_rocks_04_diff_4k.jpg',
      't/aerial_rocks_02_nor_gl_4k.jpg',
    ]);
    expect(
      [for (final s in sets) s.name],
      ['aerial_rocks_02', 'aerial_rocks_04'],
    );
    for (final s in sets) {
      expect(s.maps[TextureRole.colour]!.path, contains(s.name));
      expect(s.maps[TextureRole.normal]!.path, contains(s.name));
    }
  });

  test("the fix for a screen material's own values is undone on it", () {
    final world = World()..initialize();
    final scope = EditorScope(world: world, modules: const []);
    addTearDown(scope.dispose);
    write('fx/flash.material2d.json', {'flash': {}});
    write('fx/crt.material2d.json', {'kind': 'screen'});
    final screen = ScreenMaterial(material: 'fx/crt.material2d.json')
      ..set('nothing.here', 1.0);
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(100, 100, 0)),
      RectangleComponent(width: 40, height: 40),
      Material2D(material: 'fx/flash.material2d.json'),
      screen,
    ], name: 'Both');
    final problems = [
      for (final v in MaterialChecks.all)
        ...v(ValidationContext(scope: scope, projectRoot: root)),
    ];
    final problem = problems.singleWhere(
      (p) => p.message.contains('nothing.here'),
    );
    problem.fixes.single.apply();
    expect(screen.overrides, isEmpty);
    scope.history.undo();
    expect(screen.overrides, {'nothing.here': 1.0});
  });

  test('what draws with a 2-D material is read again once changed', () async {
    const material = 'fx/glow.material2d.json';
    Map<String, Object?> scene(String sprite) => {
      'entities': [
        {
          'name': 'Hero',
          'components': [
            {
              'type': 'SpriteComponent',
              'fields': {'spritePath': sprite},
            },
            {
              'type': 'Material2D',
              'fields': {'material': material},
            },
          ],
        },
      ],
    };
    write('assets/scenes/a.scene.json', scene('assets/hero.png'));
    expect(
      (await Material2DUsers.find(root, material))!.spritePath,
      'assets/hero.png',
    );
    write('assets/scenes/a.scene.json', scene('assets/hero_big_one.png'));
    expect(
      (await Material2DUsers.find(root, material))!.spritePath,
      'assets/hero_big_one.png',
    );
    // Told by the editor, it is read again whatever the clock says.
    Material2DUsers.forget(root, 'assets/scenes/a.scene.json');
    expect(
      (await Material2DUsers.find(root, material))!.spritePath,
      'assets/hero_big_one.png',
    );
  });

  group('images are let go', () {
    test("a map's picture, once forgotten", () async {
      await png('n.png', 0xFF8080FF);
      final maps = MapPictures(root: root);
      addTearDown(maps.dispose);
      await waitUntil(
        () => maps.peek('n.png') != null,
        what: 'the picture to be read',
      );
      final picture = maps.peek('n.png')!;
      maps.forget('n.png');
      expect(picture.image.debugDisposed, isTrue);
    });

    test('what a stage read: released, forgotten, or with the stage', () async {
      await png('hero.png', 0xFFFF0000);
      await png('n.png', 0xFF8080FF);
      write('bumpy.material2d.json', {
        'normalMap': {'map': 'n.png'},
      });
      final stage = Material2DStage(root: root);
      final first = (await stage.loadImage('hero.png'))!;
      stage.releaseImages();
      expect(first.debugDisposed, isTrue);

      // Forgotten: let go once what is shown no longer draws it.
      final old = (await stage.loadImage('hero.png'))!;
      stage.forgetImage('hero.png');
      final again = (await stage.loadImage('hero.png'))!;
      expect(again, isNot(same(old)));
      stage.show(
        'bumpy.material2d.json',
        kind: Material2DKind.sprite,
        subject: Material2DSubject.selected,
        image: again,
      );
      (await stage.picture(16, 16)).dispose();
      expect(old.debugDisposed, isTrue);
      expect(again.debugDisposed, isFalse);

      // The normal map the material names goes with the stage.
      final map = stage.library.imageOf('n.png');
      expect(map, isNotNull, reason: 'read for the picture');
      stage.dispose();
      expect(map!.debugDisposed, isTrue);
      expect(again.debugDisposed, isTrue);
    });

    test("a stone is drawn for its caller, not kept", () {
      final a = Material2DSamples.stone(8, 8),
          b = Material2DSamples.stone(8, 8);
      expect(a, isNot(same(b)));
      a.dispose();
      b.dispose();
    });
  });

  test("a normal map that can't be read doesn't hold the preview", () async {
    write('bumpy.material2d.json', {
      'normalMap': {'map': 'gone.png'},
    });
    final stage = Material2DStage(root: root);
    addTearDown(stage.dispose);
    stage.show(
      'bumpy.material2d.json',
      kind: Material2DKind.sprite,
      subject: Material2DSubject.auto,
      lit: true,
    );
    final clock = Stopwatch()..start();
    (await stage.picture(32, 32, wait: const Duration(seconds: 10))).dispose();
    expect(stage.ready, isTrue);
    expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
    // Not laid out again at every paint.
    List<int> laidOut() => [
      for (final e in stage.world.entities)
        if (e.isAlive) e.id,
    ];
    void paint() {
      final recorder = ui.PictureRecorder();
      stage.paint(Canvas(recorder), const Size(32, 32));
      recorder.endRecording().dispose();
    }

    paint();
    final before = laidOut();
    paint();
    paint();
    expect(laidOut(), before);
  });

  test('a 2-D picture changed on disk is drawn from the new file', () async {
    final pictures = Material2DPictures(root: root, size: 80);
    addTearDown(pictures.dispose);
    Future<(int, int, int)> centreOf(int argb, DateTime modified) async {
      write('flash.material2d.json', {
        'flash': {'colour': argb, 'amount': 1},
      });
      final image = (await pictures.of(
        'flash.material2d.json',
        modified: modified,
      ))!;
      final data = (await image.toByteData())!;
      final i = (34 * 80 + 34) * 4;
      return (data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
    }

    final (r, _, b) = await centreOf(0xFFFF0000, DateTime(2026, 1, 1));
    expect((r > 200, b < 60), (true, true), reason: 'red');
    final (r2, _, b2) = await centreOf(0xFF0000FF, DateTime(2026, 1, 2));
    expect((b2 > 200, r2 < 60), (true, true), reason: 'blue now');
  });

  test(
    'a new material in a folder that cannot be made is said, not thrown',
    () async {
      final module = BuiltInMaterialsModule(root: root);
      final scope = EditorScope(
        world: World()..initialize(),
        modules: [module],
      );
      addTearDown(scope.dispose);
      // A file where the folder would be.
      write('blocked', 'not a folder');
      final errors = <Object>[];
      runZonedGuarded(() {
        module.assetActions
            .firstWhere((a) => a.id == BuiltInMaterialsModule.newMaterialId)
            .run(scope, 'blocked');
      }, (error, _) => errors.add(error));
      // Done once it has said why it could not — or has thrown.
      await waitUntil(
        () =>
            errors.isNotEmpty ||
            scope.log.entries.value.any((e) => e.source == 'materials'),
        what: 'the new material to be refused',
      );
      expect(errors, isEmpty);
    },
  );
}
