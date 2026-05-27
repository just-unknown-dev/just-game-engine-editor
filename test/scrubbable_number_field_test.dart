import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/src/ui/widgets/scrubbable_number_field.dart';

void main() {
  testWidgets('mouse horizontal drag increases and decreases value', (
    tester,
  ) async {
    final controller = TextEditingController(text: '10.0');
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ScrubbableNumberField(
              label: 'X',
              controller: controller,
              focusNode: focusNode,
              onCommit: () {},
              config: const NumberScrubConfig(
                step: 1,
                pixelsPerStep: 10,
                fractionDigits: 1,
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final labelFinder = find.text('X');
    final start = tester.getCenter(labelFinder);

    await gesture.addPointer(location: start);
    await tester.pump();
    await gesture.moveTo(start);
    await tester.pump();

    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(Offset(start.dx + 30, start.dy));
    await tester.pump();
    expect(controller.text, '13.0');

    await gesture.moveTo(Offset(start.dx - 20, start.dy));
    await tester.pump();
    expect(controller.text, '8.0');

    await gesture.up();
    await tester.pump();
  });

  testWidgets('clamps to min and max while scrubbing', (tester) async {
    final controller = TextEditingController(text: '0.50');
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ScrubbableNumberField(
              label: 'Progress',
              controller: controller,
              focusNode: focusNode,
              onCommit: () {},
              config: const NumberScrubConfig(
                step: 0.1,
                pixelsPerStep: 10,
                fractionDigits: 2,
                min: 0,
                max: 1,
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final start = tester.getCenter(find.text('Progress'));

    await gesture.addPointer(location: start);
    await tester.pump();

    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(Offset(start.dx + 300, start.dy));
    await tester.pump();
    expect(controller.text, '1.00');

    await gesture.moveTo(Offset(start.dx - 300, start.dy));
    await tester.pump();
    expect(controller.text, '0.00');

    await gesture.up();
    await tester.pump();
  });

  testWidgets('typing still works with scrubbable numeric field', (
    tester,
  ) async {
    final controller = TextEditingController(text: '1.0');
    final focusNode = FocusNode();
    var commits = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ScrubbableNumberField(
              label: 'Y',
              controller: controller,
              focusNode: focusNode,
              onCommit: () {
                commits++;
              },
              config: const NumberScrubConfig(
                step: 1,
                pixelsPerStep: 10,
                fractionDigits: 1,
              ),
            ),
          ),
        ),
      ),
    );

    final input = find.byType(TextField);
    await tester.tap(input);
    await tester.pump();
    await tester.enterText(input, '42.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(controller.text, '42.5');
    expect(commits, greaterThan(0));
  });
}
