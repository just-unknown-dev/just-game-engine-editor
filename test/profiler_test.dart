// The profiler: frames kept, a frame looked at, and what each system cost.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/profiler/frame_capture.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/profiler/profiler_dock.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/shell/built_in_docks.dart';
import 'package:just_game_engine/just_game_engine.dart' show Engine;

import 'support/test_scope.dart';

PerformanceDebuggerSnapshot _frame(
  int n,
  double ms, {
  Map<String, double> systems = const {},
}) => PerformanceDebuggerSnapshot(
  frameNumber: n,
  lastUpdateMs: ms,
  currentFps: 60,
  systemTimesMs: systems,
);

void main() {
  test("the editor gives it each frame as it runs, not the debugger's "
      'few samples a second', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final engine = Engine();
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);
    await plugin.attach(plugin.engine);
    addTearDown(() async {
      plugin.dispose();
      await engine.dispose();
    });
    final capture = BuiltInDocks.frameCaptureOf(plugin);

    // The debugger's poll no longer feeds it.
    plugin.debuggerController.notifyListeners();
    expect(capture.samples, isEmpty);

    plugin.update(1 / 60);
    expect(capture.samples, hasLength(1));
    expect(capture.samples.single.frame, engine.performanceStats['frame']);

    capture.paused = true;
    plugin.update(1 / 60);
    expect(capture.samples, hasLength(1), reason: 'paused');
  });

  test('it keeps the last frames, once each', () {
    final capture = FrameCapture(capacity: 3);
    for (var i = 1; i <= 5; i++) {
      capture
        ..add(_frame(i, i.toDouble()))
        ..add(_frame(i, 99), entities: 7); // the same frame again: ignored
    }
    expect([for (final s in capture.samples) s.frame], [3, 4, 5]);
    expect(capture.worstMs, 5);
    expect(capture.averageMs, 4);
  });

  test('looking at a frame pauses; resuming follows the newest again', () {
    final capture = FrameCapture();
    var notified = 0;
    capture.addListener(() => notified++);
    for (var i = 1; i <= 4; i++) {
      capture.add(_frame(i, 10));
    }
    capture.select(1);
    expect(capture.paused, isTrue);
    expect(capture.selected!.frame, 2);
    capture.add(_frame(5, 10));
    expect(capture.samples, hasLength(4), reason: 'held still');

    capture.paused = false;
    capture.add(_frame(6, 10));
    expect(capture.selectedIndex, isNull);
    expect(capture.selected!.frame, 6);
    expect(notified, greaterThan(5));
  });

  test('spikes are frames over budget, whichever budget that is', () {
    final capture = FrameCapture();
    for (final (i, ms) in [10.0, 20.0, 40.0].indexed) {
      capture.add(_frame(i + 1, ms));
    }
    expect(capture.spikes, 2, reason: '60 fps: 16.7 ms');
    capture.budgetMs = 1000 / 30;
    expect(capture.spikes, 1);
  });

  test('systems: average, worst and share over the window', () {
    final capture = FrameCapture()
      ..add(_frame(1, 5, systems: {'Physics': 3, 'Render': 1}))
      ..add(_frame(2, 9, systems: {'Physics': 5, 'Render': 1, 'AI': 2}));
    final stats = {for (final s in capture.systemStats) s.name: s};
    expect(
      capture.systemStats.first.name,
      'Physics',
      reason: 'costliest first',
    );
    expect(stats['Physics']!.average, 4);
    expect(stats['Physics']!.max, 5);
    expect(stats['Physics']!.share, closeTo(8 / 12, 1e-9));
    expect(stats['AI']!.average, 1, reason: 'absent in a frame is zero there');
    expect(stats['AI']!.selected, 2, reason: 'the newest frame');
    capture.select(0);
    expect(capture.systemStats.firstWhere((s) => s.name == 'AI').selected, 0);

    final json = jsonDecode(capture.toJsonText()) as Map<String, dynamic>;
    expect((json['frames'] as List).length, 2);
  });

  testWidgets('a click on the graph picks that frame', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scope = testScope();
    final capture = FrameCapture();
    addTearDown(capture.dispose);
    for (var i = 1; i <= 120; i++) {
      capture.add(_frame(i, i == 60 ? 40 : 8, systems: {'Physics': 2}));
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfilerDock(
            scope: scope,
            capture: capture,
            dock: DockContext(
              scope: scope,
              height: 300,
              onResize: (_) {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Physics'), findsOneWidget);
    expect(find.textContaining('Frame 120'), findsOneWidget);

    // 120 frames fill the 1200 px graph at 10 px each: frame 60 is at x≈595.
    final graph = tester.getTopLeft(find.byType(CustomPaint).first);
    await tester.tapAt(Offset(595, graph.dy + 120));
    await tester.pump();
    expect(capture.paused, isTrue);
    expect(find.textContaining('Frame 60 · 40.00 ms'), findsOneWidget);
    expect(find.byTooltip('Resume capturing'), findsOneWidget);
  });
}
