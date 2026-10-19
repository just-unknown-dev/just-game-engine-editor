// Variants and live edits: a variant's own value taken back from its
// parent, all of them at once, or written into the parent; a new variant
// made beside a material; and unsaved edits drawn in the open scene until
// saved or the workspace closes.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

import '../support/real_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_variants');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // A read a widget test's frozen clock never finished: left for
        // the system's clean-up.
      }
    });
  });

  void write(String path, String text) => File('${dir.path}/$path')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  String read(String path) => File('${dir.path}/$path').readAsStringSync();

  Widget host(Widget workspace) => MaterialApp(home: Scaffold(body: workspace));

  // Waits until the 2-D material and its parent are read, so the reads a
  // widget test's frozen clock started (the window asks its stage every
  // frame) are over: on Windows a file still open for reading can't be
  // saved over (a save is written beside it and moved over it).
  Future<void> settle(WidgetTester tester, Material2DWorkspaceState state) =>
      pumpUntil(
        tester,
        () => state.stage.ready,
        what: 'the material and its parent to be read',
      );

  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('a 3-D variant', () {
    late List<String> reloaded;

    Future<MaterialWorkspaceState> open(WidgetTester tester) async {
      bigView(tester);
      final scope = EditorScope(
        world: World()..initialize(),
        modules: const [],
      );
      addTearDown(scope.dispose);
      reloaded = [];
      final key = GlobalKey<MaterialWorkspaceState>();
      await tester.pumpWidget(
        host(
          MaterialWorkspace(
            key: key,
            path: 'mossy.material.json',
            root: dir.path,
            pictures: MaterialPictures(root: dir.path),
            workspace: WorkspaceContext(
              scope: scope,
              onClose: () {},
              path: 'mossy.material.json',
              reloadAssets: reloaded.add,
            ),
            loadOnStart: false,
          ),
        ),
      );
      final state = key.currentState!;
      await tester.runAsync(state.load);
      await tester.pump();
      return state;
    }

    setUp(() {
      write(
        'rock.material.json',
        const MaterialFile(
          color: 0xFF808080,
          metallic: 1,
          roughness: 0.8,
        ).encode(),
      );
      write(
        'mossy.material.json',
        const MaterialFile(
          parent: 'rock.material.json',
          color: 0xFF4C7A3A,
          roughness: 0.3,
          overrides: {'color', 'roughness'},
        ).encode(),
      );
    });

    testWidgets("one value back to the parent's, then all", (tester) async {
      final state = await open(tester);
      expect(find.byTooltip("Its own: back to the parent's"), findsWidgets);
      state.revert('roughness');
      expect(state.material.overrides, {'color'});
      expect(state.shown.roughness, 0.8);
      state.revertAll();
      expect(state.material.overrides, isEmpty);
      expect(state.shown.color, 0xFF808080);
      state.undo();
      state.undo();
      expect(state.material.overrides, {'color', 'roughness'});
    });

    testWidgets('its own values written into the parent', (tester) async {
      final state = await open(tester);
      final applied = await tester.runAsync(
        () => state.applyToParent(confirm: false),
      );
      expect(applied, isTrue);
      final rock = MaterialFile.parse(read('rock.material.json'));
      expect([rock.color, rock.roughness, rock.metallic], [0xFF4C7A3A, 0.3, 1]);
      expect(rock.isVariant, isFalse);
      expect(state.material.overrides, isEmpty, reason: 'its own let go');
      expect(state.shown.color, 0xFF4C7A3A, reason: 'from the parent now');
      expect(reloaded, ['rock.material.json']);
      expect(state.dirty, isTrue, reason: 'the variant is saved by hand');
    });

    testWidgets('into a parent that is itself a variant', (tester) async {
      write('stone.material.json', const MaterialFile(roughness: 1).encode());
      write(
        'rock.material.json',
        const MaterialFile(
          parent: 'stone.material.json',
          metallic: 1,
          overrides: {'metallic'},
        ).encode(),
      );
      final state = await open(tester);
      await tester.runAsync(() => state.applyToParent(confirm: false));
      final rock = MaterialFile.parse(read('rock.material.json'));
      expect(rock.parent, 'stone.material.json');
      expect(rock.overrides, {'metallic', 'color', 'roughness'});
      expect(rock.roughness, 0.3);
    });
  });

  group('a 2-D variant', () {
    Future<Material2DWorkspaceState> open(
      WidgetTester tester, {
      Engine? engine,
    }) async {
      bigView(tester);
      final scope = engine == null
          ? EditorScope(world: World()..initialize(), modules: const [])
          : EditorScope(engine: engine, modules: const []);
      addTearDown(scope.dispose);
      final key = GlobalKey<Material2DWorkspaceState>();
      await tester.pumpWidget(
        host(
          Material2DWorkspace(
            key: key,
            path: 'dark.material2d.json',
            root: dir.path,
            workspace: WorkspaceContext(
              scope: scope,
              onClose: () {},
              path: 'dark.material2d.json',
            ),
            loadOnStart: false,
          ),
        ),
      );
      final state = key.currentState!;
      await tester.runAsync(state.load);
      await tester.pump();
      return state;
    }

    setUp(() {
      write(
        'base.material2d.json',
        jsonEncode({
          'outline': {'width': 2},
          'tint': {'colour': 0xFFFF0000},
        }),
      );
      write(
        'dark.material2d.json',
        jsonEncode({
          'parent': 'base.material2d.json',
          'outline': {'colour': 0xFF0000FF},
          'tint': false,
        }),
      );
    });

    testWidgets("a value, an effect, then everything back to the parent's", (
      tester,
    ) async {
      final state = await open(tester);
      expect(state.shown.isOn('tint'), isFalse, reason: 'its own switch');
      expect(state.shown.colour('outline.colour'), 0xFF0000FF);
      expect(state.shown.number('outline.width'), 2, reason: "the parent's");
      // The outline is on, so its card comes first (its switch, its
      // colour); the tint the variant switched off is in the list to add.
      final revert = find.byTooltip("Its own: back to the parent's");
      expect(revert, findsNWidgets(3), reason: 'outline and its colour; tint');
      await tester.tap(revert.last);
      await tester.pump();
      expect(state.shown.isOn('tint'), isTrue, reason: "the parent's again");
      expect(state.material.effects.containsKey('tint'), isFalse);
      // Then the outline: its switch and its colour both.
      await tester.tap(revert.first);
      await tester.pump();
      expect(state.material.effects, isEmpty);
      expect(state.material.values, isEmpty);
      expect(revert, findsNothing);
      state.undo();
      state.undo();
      state.revertAll();
      expect(state.material.effects, isEmpty);
      expect(state.material.values, isEmpty);
    });

    testWidgets('its own written into the parent', (tester) async {
      final state = await open(tester);
      await settle(tester, state);
      await tester.runAsync(() => state.applyToParent(confirm: false));
      final base = Material2DFile.parse(read('base.material2d.json'));
      expect(base.isOn('tint'), isFalse);
      expect(base.colour('outline.colour'), 0xFF0000FF);
      expect(base.number('outline.width'), 2);
      expect(state.material.effects, isEmpty);
      expect(state.material.values, isEmpty);
    });

    testWidgets('unsaved edits drawn in the open scene until saved or '
        'closed', (tester) async {
      final engine = Engine();
      await tester.runAsync(engine.initialize);
      addTearDown(engine.dispose);
      final game = Material2DLibrary.of(engine.context);
      final state = await open(tester, engine: engine);
      expect(state.liveInScene, isTrue);
      expect(game.isPreviewing('dark.material2d.json'), isFalse);
      state.preview((m) => m.withValue('outline.width', 5.0));
      expect(game.isPreviewing('dark.material2d.json'), isTrue);
      expect(
        game.sourceOf('dark.material2d.json')!.number('outline.width'),
        5,
        reason: 'what is being dragged',
      );
      state.endPreview();
      expect(game.isPreviewing('dark.material2d.json'), isFalse);
      state.change((m) => m.withValue('outline.width', 4.0));
      expect(game.isPreviewing('dark.material2d.json'), isTrue);
      state.setLiveInScene(false);
      expect(game.isPreviewing('dark.material2d.json'), isFalse);
      state.setLiveInScene(true);
      await tester.runAsync(state.save);
      expect(
        game.isPreviewing('dark.material2d.json'),
        isFalse,
        reason: 'saved: the file is drawn',
      );
      state.change((m) => m.withValue('outline.width', 3.0));
      expect(game.isPreviewing('dark.material2d.json'), isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(
        game.isPreviewing('dark.material2d.json'),
        isFalse,
        reason: 'closed unsaved: put back',
      );
    });
  });

  testWidgets('3-D: unsaved edits drawn in the open scene until saved or '
      'closed', (tester) async {
    bigView(tester);
    write('a.material.json', const MaterialFile(roughness: 0.5).encode());
    final engine = Engine(config: EngineConfig(graphics3D: Graphics3D()));
    await tester.runAsync(engine.initialize);
    addTearDown(engine.dispose);
    final game = engine.service<Graphics3D>().sceneRenderer.materials;
    final scope = EditorScope(engine: engine, modules: const []);
    addTearDown(scope.dispose);
    final key = GlobalKey<MaterialWorkspaceState>();
    await tester.pumpWidget(
      host(
        MaterialWorkspace(
          key: key,
          path: 'a.material.json',
          root: dir.path,
          pictures: MaterialPictures(root: dir.path),
          workspace: WorkspaceContext(
            scope: scope,
            onClose: () {},
            path: 'a.material.json',
          ),
          loadOnStart: false,
        ),
      ),
    );
    final state = key.currentState!;
    await tester.runAsync(state.load);
    expect(state.sceneMaterials, same(game));
    expect(game.isPreviewing('a.material.json'), isFalse);
    state.preview((m) => m.copyWith(roughness: 0.1));
    expect(game.isPreviewing('a.material.json'), isTrue);
    expect(game.sourceOf('a.material.json')!.roughness, 0.1);
    state.change((m) => m.copyWith(roughness: 0.2));
    expect(game.sourceOf('a.material.json')!.roughness, 0.2);
    await tester.runAsync(state.save);
    expect(game.isPreviewing('a.material.json'), isFalse);
    state.change((m) => m.copyWith(roughness: 0.9));
    expect(game.isPreviewing('a.material.json'), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(game.isPreviewing('a.material.json'), isFalse);
  });

  group('New variant', () {
    test('beside the material, taking everything from it', () async {
      final module = BuiltInMaterialsModule(root: dir.path);
      addTearDown(module.dispose);
      write('assets/m/rock.material.json', const MaterialFile().encode());
      write('assets/m/hit.material2d.json', jsonEncode({'kind': 'screen'}));
      final a = await module.newVariant('assets/m/rock.material.json');
      final b = await module.newVariant('assets/m/rock.material.json');
      final c = await module.newVariant('assets/m/hit.material2d.json');
      expect(a, 'assets/m/rock_variant.material.json');
      expect(b, 'assets/m/rock_variant_2.material.json');
      expect(c, 'assets/m/hit_variant.material2d.json');
      expect(MaterialFile.parse(read(a)).parent, 'assets/m/rock.material.json');
      final flat = Material2DFile.parse(read(c));
      expect(flat.parent, 'assets/m/hit.material2d.json');
      expect(
        MaterialChain.resolve2D(c, (p) {
          final f = File('${dir.path}/$p');
          return f.existsSync()
              ? Material2DFile.parse(f.readAsStringSync())
              : null;
        }).value.kind,
        Material2DKind.screen,
        reason: "its parent's kind",
      );
      final action = module.assetActions.firstWhere(
        (x) => x.id == BuiltInMaterialsModule.newVariantId,
      );
      expect(action.appliesTo(a, isDirectory: false), isTrue);
      expect(action.appliesTo(c, isDirectory: false), isTrue);
      expect(action.appliesTo('assets/m', isDirectory: true), isFalse);
      expect(action.appliesTo('assets/m/x.png', isDirectory: false), isFalse);
    });
  });
}
