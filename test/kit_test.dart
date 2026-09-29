// The editor's kit: what every panel is built from keeps its promises — a
// target never under 24 px, a toolbar that never spills over its edge, a
// field that keeps what was typed exactly once.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

Widget _host(Widget child, {double width = 400}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  testWidgets('a toolbar narrower than what is in it scrolls, not spills', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        EditorToolbar(
          children: [
            for (var i = 0; i < 12; i++)
              EditorIconButton(
                icon: Icons.star,
                tooltip: 'Star $i',
                onTap: () {},
              ),
            const Spacer(),
            const Text('end'),
          ],
        ),
        width: 120,
      ),
    );
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('wide enough, a Spacer in a toolbar still pushes right', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        EditorToolbar(
          children: [
            EditorIconButton(icon: Icons.star, tooltip: 'Star', onTap: () {}),
            const Spacer(),
            const Text('end'),
          ],
        ),
        width: 400,
      ),
    );
    final bar = tester.getRect(find.byType(EditorToolbar));
    final end = tester.getRect(find.text('end'));
    expect(bar.right - end.right, lessThan(12), reason: 'at the right edge');
  });

  testWidgets('an icon button is never a smaller target than 24 px', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        EditorIconButton(
          icon: Icons.close,
          tooltip: 'Close',
          shortcut: 'Esc',
          onTap: () {},
        ),
      ),
    );
    final size = tester.getSize(
      find
          .descendant(
            of: find.byType(EditorIconButton),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(size.width, greaterThanOrEqualTo(24));
    expect(find.byTooltip('Close  (Esc)'), findsOneWidget);
  });

  testWidgets('a disabled icon button says so by its colour', (tester) async {
    await tester.pumpWidget(
      _host(
        const EditorIconButton(icon: Icons.undo, tooltip: 'Undo', onTap: null),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.undo));
    expect(icon.color!.a, lessThan(0.5));
  });

  testWidgets('a commit field keeps what was typed once: Enter, then the '
      'focus leaving, is one change', (tester) async {
    final kept = <String>[];
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            CommitTextField(value: 'a', onCommit: kept.add),
            const TextField(),
          ],
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'b');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    expect(kept, ['b']);
  });

  testWidgets('a toggle switches, and says what it switches', (tester) async {
    var on = false;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => EditorToggle(
            value: on,
            label: 'Snap',
            onChanged: (v) => setState(() => on = v),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(EditorToggle));
    await tester.pump();
    expect(on, isTrue);
    expect(find.bySemanticsLabel('Snap'), findsOneWidget);
  });
}
