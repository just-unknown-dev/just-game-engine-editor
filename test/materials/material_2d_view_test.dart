// The 2-D material workspace's preview and panel: zoom and pan, tiling,
// comparing with and without the material, the normals view, the light and
// its settings, the game's sprites to pick from, playing what moves, the
// keys — and effects that are on first, each with what it does, a reset
// and a solo, the rest added from a list.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_material_view');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Left for the system's own clean-up.
      }
    });
  });

  void write(String path, Object json) => File('${dir.path}/$path')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(json));

  List<Sprite> sprites(Material2DStage stage) => [
    for (final e in stage.world.query(const [RenderableComponent]))
      e.getComponent<RenderableComponent>()!.renderable,
  ].whereType<Sprite>().toList();

  group('the stage', () {
    late Material2DStage stage;
    setUp(() {
      write('a.material2d.json', {
        'tint': {'colour': 0xFFFFFFFF},
      });
      stage = Material2DStage(root: dir.path)
        ..show('a.material2d.json', kind: Material2DKind.sprite);
    });
    tearDown(() => stage.dispose());

    test('at 1:1, tiled, moved; without the material', () async {
      stage.zoom = 1;
      await stage.picture(300, 300);
      expect(stage.scale, 1);
      expect(sprites(stage).single.renderSize, const Size(96, 96));

      stage.tiled = true;
      await stage.picture(300, 300);
      expect(sprites(stage), hasLength(9), reason: 'three by three');

      stage
        ..tiled = false
        ..pan = const Offset(20, -10);
      await stage.picture(300, 300);
      final at = stage.world
          .query(const [RenderableComponent])
          .single
          .getComponent<TransformComponent>()!
          .position;
      expect((at.x, at.y), (170.0, 140.0), reason: 'the middle, moved');

      expect(stage.world.query(const [Material2D]), hasLength(1));
      stage.plain = true;
      await stage.picture(300, 300);
      expect(stage.world.query(const [Material2D]), isEmpty);
    });

    test("the light's settings; the normals view lights it", () async {
      stage
        ..show('a.material2d.json', kind: Material2DKind.sprite, lit: true)
        ..lightColour = const Color(0xFFFFAA00)
        ..lightHeight = 0.5
        ..lightReach = 1
        ..lightStrength = 2;
      await stage.picture(200, 100);
      final light = stage.world.query(const [Light2D]).single;
      final l = light.getComponent<Light2D>()!;
      expect(
        [l.colour, l.intensity, l.radius, l.height],
        [const Color(0xFFFFAA00), 2.0, 200.0, 50.0],
      );

      stage
        ..show('a.material2d.json', kind: Material2DKind.sprite)
        ..showNormals = true;
      await stage.picture(200, 100);
      expect(stage.lighting.showNormals, isTrue);
      expect(
        stage.world.query(const [Lighting2D]),
        hasLength(1),
        reason: 'only the lighting has them',
      );
    });
  });

  group('the workspace', () {
    late EditorScope scope;

    Future<Material2DWorkspaceState> open(
      WidgetTester tester,
      String path,
    ) async {
      tester.view.physicalSize = const Size(1600, 1000);
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

    testWidgets('effects on first, with what they do; the rest to add, '
        'searched', (tester) async {
      write('a.material2d.json', {
        'outline': {'width': 2},
      });
      final state = await open(tester, 'a.material2d.json');
      expect(find.text('ON · 1'), findsOneWidget);
      expect(
        find.text(Material2DEffects.byId('outline')!.description),
        findsOneWidget,
        reason: 'what it does, under its name',
      );
      expect(find.text('ADD EFFECT'), findsOneWidget);

      await tester.tap(find.text('Tint'));
      await tester.pump();
      expect(state.material.isOn('tint'), isTrue, reason: 'added');
      expect(find.text('ON · 2'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byType(EditorSearchField),
          matching: find.byType(TextField),
        ),
        'glow',
      );
      await tester.pump();
      expect(find.text('Glow'), findsOneWidget);
      expect(find.text('Flash'), findsNothing, reason: 'not what was asked');
    });

    testWidgets('reset to its defaults; solo shows it alone in the preview', (
      tester,
    ) async {
      write('a.material2d.json', {
        'outline': {'width': 3},
        'tint': {'colour': 0xFF00FF00},
      });
      final state = await open(tester, 'a.material2d.json');
      expect(
        Material2DWorkspaceState.resetEffect(
          state.material,
          'outline',
        ).values.containsKey('outline.width'),
        isFalse,
      );
      await tester.tap(find.byTooltip('Back to its defaults').last);
      await tester.pump();
      expect(state.material.values.containsKey('outline.width'), isFalse);
      expect(state.material.isOn('outline'), isTrue, reason: 'still on');

      state.setSolo('tint');
      await tester.pump();
      final drawn = state.stage.library.sourceOf('a.material2d.json')!;
      expect(
        (drawn.isOn('tint'), drawn.isOn('outline')),
        (true, false),
        reason: 'the preview draws it alone',
      );
      expect(
        state.material.isOn('outline'),
        isTrue,
        reason: 'the file keeps it',
      );
      expect(find.text('Solo: Tint'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Solo: Tint'),
            matching: find.byType(Container),
          ),
          matching: find.byTooltip('Close'),
        ),
      );
      await tester.pump();
      expect(state.solo, isNull);
    });

    testWidgets('zoom, fit; the panel sized by its edge', (tester) async {
      write('a.material2d.json', {});
      final state = await open(tester, 'a.material2d.json');
      await tester.tap(find.text('2×'));
      await tester.pump();
      expect(state.stage.zoom, 2);
      expect(state.plainStage.zoom, 2, reason: 'both drawn alike');
      state.zoomBy(1);
      expect(state.stage.zoom, 3, reason: 'the next whole number');
      await tester.tap(find.text('Fit'));
      await tester.pump();
      expect(state.stage.zoom, isNull);

      final width = state.panelWidth;
      final edge = tester.getTopLeft(find.byType(VerticalDivider).first);
      await tester.dragFrom(edge + const Offset(2, 300), const Offset(80, 0));
      await tester.pump();
      expect(state.panelWidth, closeTo(width + 80, 1));
    });

    testWidgets('keys: tile, normals, light, compare, play, Space held', (
      tester,
    ) async {
      write('a.material2d.json', {
        'scroll': {
          'speed': [10, 0],
        },
      });
      final state = await open(tester, 'a.material2d.json');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      expect(state.stage.tiled, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      expect(state.stage.showNormals, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      expect(state.lit, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      expect(state.compareAt, 0.5);
      expect(find.text('Without'), findsOneWidget);
      expect(find.text('With'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      expect(state.playing, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      expect(state.holdingPlain, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(state.holdingPlain, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      expect(state.stage.zoom, 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      expect(state.stage.zoom, isNull);
    });

    testWidgets('what moves: paused, scrubbed', (tester) async {
      write('a.material2d.json', {
        'scroll': {
          'speed': [10, 0],
        },
      });
      final state = await open(tester, 'a.material2d.json');
      await tester.pump();
      expect(find.byTooltip('Pause (P)'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause (P)'));
      await tester.pump();
      expect(state.playing, isFalse);
      expect(find.byTooltip('Play (P)'), findsOneWidget);
      state.scrub(3);
      expect(state.time, 3);
      expect(state.stage.time, 3);
    });

    testWidgets('the light: settings and presets', (tester) async {
      write('a.material2d.json', {});
      final state = await open(tester, 'a.material2d.json');
      await tester.tap(find.byTooltip('Light settings'));
      await tester.pump();
      expect(find.text('The light'), findsOneWidget);
      await tester.tap(find.text('Above'));
      await tester.pump();
      final (at, height) = Material2DWorkspaceState.lightPresets['Above']!;
      expect(state.lit, isTrue, reason: 'a preset lights it');
      expect((state.stage.light, state.stage.lightHeight), (at, height));
      expect(state.plainStage.lightHeight, height);
      expect(find.byTooltip('The light: drag it'), findsOneWidget);
    });

    testWidgets("the game's sprites drawn with it, to pick from", (
      tester,
    ) async {
      const path = 'assets/m.material2d.json';
      write(path, {
        'normalMap': {'map': 'assets/n.png'},
      });
      Map<String, Object?> user(String name, String image) => {
        'name': name,
        'components': [
          {'type': 'TransformComponent', 'fields': <String, Object?>{}},
          {
            'type': 'SpriteComponent',
            'fields': {'spritePath': image, 'atlasPath': ''},
          },
          {
            'type': 'Material2D',
            'fields': {'material': path},
          },
        ],
      };
      write('assets/scenes/a.scene.json', {
        'entities': [
          user('Rock_1', 'assets/rock.png'),
          user('Rock_2', 'assets/rock.png'),
          user('Wall', 'assets/wall.png'),
        ],
      });
      final state = await open(tester, path);
      await tester.runAsync(() async {
        for (var i = 0; i < 300 && state.user == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      expect(
        [for (final u in state.users) (u.entity, u.count)],
        [('Rock_1', 2), ('Wall', 1)],
        reason: 'the same image once, counted',
      );
      expect(state.user?.entity, 'Rock_1');
      expect(find.textContaining('On Rock_1'), findsOneWidget);
      expect(
        state.shownSpritePath,
        'assets/rock.png',
        reason:
            'what a normal '
            'map would be made from',
      );
      await tester.runAsync(() => state.pickUser(state.users.last));
      await tester.pump();
      expect(state.user?.entity, 'Wall');
      expect(state.shownSpritePath, 'assets/wall.png');
    });
  });
}
