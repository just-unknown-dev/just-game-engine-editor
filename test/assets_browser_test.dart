// The asset browser on screen, and an asset dropped into the level.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/assets/asset_index.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/assets/assets_browser.dart';

import 'support/test_scope.dart';

class _Memory implements DockMemory {
  final Map<String, Object?> values = {};

  @override
  T? read<T>(String key) => values[key] is T ? values[key] as T : null;

  @override
  void write(String key, Object? value) => values[key] = value;
}

void main() {
  late Directory dir;
  late AssetIndex index;

  void write(String path, [String content = 'x']) => File('${dir.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('assets_browser');
    write('assets/sprites/hero.json', '{}');
    write('assets/sprites/coin.json', '{}');
    write('assets/audio/jump.wav');
    write(
      'assets/scenes/level.scene.json',
      '{"a": "assets/sprites/hero.json"}',
    );
    index = AssetIndex(projectRoot: dir.path);
  });
  tearDown(() {
    index.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<(_Memory, EditorScope)> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1400, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(index.scan);
    final scope = testScope();
    final memory = _Memory();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorScopeProvider(
            scope: scope,
            child: AssetsBrowserDock(
              scope: scope,
              index: index,
              dock: DockContext(
                scope: scope,
                height: 400,
                onResize: (_) {},
                onClose: () {},
                memory: memory,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (memory, scope);
  }

  /// File operations are real I/O started from the test's fake clock: each
  /// step finishes on the real one and continues on the fake one, so both
  /// get turns until the chain has run out.
  Future<void> io(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  testWidgets('folders lead somewhere, and the way back is on the toolbar', (
    tester,
  ) async {
    final (memory, _) = await pump(tester);
    expect(find.text('sprites'), findsWidgets);
    expect(
      find.text('hero.json'),
      findsNothing,
      reason: 'one folder at a time',
    );

    await tester.tap(find.text('sprites').first);
    await tester.pump();
    expect(find.text('hero.json'), findsOneWidget);
    expect(find.text('coin.json'), findsOneWidget);
    expect(memory.values['dir'], 'assets/sprites', reason: 'remembered');

    // A search looks under the open folder; the breadcrumb goes back up.
    await tester.enterText(find.byType(TextField), 'coin');
    await tester.pump();
    expect(find.text('hero.json'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('assets').first);
    await tester.pump();
    expect(find.text('hero.json'), findsNothing);
  });

  testWidgets('a file that is in use says so before it is deleted, and the '
      'delete can be taken back', (tester) async {
    await pump(tester);
    await tester.tap(find.text('sprites').first);
    await tester.pump();
    await tester.tap(find.text('hero.json'));
    await tester.pump();
    expect(
      find.textContaining('Data · 2 B'),
      findsOneWidget,
      reason: 'preview',
    );

    await tester.tap(find.byTooltip('Delete (to the trash)'));
    await io(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('level.scene.json'), findsOneWidget);
    await tester.tap(find.text('Delete anyway'));
    await io(tester);
    await tester.pumpAndSettle();
    expect(File('${dir.path}/assets/sprites/hero.json').existsSync(), isFalse);
    expect(find.text('hero.json'), findsNothing);

    await tester.tap(find.text('Restore'));
    await io(tester);
    expect(File('${dir.path}/assets/sprites/hero.json').existsSync(), isTrue);
    expect(find.text('hero.json'), findsWidgets);
    // Let the "restore" bar's timer run out before the test ends.
    await tester.pump(const Duration(seconds: 13));
  });

  testWidgets('renaming a used file offers to update what uses it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('sprites').first);
    await tester.pump();
    await tester.tap(find.text('hero.json'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'knight.json',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Rename'));
    await io(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename and update'));
    await io(tester);
    await io(tester);
    expect(File('${dir.path}/assets/sprites/knight.json').existsSync(), isTrue);
    expect(
      File('${dir.path}/assets/scenes/level.scene.json').readAsStringSync(),
      contains('"assets/sprites/knight.json"'),
    );
    // The watcher's debounce timer: let it run out before the test ends.
    await tester.pump(const Duration(milliseconds: 400));
  });

  group('dropped on the viewport', () {
    late JustGameEditorPlugin plugin;
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      plugin = JustGameEditorPlugin(engine: engine);
      await plugin.onInitialize();
    });
    tearDown(() {
      plugin.dispose();
    });

    test('an image is a sprite there; an atlas or a project animates', () {
      expect(
        plugin.dropAsset('assets/a.png', Offset.zero),
        isNull,
        reason: 'no scene',
      );
      plugin.sceneState.openScene(EditorScene(name: 'level'));
      final camera = plugin.engine.cameraSystem.mainCamera
        ..viewportSize = const Size(800, 600);
      final where = camera.screenToWorld(const Offset(200, 150));

      final still = plugin.dropAsset(
        'assets/sprites/tree.png',
        const Offset(200, 150),
      )!;
      expect(still.name, 'tree');
      final sprite = still.getComponent<SpriteComponent>()!;
      expect(
        (sprite.spritePath, sprite.pixelArt),
        ('assets/sprites/tree.png', true),
      );
      final at = still.getComponent<TransformComponent>()!.position;
      expect((at.x, at.y), (where.dx, where.dy));
      expect(plugin.sceneState.selectedEntity.value, same(still));

      final fromProject = plugin.dropAsset(
        'assets/sprites/hero.jsprite',
        Offset.zero,
      )!;
      expect(
        fromProject.getComponent<SpriteAnimationComponent>()!.atlasPath,
        'assets/sprites/hero.json',
        reason: 'the atlas saved beside the project',
      );
      expect(
        plugin.dropAsset('assets/scenes/l.scene.json', Offset.zero),
        isNull,
      );
      // A sound: a looping source of it, flat in a 2-D scene.
      final sound = plugin.dropAsset('assets/audio/wind.wav', Offset.zero)!;
      expect(sound.name, 'wind');
      final source = sound.getComponent<AudioSourceComponent>()!;
      expect((source.clipPath, source.loop, source.is3d), ('assets/audio/wind.wav', true, false));
    });
  });
}
