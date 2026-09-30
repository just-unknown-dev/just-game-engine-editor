// The save footer always says where the scene stands, and says it legibly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  testWidgets(
    'Saved when clean, UNSAVED when dirty, and Save explains itself',
    (tester) async {
      Engine.resetInstance();
      // A scene is opened below, and the panel beside the footer lists the
      // world's entities — so the engine has to be a running one.
      final engine = Engine();
      await tester.runAsync(engine.initialize);
      final plugin = JustGameEditorPlugin(engine: engine, startVisible: false);
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
      plugin.toggleVisibility();
      plugin.sceneState.openScene(Scene(name: 'level'));
      await tester.pumpAndSettle();

      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('UNSAVED'), findsNothing);
      expect(find.byTooltip('Nothing to save'), findsOneWidget);

      plugin.sceneState.markDirty();
      await tester.pumpAndSettle();
      expect(find.text('UNSAVED'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      expect(find.byTooltip('Save scene  (Ctrl+S)'), findsOneWidget);
      // The key is on the button too, not only in the tooltip.
      expect(find.text('Ctrl+S'), findsOneWidget);

      // As tall as the editor's other controls, not a 32 px block.
      final button = find.ancestor(
        of: find.text('Save'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(button.first).height, 28);

      plugin.dispose();
      Engine.resetInstance();
    },
  );

  testWidgets('a badge is tinted with its accent, not filled with it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: EditorBadge(
            label: 'UNSAVED',
            accent: EditorTheme.warning,
            showDot: true,
          ),
        ),
      ),
    );
    // White on the warning yellow was unreadable; the accent is the text now.
    final text = tester.widget<Text>(find.text('UNSAVED'));
    expect(text.style!.color, EditorTheme.warning);
    final box = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.text('UNSAVED'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final fill = (box.decoration as BoxDecoration).color!;
    expect(fill.a, lessThan(0.3), reason: 'a tint, not a block of colour');
  });
}
