// The material workspace: its cards (reset, fold), presets as one undo
// step, a value being dragged shown without an undo step, a variant's own
// values, the preview's toolbar (shape, light, background, zoom, compare)
// and keys, a map's picture and size, and a parent changed on disk.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_material_ws');
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  void write(String path, MaterialFile file) {
    File('${dir.path}/$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(file.encode());
  }

  Future<MaterialWorkspaceState> open(
    WidgetTester tester,
    String path, {
    Stream<String>? changes,
    MapPictures? maps,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scope = EditorScope(world: World()..initialize(), modules: const []);
    addTearDown(scope.dispose);
    final key = GlobalKey<MaterialWorkspaceState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MaterialWorkspace(
            key: key,
            path: path,
            root: dir.path,
            pictures: MaterialPictures(root: dir.path),
            maps: maps,
            changes: changes,
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

  testWidgets('its sections, and the Transparency fields its mode needs', (
    tester,
  ) async {
    write('a.material.json', const MaterialFile());
    final state = await open(tester, 'a.material.json');
    for (final card in ['Surface', 'Transparency', 'Maps']) {
      expect(find.text(card), findsOneWidget, reason: card);
    }
    expect(find.text('Cutoff'), findsNothing);
    state.change((m) => m.copyWith(alpha: MaterialAlpha.cutout));
    await tester.pump();
    expect(find.text('Cutoff'), findsOneWidget);
    state.change((m) => m.copyWith(alpha: MaterialAlpha.blend));
    await tester.pump();
    expect(find.text('Cutoff'), findsNothing);
    expect(find.text('Opacity'), findsOneWidget);
    state.change((m) => m.copyWith(kind: MaterialKind.layered));
    await tester.pump();
    expect(find.text('Layers'), findsOneWidget);
    expect(find.text('Transparency'), findsNothing);
    expect(find.text('Laid out'), findsOneWidget, reason: 'every kind has it');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card resets what it holds as one undo step, and folds', (
    tester,
  ) async {
    MaterialCardFolds.clear();
    addTearDown(MaterialCardFolds.clear);
    write(
      'a.material.json',
      const MaterialFile(color: 0xFF336699, metallic: 0.8, tilingX: 2),
    );
    final state = await open(tester, 'a.material.json');
    expect(state.cardChanged('surface'), isTrue);
    expect(state.cardChanged('transparency'), isFalse);
    expect(state.cardChanged('layout'), isTrue);
    await tester.tap(find.byTooltip('Back to its defaults').first);
    await tester.pump();
    expect(state.material.color, const MaterialFile().color);
    expect(state.material.metallic, const MaterialFile().metallic);
    expect(state.material.tilingX, 2, reason: "another card's");
    state.undo();
    expect(state.material.metallic, 0.8, reason: 'one undo step');

    await tester.pump();
    expect(find.text('Metallic'), findsOneWidget);
    await tester.tap(find.byTooltip('Fold').first);
    await tester.pump();
    expect(find.text('Metallic'), findsNothing);
    expect(find.text('Surface'), findsOneWidget, reason: 'its header stays');
    expect(MaterialCardFolds.isFolded('3d.surface'), isTrue);
  });

  testWidgets("a variant's card takes its own values back to the parent's", (
    tester,
  ) async {
    write(
      'rock.material.json',
      const MaterialFile(color: 0xFF808080, roughness: 0.9),
    );
    write(
      'mossy.material.json',
      const MaterialFile(
        parent: 'rock.material.json',
        color: 0xFF336633,
        tilingX: 3,
        overrides: {'color', 'tiling'},
      ),
    );
    final state = await open(tester, 'mossy.material.json');
    expect(state.cardChanged('surface'), isTrue);
    expect(state.cardChanged('maps'), isFalse);
    state.resetCard('surface');
    expect(state.material.overrides, {'tiling'});
    expect(state.shown.color, 0xFF808080, reason: "the parent's");
    expect(state.shown.tilingX, 3, reason: 'still its own');
  });

  testWidgets('the toolbar: shapes, background, zoom and fit, compare; '
      'and their keys', (tester) async {
    write('a.material.json', const MaterialFile());
    final state = await open(tester, 'a.material.json');
    await tester.tap(find.text('Cube'));
    await tester.pump();
    expect(state.shape, PreviewShape.cube);
    await tester.tap(find.text('Bright'));
    await tester.pump();
    expect(state.backdrop, PreviewBackdrop.bright);

    state.fit();
    await tester.pump();
    expect(state.atStart, isTrue);
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom in (+)'));
    await tester.pump();
    expect(state.zoom, closeTo(1.25, 1e-9));
    expect(find.text('125%'), findsOneWidget);
    expect(state.atStart, isFalse);
    await tester.tap(find.text('Fit'));
    await tester.pump();
    expect(state.atStart, isTrue);

    await tester.tap(
      find.byTooltip('Compare with a plain grey material (C; hold Space)'),
    );
    await tester.pump();
    expect(state.compareAt, 0.5);
    expect(find.text('Plain'), findsOneWidget);
    expect(find.text('With'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    expect(state.compareAt, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    expect(state.backdrop, PreviewBackdrop.sky, reason: 'round after Bright');
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    expect(state.atStart, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    expect(state.atStart, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(state.holdingPlain, isTrue);
    await tester.pump();
    expect(find.text('A plain grey in its place'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(state.holdingPlain, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a preset is one undo step', (tester) async {
    write('a.material.json', const MaterialFile(color: 0xFF336699));
    final state = await open(tester, 'a.material.json');
    state.change(MaterialPreset.byId('gold')!.apply);
    expect(state.material.metallic, 1);
    expect(state.material.color, 0xFFFFC356);
    state.change(MaterialPreset.byId('glass')!.apply);
    expect(state.material.alpha, MaterialAlpha.blend);
    expect(state.material.validate(), isEmpty);
    state.undo();
    expect(state.material.alpha, MaterialAlpha.opaque);
    state.undo();
    expect(state.material.color, 0xFF336699);
    expect(state.dirty, isFalse);
    // Every preset makes a material that saves.
    for (final p in MaterialPreset.all) {
      expect(p.apply(const MaterialFile()).validate(), isEmpty, reason: p.id);
    }
  });

  testWidgets('a value being dragged is drawn, not an undo step', (
    tester,
  ) async {
    write('a.material.json', const MaterialFile(roughness: 0.5));
    final state = await open(tester, 'a.material.json');
    state.preview((m) => m.copyWith(roughness: 0.2));
    expect(state.drawn.roughness, 0.2);
    expect(state.material.roughness, 0.5);
    expect(state.dirty, isFalse);
    state.endPreview();
    expect(state.drawn.roughness, 0.5);
    state.preview((m) => m.copyWith(roughness: 0.3));
    state.change((m) => m.copyWith(roughness: 0.3));
    expect(state.drawn.roughness, 0.3);
    expect(state.material.roughness, 0.3);
    state.undo();
    expect(state.drawn.roughness, 0.5);
  });

  group('a variant', () {
    setUp(() {
      write(
        'rock.material.json',
        const MaterialFile(color: 0xFF808080, metallic: 1, roughness: 0.8),
      );
      write(
        'mossy.material.json',
        const MaterialFile(
          parent: 'rock.material.json',
          color: 0xFF4C7A3A,
          overrides: {'color'},
        ),
      );
    });

    testWidgets("shows its parent's values where it has none", (tester) async {
      final state = await open(tester, 'mossy.material.json');
      expect(state.shown.color, 0xFF4C7A3A);
      expect(state.shown.metallic, 1, reason: "the parent's");
      expect(state.shown.roughness, 0.8);
      expect(find.textContaining('Variant of rock.material.json'), findsOne);
      expect(find.text('Open parent'), findsOneWidget);
    });

    testWidgets('a value changed becomes its own, even the default', (
      tester,
    ) async {
      final state = await open(tester, 'mossy.material.json');
      state.change((m) => m.copyWith(metallic: 0));
      expect(state.material.overrides, {'color', 'metallic'});
      expect(state.shown.metallic, 0);
      expect(state.shown.roughness, 0.8, reason: 'still the parent\'s');
      await tester.runAsync(state.save);
      final saved = MaterialFile.parse(
        File('${dir.path}/mossy.material.json').readAsStringSync(),
      );
      expect(saved.parent, 'rock.material.json');
      expect(saved.overrides, {'color', 'metallic'});
      state.change(MaterialPreset.byId('rubber')!.apply);
      expect(
        state.material.overrides,
        containsAll(['color', 'metallic', 'roughness']),
      );
    });

    testWidgets('its parent changed on disk shows', (tester) async {
      final changes = StreamController<String>.broadcast();
      addTearDown(changes.close);
      final state = await open(
        tester,
        'mossy.material.json',
        changes: changes.stream,
      );
      expect(state.shown.roughness, 0.8);
      write(
        'rock.material.json',
        const MaterialFile(color: 0xFF808080, metallic: 1, roughness: 0.3),
      );
      changes.add('rock.material.json');
      await tester.pump();
      expect(state.shown.roughness, 0.3);
    });

    testWidgets('a missing parent is said', (tester) async {
      File('${dir.path}/rock.material.json').deleteSync();
      final state = await open(tester, 'mossy.material.json');
      expect(state.shown.color, 0xFF4C7A3A);
      expect(
        find.textContaining('"rock.material.json" is missing'),
        findsOneWidget,
      );
    });
  });

  testWidgets("the preview's shape and light are kept for the next one", (
    tester,
  ) async {
    write('a.material.json', const MaterialFile());
    final state = await open(tester, 'a.material.json');
    expect(state.sceneLighting, isNull, reason: 'no engine, no scene');
    state.setShape(PreviewShape.torus);
    state.setLighting(PreviewLighting.dusk);
    await tester.pumpWidget(const SizedBox());
    final next = await open(tester, 'a.material.json');
    expect(next.shape, PreviewShape.torus);
    expect(next.lighting, PreviewLighting.dusk);
    next
      ..setShape(PreviewShape.ball)
      ..setLighting(PreviewLighting.studio);
  });

  testWidgets("a map's slot shows its picture and size", (tester) async {
    final png = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 40, 20),
        Paint()..color = const Color(0xFFFF0000),
      );
      final image = await recorder.endRecording().toImage(40, 20);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    });
    File('${dir.path}/brick.png').writeAsBytesSync(png!);
    write('a.material.json', const MaterialFile(colorMap: 'brick.png'));
    final maps = MapPictures(root: dir.path);
    addTearDown(maps.dispose);
    // Read for real (a widget test's clock stands still).
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && maps.peek('brick.png') == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await open(tester, 'a.material.json', maps: maps);
    expect(find.text('40 × 20'), findsOneWidget);
    expect(maps.peek('brick.png')!.image.width, 40, reason: 'small already');

    // Changed on disk: forgotten, so it is read again when next asked.
    final before = maps.revision.value;
    maps.forget('brick.png');
    expect(maps.revision.value, before + 1);
    maps.forget('brick.png');
    expect(maps.revision.value, before + 1, reason: 'nothing left to forget');
  });

  testWidgets('a map that cannot be read says so', (tester) async {
    write('a.material.json', const MaterialFile(normalMap: 'gone.png'));
    final maps = MapPictures(root: dir.path);
    addTearDown(maps.dispose);
    await open(tester, 'a.material.json', maps: maps);
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && !maps.failed('gone.png'); i++) {
        maps.peek('gone.png');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(find.text("Can't be read"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'the module hands a changed file to its pictures and workspaces',
    () async {
      final module = BuiltInMaterialsModule(root: dir.path);
      addTearDown(module.dispose);
      final seen = <String>[];
      final scope = EditorScope(
        world: World()..initialize(),
        modules: [module],
      );
      addTearDown(scope.dispose);
      final workspace = module.workspaces.firstWhere(
        (w) => w.id == BuiltInMaterialsModule.workspaceId,
      );
      expect(workspace.id, BuiltInMaterialsModule.workspaceId);
      // The workspace it builds listens; here, a listener of its own.
      final built =
          workspace.build(
                _FakeContext(),
                WorkspaceContext(scope: scope, onClose: () {}, path: 'a.json'),
              )
              as MaterialWorkspace;
      final sub = built.changes!.listen(seen.add);
      addTearDown(sub.cancel);
      module.onAssetChanged('assets/textures/brick.png');
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['assets/textures/brick.png']);
      expect(built.maps, same(module.maps));
    },
  );
}

class _FakeContext extends Fake implements BuildContext {}
