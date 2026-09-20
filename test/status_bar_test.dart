// The status bar: quick facts about the project, and one big button.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/compact_dock.dart';

void main() {
  late JustGameEditorPlugin plugin;

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1600, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Engine.resetInstance();
    final engine = Engine();
    await tester.runAsync(engine.initialize);
    plugin = JustGameEditorPlugin(engine: engine);
    await tester.runAsync(plugin.onInitialize);
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

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    plugin.dispose();
    Engine.resetInstance();
  }

  /// Facts refresh on a timer; give it a turn.
  Future<void> refresh(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 600));

  testWidgets('it comes and goes with the editor; F1 is its only switch', (
    tester,
  ) async {
    if (!kDebugMode) return;
    await pump(tester);
    // The editor opens on launch, and the bar with it.
    expect(plugin.isVisible.value, isTrue);
    await tester.pump();
    expect(find.byType(DockStatusStrip), findsOneWidget);

    plugin.setVisible(false);
    await tester.pump();
    expect(find.byType(DockStatusStrip), findsNothing, reason: 'editor shut');

    plugin.setVisible(true);
    await tester.pump();
    await tester.pump();
    expect(find.byType(DockStatusStrip), findsOneWidget);
    expect(
      tester.getSize(find.byType(DockStatusStrip)).height,
      OverlayLayout.compactDockPanelHeight,
    );
    expect(OverlayLayout.compactDockPanelHeight, 26, reason: 'one line');

    plugin.setVisible(false);
    await tester.pump();
    expect(find.byType(DockStatusStrip), findsNothing);
    await done(tester);
  });

  testWidgets('facts: the scene, what is wrong, what is selected', (
    tester,
  ) async {
    if (!kDebugMode) return;
    await pump(tester);
    plugin.setVisible(true);
    await tester.pump();
    await refresh(tester);
    expect(find.text('No scene'), findsOneWidget);

    plugin.sceneState.openScene(Scene(name: 'level_01'), const {});
    final hero = plugin.engine.world.createEntityWithComponents([
      TransformComponent(position: Vector3(120, 48, 0)),
    ], name: 'Hero');
    plugin.sceneState
      ..syncEntityNode(hero)
      ..selectEntity(hero)
      ..markDirty();
    await refresh(tester);
    expect(
      find.descendant(
        of: find.byType(DockStatusStrip),
        matching: find.text('level_01'),
      ),
      findsOneWidget,
    );
    expect(find.text('● unsaved'), findsOneWidget);
    expect(find.text('Hero'), findsWidgets);
    expect(find.text('120, 48'), findsOneWidget);

    // Trouble shows only when there is some.
    expect(find.byTooltip('1 errors in the Console'), findsNothing);
    final before = plugin.logService.entries.value
        .where((e) => e.level == DebuggerLogLevel.error)
        .length;
    plugin.logService.log('boom', level: DebuggerLogLevel.error);
    await refresh(tester);
    expect(
      find.byTooltip('${before + 1} errors in the Console'),
      findsOneWidget,
    );

    plugin.playController.play();
    await refresh(tester);
    expect(find.text('▶ playing'), findsOneWidget);
    plugin.playController.stop();
    await done(tester);
  });
}
