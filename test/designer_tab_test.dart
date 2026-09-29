// While the Level Designer is open its panel is a tab of the right panel —
// Inspector | Level — so the level keeps the width of the editor's one
// panel instead of losing another beside it.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/editor_overlay.dart'
    show GameCanvasArea;

void main() {
  late JustGameEditorPlugin plugin;

  Future<void> start(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Engine.resetInstance();
    final engine = Engine();
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
    plugin.sceneState.openScene(Scene(name: 'level'), const {});
    await tester.pump();
  }

  Future<void> stop(WidgetTester tester) async {
    plugin.closeLevelDesigner();
    await tester.pumpWidget(const SizedBox());
    plugin.dispose();
    Engine.resetInstance();
  }

  testWidgets('opening the designer shows its tab, and the level keeps its '
      'width', (tester) async {
    if (!kDebugMode) return;
    await start(tester);
    final before = tester.getRect(find.byType(GameCanvasArea)).width;
    expect(find.text('Level'), findsNothing, reason: 'no tabs yet');

    plugin.openLevelDesigner();
    await tester.pump();
    await tester.pump();
    expect(find.text('Inspector'), findsOneWidget);
    expect(find.text('Level'), findsOneWidget);
    expect(find.text('LAYERS'), findsOneWidget, reason: 'the Level tab is up');
    expect(
      tester.getRect(find.byType(GameCanvasArea)).width,
      before,
      reason: 'no second panel beside the right one',
    );

    await tester.tap(find.text('Inspector'));
    await tester.pump();
    expect(find.text('LAYERS'), findsNothing);
    expect(
      plugin.scope.chrome.rightPanelTab.value,
      EditorChromeState.inspectorTab,
    );

    plugin.closeLevelDesigner();
    await tester.pump();
    expect(find.text('Level'), findsNothing, reason: 'tabs go with it');
    await stop(tester);
  });
}
