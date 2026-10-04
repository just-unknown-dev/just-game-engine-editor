// The settings open from a gear at the foot of the viewport, bottom right,
// in a dialog that holds the keyboard while it is open: typing in it must
// not play the level or pick a tool behind it.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  late JustGameEditorPlugin plugin;

  Future<void> start(WidgetTester tester) async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await tester.runAsync(engine.initialize);
    plugin = JustGameEditorPlugin(engine: engine);
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
  }

  Future<void> stop(WidgetTester tester) async {
    plugin.playController.stop();
    await tester.pumpWidget(const SizedBox());
    plugin.dispose();
  }

  final gear = find.byTooltip('Editor settings  (Ctrl+,)');

  testWidgets('the gear sits bottom right and opens the settings', (
    tester,
  ) async {
    if (!kDebugMode) return;
    await start(tester);

    expect(gear, findsOneWidget);
    final at = tester.getRect(gear);
    final window = tester.view.physicalSize / tester.view.devicePixelRatio;
    // The canvas ends where the right panel starts.
    final canvasRight =
        window.width - plugin.scope.chrome.rightPanelWidth.value;
    expect(canvasRight - at.right, lessThan(40), reason: 'at the right');
    expect(at.top, greaterThan(window.height / 2), reason: 'at the foot');

    await tester.tap(gear);
    await tester.pumpAndSettle();
    expect(find.text('Editor Settings'), findsOneWidget);
    expect(plugin.scope.chrome.settingsOpen.value, isTrue);

    await stop(tester);
  });

  testWidgets('while it is open the level\'s keys stand down; Esc and '
      'Ctrl+, shut it', (tester) async {
    if (!kDebugMode) return;
    await start(tester);
    // F5 plays the scene open.
    plugin.sceneState.openScene(EditorScene(name: 'level'));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(plugin.scope.chrome.settingsOpen.value, isTrue);

    // F5 is Play, whenever the editor is open — but not over the settings.
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    expect(plugin.playController.state.value, EditorPlayState.stopped);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(plugin.scope.chrome.settingsOpen.value, isFalse);
    expect(find.text('Editor Settings'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    expect(plugin.playController.state.value, EditorPlayState.playing);

    await stop(tester);
  });

  testWidgets('an accent picked recolours the chrome, not just the settings', (
    tester,
  ) async {
    if (!kDebugMode) return;
    addTearDown(() => EditorTheme.apply(EditorThemeData.classic));
    await start(tester);
    final scope = plugin.scope;
    final cobalt = scope.theme.preset('cobalt')!.data.primary;

    unawaited(
      scope.prefs.update(
        scope.prefs.settings.value.copyWith(themeId: 'cobalt', accent: cobalt),
      ),
    );
    // The frame eases into its new colour: a frame to start, one to end.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(EditorTheme.accent, cobalt);

    // The gear's frame, drawn in the accent, was built again in the new one.
    final frame = find.ancestor(
      of: gear,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).border is Border,
      ),
    );
    final decoration =
        tester.widget<Container>(frame.first).decoration! as BoxDecoration;
    expect((decoration.border! as Border).top.color, cobalt);

    await stop(tester);
  });

  testWidgets('the designer\'s grid size is kept through other changes', (
    tester,
  ) async {
    if (!kDebugMode) return;
    await start(tester);
    final prefs = plugin.scope.prefs;

    plugin.setGridSize(48);
    await tester.pump();
    expect(prefs.settings.value.gridSize, 48);

    // Any other change used to put the grid back to what was saved. (The
    // value is set at once; the write to disk is not waited for here.)
    unawaited(prefs.update(prefs.settings.value.copyWith(cornerRadius: 8)));
    await tester.pump();
    await tester.pump();
    expect(plugin.gridSize.value, 48);

    await stop(tester);
  });
}
