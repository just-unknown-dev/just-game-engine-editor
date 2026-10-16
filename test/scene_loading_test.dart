// Opening a scene shows how far it has got: the file read, the entities
// made, and the sprites, tile maps and models they ask for, waited on until
// they are in. A quick open shows nothing at all.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/assets/asset_load_counter.dart';
import 'package:just_game_engine_editor/src/ui/overlay/start/scene_loading_view.dart';

import 'support/memory_settings_store.dart';
import 'support/test_scope.dart';

void main() {
  group('SceneLoading', () {
    test('a quick open never shows the loader', () {
      final loading = SceneLoading();
      loading.begin('level_01');
      expect(loading.isLoading, isTrue);
      expect(loading.progress.value!.stage, SceneLoadStage.read);

      loading.report(SceneLoadStage.build, done: 1, total: 2);
      loading.tick();
      expect(loading.isShown.value, isFalse);

      loading.end();
      expect(loading.isLoading, isFalse);
      expect(loading.progress.value, isNull);
    });

    test('shows once the open has run a while, and stays a moment', () {
      final held = SceneLoading(
        showAfter: Duration.zero,
        showFor: const Duration(hours: 1),
      );
      held.begin('level_01');
      held.tick();
      expect(held.isShown.value, isTrue);

      held.end();
      // Over, and full: the editor takes edits again, the card stays.
      expect(held.isLoading, isFalse);
      expect(held.progress.value!.isFinished, isTrue);
      expect(held.progress.value!.fraction, 1);
      held.tick();
      expect(held.isShown.value, isTrue);

      final brief =
          SceneLoading(showAfter: Duration.zero, showFor: Duration.zero)
            ..begin('level_01')
            ..tick()
            ..end()
            ..tick();
      expect(brief.isShown.value, isFalse);
      expect(brief.progress.value, isNull);
    });

    test('the bar never goes back, though a step finds more to do', () {
      final loading = SceneLoading()..begin('level_01');
      loading.report(SceneLoadStage.build, done: 5, total: 10);
      final halfway = loading.progress.value!.fraction;
      expect(halfway, closeTo(0.35, 1e-9));

      loading.report(SceneLoadStage.build, done: 5, total: 20);
      expect(loading.progress.value!.fraction, halfway);
      expect(loading.progress.value!.total, 20);

      loading.report(SceneLoadStage.assets);
      expect(loading.progress.value!.fraction, closeTo(0.6, 1e-9));
    });

    test('waits on the assets until nothing has loaded for a few updates', () {
      final loading = SceneLoading()..begin('level_01');
      var tally = (done: 0, total: 2);
      loading.watchAssets(() => tally);
      expect(loading.isWaitingOnAssets, isTrue);

      for (var i = 0; i < 5; i++) {
        loading.tick();
      }
      expect(loading.isLoading, isTrue);
      expect(loading.progress.value!.total, 2);
      expect(loading.progress.value!.done, 0);

      tally = (done: 2, total: 2);
      loading
        ..tick()
        ..tick();
      // A tile map's tilesets can start a frame after the map: not yet.
      expect(loading.isLoading, isTrue);
      expect(loading.progress.value!.done, 2);
      loading.tick();
      expect(loading.isLoading, isFalse);
    });

    test('skip shows the scene before its assets are in — not before it '
        'is built', () {
      final loading = SceneLoading()..begin('level_01');
      loading.skip();
      expect(loading.isLoading, isTrue, reason: 'still being built');

      loading.watchAssets(() => (done: 0, total: 3));
      loading.skip();
      expect(loading.isLoading, isFalse);
      expect(loading.progress.value, isNull);
    });

    test('gives up waiting when nothing arrives', () {
      final loading = SceneLoading(giveUpAfter: Duration.zero)
        ..begin('level_01')
        ..watchAssets(() => (done: 0, total: 1))
        ..tick();
      expect(loading.isLoading, isFalse);
    });
  });

  test('the counter counts arrivals, failures too, from its last '
      'restart', () async {
    final counter = AssetLoadCounter();
    final slow = Completer<int>();
    unawaited(counter.track(Future<int>.value(1)));
    counter.track(Future<int>.error('missing')).ignore();
    unawaited(counter.track(slow.future));
    await pumpEventQueue();
    expect(counter.started, 3);
    expect(counter.finished, 2);
    expect(counter.pending, 1);

    counter.restart();
    slow.complete(2);
    await pumpEventQueue();
    // A load from before the restart is not this round's.
    expect(counter.started, 0);
    expect(counter.finished, 0);
  });

  group('opening through SceneIO', () {
    late Directory project;
    late EditorScope scope;
    late SceneIO io;

    setUp(() {
      project = Directory.systemTemp.createTempSync('scene_loading_test');
      Directory('${project.path}/assets/scenes').createSync(recursive: true);
      File(
        '${project.path}/assets/scenes/level_test.scene.json',
      ).writeAsStringSync(
        jsonEncode({
          'version': SceneFormat.current,
          ...EditorScene(name: 'level_test').toJson(),
          'entities': [
            for (var i = 0; i < 300; i++)
              {
                'name': 'Block $i',
                'parentName': i == 0 ? null : 'Block 0',
                'components': [
                  {
                    'type': 'TransformComponent',
                    'fields': {
                      'position': {'x': i * 16.0, 'y': 0.0},
                    },
                  },
                ],
              },
          ],
        }),
      );
      scope = testScope(scenesRoot: '${project.path}/assets/scenes');
      io = SceneIO(
        scope: scope,
        world: () => scope.world,
        sceneState: scope.sceneState,
      );
      addTearDown(() {
        if (project.existsSync()) project.deleteSync(recursive: true);
      });
    });

    test('an open goes through its steps, counting the entities', () async {
      final seen = <SceneLoadProgress>[];
      final stop = io.loading.progress.watch(() {
        final p = io.loading.progress.value;
        if (p != null) seen.add(p);
      });
      addTearDown(stop);

      await io.open('level_test');

      expect(seen.map((p) => p.stage), contains(SceneLoadStage.read));
      final built = seen.where((p) => p.stage == SceneLoadStage.build);
      expect(built.map((p) => p.total), everyElement(300));
      expect(built.last.done, 300);
      expect(io.loading.progress.value, isNull, reason: 'over, unseen');

      // Still linked, with the frames it may have let through.
      final root = scope.world.findEntityByName('Block 0')!;
      expect(root.getComponent<ChildrenComponent>()!.childIds, hasLength(299));
      expect(scope.sceneState.rootOrder(scope.world), [root.id]);
    });

    test('with assets to count, the open waits on them', () async {
      await io.open('level_test', assets: () => (done: 0, total: 1));
      expect(io.loading.isWaitingOnAssets, isTrue);
      expect(io.isBusy, isFalse, reason: 'the scene itself is open');
    });

    test('an open that fails takes the loader with it', () async {
      final broken = SceneIO(
        scope: scope,
        world: () => throw StateError('no world'),
        sceneState: scope.sceneState,
      );
      await expectLater(broken.open('level_test'), throwsStateError);
      expect(broken.loading.isLoading, isFalse);
      expect(broken.loading.progress.value, isNull);
    });
  });

  group('the card', () {
    Future<void> show(
      WidgetTester tester,
      SceneLoadProgress progress, {
      VoidCallback? onSkip,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: SceneLoadingCard(progress: progress, onSkip: onSkip),
            ),
          ),
        ),
      ),
    );

    testWidgets('names the scene, the step under way and its count', (
      tester,
    ) async {
      await show(
        tester,
        const SceneLoadProgress(
          sceneName: 'level_01',
          stage: SceneLoadStage.build,
          done: 120,
          total: 450,
          fraction: 0.23,
        ),
      );
      expect(find.text('Opening level_01'), findsOneWidget);
      expect(find.text('23%'), findsOneWidget);
      expect(find.text('Creating the entities…'), findsOneWidget);
      expect(find.text('120 of 450'), findsOneWidget);
      for (final stage in SceneLoadStage.values) {
        expect(find.text(stage.label), findsOneWidget);
      }
      // The scene is not built yet: nothing to show now.
      final button = tester.widget<EditorButton>(
        find.widgetWithText(EditorButton, 'Show now'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('offers to show the scene while its assets arrive', (
      tester,
    ) async {
      var skipped = false;
      await show(
        tester,
        const SceneLoadProgress(
          sceneName: 'level_01',
          stage: SceneLoadStage.assets,
          done: 3,
          total: 8,
          fraction: 0.75,
        ),
        onSkip: () => skipped = true,
      );
      expect(find.text('3 of 8'), findsOneWidget);
      expect(find.text('Esc'), findsOneWidget);
      await tester.tap(find.text('Show now'));
      expect(skipped, isTrue);
    });
  });

  group('in the editor', () {
    testWidgets('the loader covers the editor while a scene opens, and '
        'goes once it has', (tester) async {
      if (!kDebugMode) return;
      tester.view
        ..physicalSize = const Size(1400, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final engine = Engine();
      addTearDown(engine.dispose);
      await tester.runAsync(engine.initialize);
      final scope = EditorScope(
        builtIns: const [BuiltInEditorModule.new],
        engine: engine,
        settingsStore: MemorySettingsStore(),
      );
      final plugin = JustGameEditorPlugin(engine: engine, scope: scope);
      await tester.runAsync(plugin.onInitialize);
      plugin.setVisible(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JustGameEditorOverlay(
              plugin: plugin,
              gameChild: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(SceneLoadingCard), findsNothing);

      final loading = plugin.sceneIO.loading;
      loading
        ..begin('level_01')
        ..report(SceneLoadStage.build, done: 40, total: 100);
      // Past the moment it waits before showing.
      loading.isShown.value = true;
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Opening level_01'), findsOneWidget);
      expect(find.text('40 of 100'), findsOneWidget);
      // Over the viewport, the backdrop: no half-built level.
      final cover = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(SceneLoadingCover),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(cover.opacity, 1);

      loading
        ..watchAssets(() => (done: 0, total: 1))
        ..skip();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SceneLoadingCard), findsNothing);

      plugin.playController.stop();
      await tester.pumpWidget(const SizedBox());
      plugin.dispose();
      scope.dispose();
    });
  });
}
