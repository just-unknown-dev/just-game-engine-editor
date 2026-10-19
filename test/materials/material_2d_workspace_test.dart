// 2-D materials in the editor: their kind, workspace and New actions, a
// picture drawn as the game draws it, and the workspace — its sections by
// kind, an effect's values shown once it is on, presets as one undo step,
// a value being dragged drawn without an undo step, a variant's own
// values, a kind change dropping what does not fit, and the preview's
// subject and light.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_material_2d');
    addTearDown(() {
      // A read a widget test's frozen clock never let finish may still
      // hold a file open; the folder goes with the next clean-up.
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Left for the system's own clean-up.
      }
    });
  });

  void write(String path, Map<String, Object?> json) {
    File('${dir.path}/$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(json));
  }

  group('the module', () {
    late BuiltInMaterialsModule module;

    setUp(() {
      module = BuiltInMaterialsModule(root: dir.path);
    });

    test('2-D materials are their own kind and open in their workspace', () {
      final scope = EditorScope(
        world: World()..initialize(),
        modules: [module],
      );
      addTearDown(scope.dispose);
      const path = 'assets/fx/hit.material2d.json';
      expect(scope.assetKinds.of(path).id, 'material2D');
      expect(
        scope.assetKinds.of('assets/fx/stone.material.json').id,
        'material',
        reason: 'the 3-D kind keeps its own',
      );
      final byId = {for (final w in module.workspaces) w.id: w};
      expect(
        byId[BuiltInMaterialsModule.workspace2DId]!.matchOf(path),
        greaterThan(0),
      );
      expect(byId[BuiltInMaterialsModule.workspaceId]!.matchOf(path), 0);
      expect(
        module.assetActions.map((a) => a.id),
        containsAll([
          BuiltInMaterialsModule.newMaterial2DId,
          BuiltInMaterialsModule.newScreenMaterialId,
        ]),
      );
      expect(module.dataFileSuffixes, contains(Material2DFile.ending));
    });

    test('New 2D and screen materials, never over another', () async {
      final sprite = await module.newMaterial2D('assets/fx');
      final again = await module.newMaterial2D('assets/fx/');
      final screen = await module.newMaterial2D(
        'assets/fx',
        kind: Material2DKind.screen,
      );
      expect(sprite, 'assets/fx/material.material2d.json');
      expect(again, 'assets/fx/material_2.material2d.json');
      expect(screen, 'assets/fx/screen.material2d.json');
      Material2DFile read(String p) =>
          Material2DFile.parse(File('${dir.path}/$p').readAsStringSync());
      expect(read(sprite).kind, Material2DKind.sprite);
      expect(read(screen).kind, Material2DKind.screen);
      expect(read(screen).validate(), isEmpty);
    });

    test('a picture drawn as the game draws it, drawn again when it '
        'changes', () async {
      write('hit.material2d.json', {
        'flash': {'colour': 0xFFFF0000, 'amount': 1},
      });
      final pictures = Material2DPictures(root: dir.path, size: 64);
      addTearDown(pictures.dispose);
      final image = await pictures.of('hit.material2d.json');
      expect(image, isNotNull);
      final data = (await image!.toByteData())!;
      int at(ByteData d, int x, int y, int c) =>
          d.getUint8((y * 64 + x) * 4 + c);
      expect(at(data, 28, 28, 0), greaterThan(200), reason: 'flashed red');
      expect(at(data, 28, 28, 1), lessThan(60));

      final before = pictures.revision.value;
      pictures.forget('hit.material2d.json');
      expect(pictures.revision.value, greaterThan(before));
      expect(pictures.peek('hit.material2d.json'), isNull, reason: 'stale');
    });
  });

  group('the workspace', () {
    late EditorScope scope;

    Future<Material2DWorkspaceState> open(
      WidgetTester tester,
      String path,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      scope = EditorScope(world: World()..initialize(), modules: const []);
      addTearDown(scope.dispose);
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

    // The Add effect menu, opened: it fades in, and the window's ticker
    // never lets the frames settle.
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.text('Add effect'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a sprite material: its groups to add from; an effect on '
        'shows its values', (tester) async {
      write('a.material2d.json', {});
      final state = await open(tester, 'a.material2d.json');
      await openMenu(tester);
      // A group's name finds all of it, wherever it is in the list.
      for (final h in ['COLOUR', 'EDGES', 'MOTION', 'LIGHT']) {
        await tester.enterText(
          find.widgetWithText(TextField, 'Search effects'),
          h.toLowerCase(),
        );
        await tester.pump();
        expect(find.text(h), findsOneWidget, reason: h);
      }
      await tester.enterText(find.byType(TextField).last, 'frame');
      await tester.pump();
      expect(find.text('THE FRAME'), findsNothing);
      await tester.enterText(find.byType(TextField).last, '');
      await tester.pump();
      expect(find.text('Width'), findsNothing);
      await tester.tap(find.text('Outline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Width'), findsOneWidget, reason: "the outline's");
      expect(state.material.isOn('outline'), isTrue);
      expect(find.text('COLOUR'), findsNothing, reason: 'the menu closed');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a screen material: the frame and colour; switching kind '
        'drops what does not fit', (tester) async {
      write('a.material2d.json', {
        'outline': {'width': 2},
        'greyscale': {'amount': 0.5},
      });
      final state = await open(tester, 'a.material2d.json');
      state.change((m) => m.copyWith(kind: Material2DKind.screen));
      // Through the kind switch, as the workspace does it.
      state.undo();
      await tester.tap(find.text('Screen'));
      await tester.pump();
      expect(state.material.kind, Material2DKind.screen);
      expect(state.material.isOn('outline'), isFalse, reason: 'sprites only');
      expect(state.material.values.containsKey('outline.width'), isFalse);
      expect(state.material.isOn('greyscale'), isTrue, reason: 'both kinds');
      await openMenu(tester);
      expect(find.text('THE FRAME'), findsOneWidget);
      expect(find.text('EDGES'), findsNothing);
      expect(find.text('LIGHT'), findsNothing, reason: 'a screen is not lit');
      await tester.tapAt(const Offset(4, 4));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a preset is one undo step', (tester) async {
      write('a.material2d.json', {});
      final state = await open(tester, 'a.material2d.json');
      state.change(Material2DPreset.byId('water')!.apply);
      expect(state.material.isOn('scroll'), isTrue);
      expect(state.material.isOn('wave'), isTrue);
      expect(state.material.validate(), isEmpty);
      state.undo();
      expect(state.material.effects, isEmpty);
      expect(state.dirty, isFalse);
      for (final p in Material2DPreset.all) {
        expect(
          p.apply(Material2DFile(kind: p.kind)).validate(),
          isEmpty,
          reason: p.id,
        );
      }
    });

    testWidgets('a value being dragged is drawn, not an undo step', (
      tester,
    ) async {
      write('a.material2d.json', {
        'flash': {'amount': 0.2},
      });
      final state = await open(tester, 'a.material2d.json');
      state.preview((m) => m.withValue('flash.amount', 0.9));
      expect(state.shown.number('flash.amount'), 0.9);
      expect(state.material.number('flash.amount'), 0.2);
      expect(state.dirty, isFalse);
      expect(state.stage.library.isPreviewing('a.material2d.json'), isTrue);
      expect(
        state.stage.library
            .sourceOf('a.material2d.json')!
            .number('flash.amount'),
        0.9,
        reason: 'the stage draws it',
      );
      state.endPreview();
      expect(state.shown.number('flash.amount'), 0.2);
    });

    testWidgets("a variant: its parent's effects, and an edit becomes its "
        'own', (tester) async {
      write('base.material2d.json', {
        'kind': 'screen',
        'vignette': {'amount': 0.4},
      });
      write('dark.material2d.json', {'parent': 'base.material2d.json'});
      final state = await open(tester, 'dark.material2d.json');
      expect(state.shown.kind, Material2DKind.screen, reason: "its parent's");
      expect(state.shown.isOn('vignette'), isTrue);
      expect(state.shown.number('vignette.amount'), 0.4);
      expect(find.textContaining('Variant of base.material2d.json'), findsOne);
      state.change((m) => m.withValue('vignette.amount', 0.8));
      expect(state.material.values, {'vignette.amount': 0.8});
      expect(state.shown.number('vignette.amount'), 0.8);
      // Its parent's effect switched off in the variant alone.
      state.change((m) => m.withEffect('vignette', false));
      expect(state.shown.isOn('vignette'), isFalse);
      await tester.runAsync(state.save);
      final saved = Material2DFile.parse(
        File('${dir.path}/dark.material2d.json').readAsStringSync(),
      );
      expect(saved.parent, 'base.material2d.json');
      expect(saved.effects, {'vignette': false});

      // Off here alone: listed under the cards, with a way back.
      await tester.pump();
      expect(find.text('OFF IN THIS VARIANT'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Vignette'),
            matching: find.byType(Row),
          ),
          matching: find.byTooltip("Its own: back to the parent's"),
        ),
      );
      await tester.pump();
      expect(state.shown.isOn('vignette'), isTrue, reason: "the parent's");
      expect(find.text('OFF IN THIS VARIANT'), findsNothing);
    });

    testWidgets('the preview: subject, light, and the selected sprite', (
      tester,
    ) async {
      write('a.material2d.json', {});
      final state = await open(tester, 'a.material2d.json');
      expect(state.lit, isFalse);
      state.setLit(true);
      expect(state.stage.lit, isTrue);
      state.setSubject(Material2DSubject.selected);
      expect(state.selectedSprite, isNull);
      await tester.pump();
      expect(find.textContaining('Select a sprite in the scene'), findsOne);
      final image = await tester.runAsync(() async {
        final r = ui.PictureRecorder();
        ui.Canvas(r).drawRect(
          const ui.Rect.fromLTWH(0, 0, 4, 4),
          ui.Paint()..color = const ui.Color(0xFF00FF00),
        );
        return r.endRecording().toImage(4, 4);
      });
      final hero = scope.world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: Sprite(image: image)),
      ]);
      scope.sceneState.selectedEntity.value = hero;
      await tester.pump();
      expect(state.selectedSprite?.image, same(image));
      expect(find.textContaining('Select a sprite in the scene'), findsNothing);
      state
        ..setSubject(Material2DSubject.sample)
        ..setLit(false);
    });

    testWidgets('a normal map turns the light on as it opens', (tester) async {
      write('bumpy.material2d.json', {
        'normalMap': {'map': 'n.png'},
      });
      final state = await open(tester, 'bumpy.material2d.json');
      expect(state.lit, isTrue);
    });
  });

  group('the list editors', () {
    test('a stop goes into the widest gap, its colour between', () {
      final next = GradientStopsEditor.withOneMore(const [
        (0.0, 0xFF000000),
        (0.2, 0xFF000000),
        (1.0, 0xFFFFFFFF),
      ]);
      expect(next.map((s) => s.$1), [0.0, 0.2, 0.6, 1.0]);
      final mid = ui.Color(next[2].$2);
      expect((mid.r * 255).round(), closeTo(128, 2));
    });

    test('a swap starts from a colour not swapped yet', () {
      const colours = Material2DSamples.spriteColours;
      final next = ColourSwapsEditor.withOneMore([
        (colours[0], 0xFF000000),
      ], colours);
      expect(next.last, (colours[1], colours[1]));
      expect(ColourSwapsEditor.withOneMore(const [], const []).single, (
        0xFF000000,
        0xFFFFFFFF,
      ));
    });
  });
}
