// The play toolbar: transport that can be stepped and slowed, keys that work
// while the game owns the letters, and buttons that are not glued together.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/shared_widgets.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/transform_toolbar.dart';
import 'package:just_game_engine_editor/src/core/play/play_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('play controller', () {
    late Engine engine;
    late JustGameEditorPlugin plugin;
    PlayController play() => plugin.playController;

    setUp(() async {
      engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      plugin = JustGameEditorPlugin(engine: engine);
      await plugin.attach(plugin.engine);
      plugin.setVisible(true);
    });
    tearDown(() {
      plugin.dispose();
    });

    test('Step runs exactly one frame and stays paused', () {
      play().play();
      play().pause();
      expect(engine.time.timeScale, 0);

      play().step();
      expect(engine.time.timeScale, 1, reason: 'the next frame will run');
      expect(play().state.value, EditorPlayState.paused);

      plugin.update(1 / 60); // that frame has now run
      expect(engine.time.timeScale, 0);
      plugin.update(1 / 60);
      expect(engine.time.timeScale, 0, reason: 'and only that one');
    });

    test('a press on the play-test holds the pointer for a game that asks; '
        'Pause and Stop let go', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      const channel = MethodChannel('just_inputs/pointer_lock');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'lock' ? true : null;
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        await PointerLock.instance.dispose();
        debugDefaultTargetPlatformOverride = null;
      });
      const press = PointerDownEvent(
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      engine.input.lockPointerOnClick = true;

      plugin.pressedPlayingGame(press);
      await pumpEventQueue();
      expect(calls, isEmpty, reason: 'authoring: the mouse is the editor’s');

      play().play();
      plugin.pressedPlayingGame(press);
      await pumpEventQueue();
      expect(calls, ['lock']);

      play().pause();
      await pumpEventQueue();
      expect(calls.last, 'unlock', reason: 'paused');

      play().togglePause();
      plugin.pressedPlayingGame(press);
      await pumpEventQueue();
      expect(calls.last, 'lock');
      play().stop();
      await pumpEventQueue();
      expect(calls.last, 'unlock', reason: 'stopped');
    });

    test('Step while playing freezes first; while stopped it does nothing', () {
      play().step();
      expect(play().state.value, EditorPlayState.stopped);

      play().play();
      play().step();
      expect(play().state.value, EditorPlayState.paused);
    });

    test('speed applies at once while playing, and on the next Play', () {
      play().setSpeed(0.25);
      expect(engine.time.timeScale, 0, reason: 'not playing yet');
      play().play();
      expect(engine.time.timeScale, 0.25);
      play().setSpeed(2);
      expect(engine.time.timeScale, 2);

      play().pause();
      play().setSpeed(0.5);
      expect(engine.time.timeScale, 0, reason: 'paused stays paused');
      play().step();
      expect(engine.time.timeScale, 0.5, reason: 'a stepped frame is slow too');
    });

    test('elapsed time is game time: scaled by speed, still while paused', () {
      play().setSpeed(2);
      play().play();
      for (var i = 0; i < 60; i++) {
        plugin.update(1 / 60);
      }
      expect(play().elapsedSeconds.value, 2);

      play().pause();
      for (var i = 0; i < 120; i++) {
        plugin.update(1 / 60);
      }
      expect(play().elapsedSeconds.value, 2);
    });

    test('Restart is a fresh run; the toggles do what the keys promise', () {
      play().play();
      for (var i = 0; i < 90; i++) {
        plugin.update(1 / 60);
      }
      expect(play().elapsedSeconds.value, 1);
      play().restart();
      expect(play().state.value, EditorPlayState.playing);
      expect(play().elapsedSeconds.value, 0);

      play().togglePause();
      expect(play().state.value, EditorPlayState.paused);
      play().togglePause();
      expect(play().state.value, EditorPlayState.playing);
      play().togglePlay();
      expect(play().state.value, EditorPlayState.stopped);
      play().togglePause();
      expect(play().state.value, EditorPlayState.stopped);
    });

    test('the play keys are function keys, in scope even mid-play', () {
      const none = ModifierKeys();
      final commands = plugin.scope.commands;
      String? idFor(LogicalKeyboardKey key, [ModifierKeys mods = none]) =>
          commands.resolve(key, mods)?.id;

      expect(idFor(LogicalKeyboardKey.f5), 'editor.playToggle');
      expect(
        idFor(LogicalKeyboardKey.f5, const ModifierKeys(shift: true)),
        'editor.playRestart',
      );
      expect(idFor(LogicalKeyboardKey.f6), 'editor.pauseToggle');
      expect(idFor(LogicalKeyboardKey.f10), 'editor.playStep');
      expect(idFor(LogicalKeyboardKey.f3), 'editor.toggleDesigner');
      expect(idFor(LogicalKeyboardKey.f4), 'editor.togglePreview');
      for (final id in ['editor.playToggle', 'editor.playStep']) {
        expect(commands.byId(id)!.scope, CommandScope.always);
      }
      expect(
        commands.bindingsFor('editor.playRestart').single.shortcut,
        'Shift+F5',
      );
    });
  });

  group('layout', () {
    late JustGameEditorPlugin plugin;
    const settings = OverlayUiSettings.defaults();

    // Initialising the plugin hooks debugPrint for the editor's log, and a
    // widget test checks such hooks are gone before its tear-downs run — so
    // each test puts things back itself, with [done].
    void done() {
      plugin.dispose();
    }

    Future<void> pump(WidgetTester tester, {bool withScene = true}) async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await tester.runAsync(engine.initialize);
      plugin = JustGameEditorPlugin(engine: engine);
      await tester.runAsync(() => plugin.attach(plugin.engine));
      // The transport and the view buttons show with a scene open.
      if (withScene) plugin.sceneState.openScene(EditorScene(name: 'level'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: PlayControlsToolbar(plugin: plugin, settings: settings),
            ),
          ),
        ),
      );
    }

    Rect rectOf(WidgetTester tester, String tooltip) => tester.getRect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == tooltip),
    );

    testWidgets('buttons are 28 px targets with air between them', (
      tester,
    ) async {
      await pump(tester);
      final playButton = rectOf(tester, 'Play  (F5)');
      final pause = rectOf(tester, 'Pause  (F6)');
      expect(playButton.size, const Size(28, 28));
      expect(pause.left - playButton.right, greaterThanOrEqualTo(2));

      // Across a frame boundary the gap is wider than a button's air: the
      // transport ends, and the view-and-mode frame starts with the preview.
      final restart = rectOf(tester, 'Restart  (Shift+F5)');
      final designer = rectOf(tester, 'Open Level Designer  (F3)');
      final preview = rectOf(tester, 'Hide the game camera preview  (F4)');
      expect(preview.left - restart.right, greaterThan(14));
      // Inside that frame the two sit as the transport's buttons do.
      expect(designer.left - preview.right, greaterThanOrEqualTo(2));
      done();
    });

    testWidgets('heightFor is the height it really has', (tester) async {
      await pump(tester);
      expect(
        tester.getSize(find.byType(PlayControlsToolbar)).height,
        PlayControlsToolbar.heightFor(settings),
      );
      done();
    });

    testWidgets('tooltips carry their keys', (tester) async {
      await pump(tester);
      for (final message in [
        'Play  (F5)',
        'Pause  (F6)',
        'Step one frame  (F10)',
        'Restart  (Shift+F5)',
        'Open Level Designer  (F3)',
        'Hide the game camera preview  (F4)',
      ]) {
        expect(find.byTooltip(message), findsOneWidget, reason: message);
      }
      done();
    });

    testWidgets('what the play-test is doing is on the toolbar', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('PLAYING'), findsNothing);

      plugin.playController.play();
      await tester.pump();
      expect(find.text('PLAYING'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.byTooltip('Resume  (F5)'), findsNothing);

      plugin.playController.pause();
      await tester.pump();
      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.byTooltip('Resume  (F5)'), findsOneWidget);

      plugin.playController.stop();
      await tester.pump();
      expect(find.text('PAUSED'), findsNothing);
      done();
    });

    testWidgets('only the transport frame tells the play state: its fill '
        'tinted, its line mixed into the fill', (tester) async {
      await pump(tester);
      List<FloatingToolFrame> frames() => tester
          .widgetList<FloatingToolFrame>(find.byType(FloatingToolFrame))
          .toList();
      // Stopped: every frame has its own accent and fill.
      expect(frames().map((f) => f.borderColor), everyElement(isNull));
      expect(frames().map((f) => f.backgroundColor), everyElement(isNull));

      plugin.playController.play();
      await tester.pump();
      final line = frames().first.borderColor;
      expect(
        line,
        PlayControlsToolbar.transportLine(EditorTheme.success, running: true),
      );
      expect(line, isNot(EditorTheme.success), reason: 'not full strength');
      final fill = frames().first.backgroundColor;
      expect(
        fill,
        PlayControlsToolbar.transportFill(EditorTheme.success, running: true),
      );
      expect(fill, isNot(EditorTheme.statusBadgeBg), reason: 'tinted');
      // The view and the modules' frames do not change.
      expect(frames().skip(1).map((f) => f.borderColor), everyElement(isNull));
      expect(
        frames().skip(1).map((f) => f.backgroundColor),
        everyElement(isNull),
      );
      // One line width in every state: the toolbar does not grow.
      expect(frames().map((f) => f.borderWidth), everyElement(1));
      expect(
        tester.getSize(find.byType(PlayControlsToolbar)).height,
        PlayControlsToolbar.heightFor(settings),
      );

      plugin.playController.pause();
      await tester.pump();
      expect(
        frames().first.borderColor,
        PlayControlsToolbar.transportLine(EditorTheme.warning, running: true),
      );
      expect(
        frames().first.backgroundColor,
        PlayControlsToolbar.transportFill(EditorTheme.warning, running: true),
      );

      plugin.playController.stop();
      await tester.pump();
      expect(frames().map((f) => f.borderColor), everyElement(isNull));
      expect(frames().map((f) => f.backgroundColor), everyElement(isNull));
      done();
    });

    testWidgets('the speed control offers the speeds and sets one', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('1×'), findsOneWidget);
      await tester.tap(find.byType(EditorDropdown<double>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0.25×'));
      await tester.pumpAndSettle();
      expect(plugin.playController.speed.value, 0.25);
      done();
    });

    testWidgets('with no scene open, only what the modules add stays', (
      tester,
    ) async {
      await pump(tester, withScene: false);
      expect(find.byTooltip('Play  (F5)'), findsNothing);
      expect(find.byType(EditorDropdown<double>), findsNothing);
      expect(find.byIcon(Icons.map_outlined), findsNothing);

      plugin.sceneState.openScene(EditorScene(name: 'level'));
      await tester.pump();
      expect(find.byTooltip('Play  (F5)'), findsOneWidget);
      expect(find.byIcon(Icons.map_outlined), findsOneWidget);
      done();
    });
  });
}
