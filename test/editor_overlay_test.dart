import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/editor_overlay.dart';

void main() {
  testWidgets('overlay hidden by default and visible after F1', (tester) async {
    final plugin = JustGameEditorPlugin(engine: Engine());

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
          body: JustGameEditorOverlay(
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
          body: JustGameEditorOverlay(
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
    final screen = tester.getSize(find.byType(JustGameEditorOverlay));
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
}
