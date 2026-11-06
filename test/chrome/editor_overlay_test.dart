import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/chrome/editor_overlay.dart';

import '../support/memory_settings_store.dart';

void main() {
  testWidgets('overlay hidden by default and visible after F1', (tester) async {
    final plugin = JustGameEditorPlugin(engine: Engine());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorOverlay(
            plugin: plugin,
            gameChild: const SizedBox.expand(),
          ),
        ),
      ),
    );

    expect(find.text('Just Runtime Editor'), findsNothing);

    if (!kDebugMode) {
      plugin.dispose();
      return;
    }

    plugin.toggleVisibility();
    await tester.pumpAndSettle();

    expect(find.text('Just Runtime Editor'), findsOneWidget);

    plugin.dispose();
  });

  testWidgets('status panel is shown only while the editor is open', (
    tester,
  ) async {
    final plugin = JustGameEditorPlugin(engine: Engine());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorOverlay(
            plugin: plugin,
            gameChild: const SizedBox.expand(),
          ),
        ),
      ),
    );

    expect(find.text('Status Panel'), findsNothing);

    if (!kDebugMode) {
      plugin.dispose();
      return;
    }

    plugin.isStatusPanelVisible.value = !plugin.isStatusPanelVisible.value;
    await tester.pumpAndSettle();
    expect(find.text('Status Panel'), findsNothing);

    plugin.toggleVisibility();
    await tester.pumpAndSettle();

    expect(find.textContaining(' fps · '), findsOneWidget);
    expect(find.text('No scene'), findsOneWidget);
    expect(find.text('Status Panel'), findsNothing);

    plugin.toggleVisibility();
    await tester.pumpAndSettle();

    expect(find.textContaining(' fps · '), findsNothing);

    plugin.dispose();
  });

  testWidgets('no status badge, and the play controls sit top-left', (
    tester,
  ) async {
    if (!kDebugMode) return;
    final engine = Engine();
    addTearDown(engine.dispose);
    await tester.runAsync(engine.initialize);
    final plugin = JustGameEditorPlugin(engine: engine);
    await tester.runAsync(() => plugin.attach(plugin.engine));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorOverlay(
            plugin: plugin,
            gameChild: const SizedBox.expand(),
          ),
        ),
      ),
    );

    plugin.setVisible(true);
    // The play controls are the level's: they show with a scene open.
    plugin.sceneState.openScene(EditorScene(name: 'level'));
    await tester.pumpAndSettle();

    expect(find.text('EDITOR: OPEN'), findsNothing);
    final screen = tester.getSize(find.byType(EditorOverlay));
    final play = tester.getCenter(find.byTooltip('Play  (F5)'));
    expect(play.dx, lessThan(screen.width / 4), reason: 'left');
    expect(play.dy, lessThan(screen.height / 4), reason: 'top');
    // The game camera preview hangs directly below them.
    expect(plugin.gamePreviewOrigin.dy, greaterThan(play.dy));
    expect(plugin.gamePreviewOrigin.dx, lessThan(play.dx));
    // …in the toolbar's own frame: its border colour and its corners.
    final ui = plugin.scope.prefs.settings.value;
    expect(plugin.gamePreviewStyle.borderColor, ui.accent);
    expect(plugin.gamePreviewStyle.cornerRadius, ui.cornerRadius + 6);

    await tester.pumpWidget(const SizedBox());
    plugin.dispose();
  });

  testWidgets('closing the window with unsaved changes asks in the editor: '
      "Cancel stays, Don't save closes", (tester) async {
    if (!kDebugMode) return;
    final root = Directory.systemTemp.createTempSync('overlay_exit_');
    addTearDown(() => root.deleteSync(recursive: true));
    final engine = Engine();
    addTearDown(engine.dispose);
    await tester.runAsync(engine.initialize);
    final scope = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      engine: engine,
      scenesRoot: root.path,
      settingsStore: MemorySettingsStore(),
    );
    final plugin = JustGameEditorPlugin(engine: engine, scope: scope);
    await tester.runAsync(() => plugin.attach(plugin.engine));
    plugin.setVisible(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorOverlay(
            plugin: plugin,
            gameChild: const SizedBox.expand(),
          ),
        ),
      ),
    );
    plugin.sceneState
      ..openScene(EditorScene(name: 'level'))
      ..markDirty();
    await tester.pumpAndSettle();

    var closing = WidgetsBinding.instance.handleRequestAppExit();
    await tester.pumpAndSettle();
    expect(find.text('Save changes to level?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await closing, AppExitResponse.cancel);
    expect(plugin.sceneState.isDirty.value, isTrue);

    closing = WidgetsBinding.instance.handleRequestAppExit();
    await tester.pumpAndSettle();
    await tester.tap(find.text("Don't save"));
    await tester.pumpAndSettle();
    expect(await closing, AppExitResponse.exit);

    // The overlay gone, there is nobody to ask: a backup is kept instead.
    plugin.playController.stop();
    await tester.pumpWidget(const SizedBox());
    expect(plugin.askToSaveBeforeExit, isNull);
    plugin.dispose();
    scope.dispose();
  });
}
