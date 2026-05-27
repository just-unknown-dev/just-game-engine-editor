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
    plugin.toggleStatusPanelVisibility();
    await tester.pumpAndSettle();

    expect(find.text('FPS'), findsOneWidget);
    expect(find.text('Entities'), findsOneWidget);
    expect(find.text('Status Panel'), findsNothing);

    plugin.toggleVisibility();
    await tester.pumpAndSettle();

    expect(find.text('FPS'), findsNothing);

    plugin.dispose();
    Engine.resetInstance();
  });
}
