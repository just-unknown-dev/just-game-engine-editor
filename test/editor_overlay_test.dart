import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  testWidgets('overlay hidden by default and visible after F1', (tester) async {
    Engine.resetInstance();
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
      Engine.resetInstance();
      return;
    }

    plugin.toggleVisibility();
    await tester.pumpAndSettle();

    expect(find.text('Just Runtime Editor'), findsOneWidget);

    plugin.dispose();
    Engine.resetInstance();
  });

  testWidgets('status panel is shown only while the editor is open', (
    tester,
  ) async {
    Engine.resetInstance();
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
      Engine.resetInstance();
      return;
    }

    plugin.toggleStatusPanelVisibility();
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
    Engine.resetInstance();
  });

  testWidgets('no status badge, and the play controls sit top-left', (
    tester,
  ) async {
    Engine.resetInstance();
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
    if (!kDebugMode) {
      plugin.dispose();
      Engine.resetInstance();
      return;
    }

    plugin.toggleVisibility();
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
    expect(plugin.gamePreviewStyle.borderColor, ui.themeColor);
    expect(plugin.gamePreviewStyle.cornerRadius, ui.cornerRadius + 6);

    plugin.dispose();
    Engine.resetInstance();
  });
}
