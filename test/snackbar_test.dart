// Messages stack at the canvas's corner, each following its own task: one
// shown or minimised never cuts another's task off.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/snackbar.dart'
    show EditorSnackBarLayer;

void main() {
  late EditorSnackBarController c;
  setUp(() => c = EditorSnackBarController());
  tearDown(() => c.dispose());

  test('a minimised task goes on while another message shows', () async {
    final task = StreamController<EditorSnackBarStep>();
    final build = c.showSnackBar(
      EditorSnackBarEntry(message: 'Building', progressStream: task.stream),
    );
    c.minimize(build);
    c.showSnackBar(const EditorSnackBarEntry(message: 'Saved'));

    task.add(const EditorSnackBarStep(message: 'step 1'));
    await Future<void>.delayed(Duration.zero);
    expect(build.steps.single.message, 'step 1');
    expect(c.minimized, [build]);
    expect(c.visible.single.entry.message, 'Saved');
    await task.close();
  });

  test('no more than three show; the oldest message makes room', () {
    for (var i = 0; i < 4; i++) {
      c.showSnackBar(EditorSnackBarEntry(message: 'm$i'));
    }
    expect([for (final s in c.visible) s.entry.message], ['m1', 'm2', 'm3']);
  });

  testWidgets('a message goes by itself; a failed task stays', (tester) async {
    final task = StreamController<EditorSnackBarStep>();
    c.showSnackBar(
      const EditorSnackBarEntry(
        message: 'Hello',
        duration: Duration(seconds: 2),
      ),
    );
    final build = c.showSnackBar(
      EditorSnackBarEntry(message: 'Building', progressStream: task.stream),
    );
    task.add(const EditorSnackBarStep(message: 'broke', isError: true));
    await task.close();
    await tester.pump(const Duration(seconds: 10));

    expect(c.visible, [build]);
    expect(build.failed, isTrue);
    c.dismiss(build);
    expect(c.snacks.value, isEmpty);
  });

  testWidgets('the layer shows them, and dismisses one', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditorMessenger(
          child: Builder(
            builder: (context) => Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Builder(
                      builder: (context) {
                        c = EditorMessenger.of(context);
                        return const EditorSnackBarLayer();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    c.showSnackBar(const EditorSnackBarEntry(title: 'Saved', message: 'All'));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Saved'), findsNothing);
  });
}
