// Pressing Play gives the keyboard to the game. It used not to: after typing
// in the inspector the keys kept going to that text field, and the player
// stood still until the editor was restarted.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/editor_overlay.dart';

void main() {
  testWidgets('Play takes the keyboard back from a text field', (tester) async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await tester.runAsync(engine.initialize);
    final plugin = JustGameEditorPlugin(engine: engine);
    await tester.runAsync(() => plugin.attach(plugin.engine));
    final typing = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JustGameEditorOverlay(
            plugin: plugin,
            gameChild: Stack(
              children: [
                GameWidget(engine: engine, showFPS: false),
                // Stands in for an inspector field.
                SizedBox(width: 120, child: TextField(focusNode: typing)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    bool gameHasKeyboard() {
      final context = FocusManager.instance.primaryFocus?.context;
      return context != null &&
          context.findAncestorWidgetOfExactType<GameWidget>() != null;
    }

    typing.requestFocus();
    await tester.pump();
    expect(typing.hasPrimaryFocus, isTrue);

    plugin.playController.play();
    await tester.pump();
    expect(typing.hasFocus, isFalse);
    expect(gameHasKeyboard(), isTrue);

    // Pausing to change a value and resuming hands it back again.
    plugin.playController.pause();
    typing.requestFocus();
    await tester.pump();
    expect(gameHasKeyboard(), isFalse);
    plugin.playController.play();
    await tester.pump();
    expect(gameHasKeyboard(), isTrue);

    plugin.playController.stop();
    await tester.pumpWidget(const SizedBox());
    typing.dispose();
    plugin.dispose();
  });
}
