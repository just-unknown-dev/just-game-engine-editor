// The dock panel's state: a dock popped out into its own window is never
// built in the panel as well, a dock opened again takes its args again, and
// the counts on the status bar are this session's.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_game_engine/just_game_engine.dart' show Engine;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/shell/built_in_docks.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/dock_controller.dart';

void main() {
  group('popped out', () {
    late DockController dock;
    setUp(() {
      dock = DockController()
        ..pin('logs')
        ..pin('assets')
        ..pin('fps');
    });
    tearDown(() => dock.dispose());

    test('opening it brings its window forward, not a copy in the panel', () {
      dock
        ..popOut('assets')
        ..popOut('fps')
        ..open('logs');
      dock.open('assets');
      expect(dock.activeDock, 'logs', reason: 'the panel keeps its dock');
      expect(dock.poppedOut.value.last, 'assets', reason: 'in front');
    });

    test('next and previous, and the panel coming back, skip it', () {
      dock
        ..popOut('assets')
        ..open('logs');
      dock.cycle(1);
      expect(dock.activeDock, 'fps');
      dock.cycle(1);
      expect(dock.activeDock, 'logs');

      dock
        ..open('fps')
        ..popOut('fps');
      expect(dock.activeDock, 'logs', reason: 'what is left in the panel');
      dock
        ..close()
        ..togglePanel();
      expect(dock.activeDock, isNot('fps'));
      expect(dock.activeDock, isNot('assets'));
    });

    test('taking the open tab off the bar does not open a popped-out one', () {
      dock
        ..popOut('logs')
        ..open('assets')
        ..unpin('assets');
      expect(dock.activeDock, 'fps');
    });
  });

  test('opened again with the same args, a dock is handed them again', () {
    final dock = DockController()..pin('logs');
    addTearDown(dock.dispose);
    const args = {'level': 'error'};
    dock.open('logs', args: args);
    final first = dock.openArgs;
    dock.open('logs', args: args);
    expect(dock.openArgs, args);
    expect(identical(dock.openArgs, first), isFalse);
  });

  test("the status bar counts this session's errors, not the ones loaded "
      'back from earlier sessions', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final engine = Engine();
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);
    addTearDown(() async {
      plugin.dispose();
      await engine.dispose();
    });
    EditorLogEntry error(DateTime at) => EditorLogEntry(
      message: 'boom',
      source: 'game',
      category: 't',
      level: DebuggerLogLevel.error,
      timestamp: at,
    );
    plugin.logService.entries.value = [
      error(plugin.sessionStartedAt.subtract(const Duration(days: 1))),
      error(plugin.sessionStartedAt.subtract(const Duration(days: 1))),
      error(plugin.sessionStartedAt.add(const Duration(seconds: 1))),
    ];
    expect(BuiltInDocks.sessionLogCounts(plugin), (errors: 1, warnings: 0));
  });
}
