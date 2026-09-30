// The Console: what it shows of the log, and the command line under it.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/services/editor_log_entry.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/console/console_dock.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/shell/built_in_docks.dart';

EditorLogEntry _entry(
  String message, {
  DebuggerLogLevel level = DebuggerLogLevel.info,
  String source = 'game',
  String? details,
}) => EditorLogEntry(
  message: message,
  source: source,
  category: 'test',
  level: level,
  timestamp: DateTime(2026, 9, 20, 12, 4, 1),
  details: details,
);

void main() {
  group('what it shows', () {
    final entries = [
      _entry('spawned "Hero"'),
      _entry('tick'),
      _entry('tick'),
      _entry('tick'),
      _entry(
        'body has no shape',
        level: DebuggerLogLevel.warning,
        source: 'physics',
      ),
      _entry('tick'),
      _entry(
        'missing asset',
        level: DebuggerLogLevel.error,
        details: 'hero.png',
      ),
    ];

    test('a run of the same line is one row with a count', () {
      final rows = const ConsoleView().apply(entries);
      expect(rows.map((r) => (r.entry.message, r.count)), [
        ('spawned "Hero"', 1),
        ('tick', 3),
        ('body has no shape', 1),
        ('tick', 1),
        ('missing asset', 1),
      ]);
      expect(const ConsoleView(collapse: false).apply(entries), hasLength(7));
    });

    test('levels, sources and search narrow it; details are searched too', () {
      expect(
        const ConsoleView(levels: {DebuggerLogLevel.error}).apply(entries),
        hasLength(1),
      );
      expect(
        const ConsoleView(
          hiddenSources: {'game'},
        ).apply(entries).single.entry.source,
        'physics',
      );
      expect(const ConsoleView(query: 'HERO').apply(entries), hasLength(2));
      // With the warning filtered out the four ticks are one run.
      final ticks = const ConsoleView(
        query: r'/^(tick|missing)/',
      ).apply(entries);
      expect(ticks.map((r) => r.count), [4, 1]);
      // A pattern that does not compile is searched as text, not an error.
      expect(const ConsoleView(query: '/(/').apply(entries), isEmpty);
      expect(ConsoleView.countLevels(entries), {
        DebuggerLogLevel.info: 5,
        DebuggerLogLevel.warning: 1,
        DebuggerLogLevel.error: 1,
      });
    });
  });

  group('in the editor', () {
    late JustGameEditorPlugin plugin;

    Future<void> pump(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Engine.resetInstance();
      final engine = Engine();
      await tester.runAsync(engine.initialize);
      plugin = JustGameEditorPlugin(engine: engine);
      await tester.runAsync(plugin.onInitialize);
      plugin.setVisible(true);
      if (!plugin.isStatusPanelVisible.value) {
        plugin.toggleStatusPanelVisibility();
      }
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
      plugin.scope.dockController.open(BuiltInDocks.console);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      plugin.dispose();
      Engine.resetInstance();
    }

    void log(
      String message, {
      DebuggerLogLevel level = DebuggerLogLevel.info,
    }) => plugin.logService.log(
      message,
      source: 'game',
      category: 't',
      level: level,
    );

    testWidgets('new lines show; Pause holds them back; a name selects', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await pump(tester);
      final hero = plugin.engine.world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Hero');
      log('spawned "Hero"');
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('spawned "Hero"'), findsOneWidget);

      await tester.tap(find.byTooltip('Select Hero'));
      expect(plugin.sceneState.selectedEntity.value, same(hero));

      await tester.tap(find.byTooltip('Pause: hold the list still'));
      await tester.pump();
      log('while paused', level: DebuggerLogLevel.error);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('while paused'), findsNothing);
      await tester.tap(find.byTooltip('Resume (1 new)'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('while paused'), findsOneWidget);

      // The level chip hides a level, and the choice is remembered.
      await tester.tap(find.text('Errors'));
      await tester.pump();
      expect(find.text('while paused'), findsNothing);
      expect(
        plugin.scope.dockController
            .memoryOf(BuiltInDocks.console)
            .read<List<Object?>>('hiddenLevels'),
        ['error'],
      );
      await done(tester);
    });

    testWidgets('the command line runs editor commands, and only those', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await pump(tester);
      // Play needs a scene to play-test.
      plugin.sceneState.openScene(Scene(name: 'level'));
      expect(
        BuiltInDocks.runCommand(plugin, 'editor.playToggle'),
        contains('Ran'),
      );
      expect(plugin.playController.isRunning, isTrue);
      expect(
        BuiltInDocks.runCommand(plugin, 'stop everything now'),
        contains('No command'),
      );
      expect(BuiltInDocks.runCommand(plugin, 'dock'), startsWith('Which one?'));
      // By label, whatever the case.
      expect(
        BuiltInDocks.runCommand(plugin, 'play / stop'),
        isNot(contains('No command')),
      );
      plugin.playController.stop();

      // Typed into the field: Enter runs it and the result is a log line.
      await tester.enterText(find.byType(TextField).last, 'dock.maximise');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(plugin.scope.dockController.maximised.value, isTrue);
      expect(find.textContaining('> dock.maximise'), findsOneWidget);
      await done(tester);
    });
  });
}
