// The editor's dropdown is a field like the ones beside it, not a 48 px
// Material control dropped into a column of 28 px inputs.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 320, child: child),
      ),
    ),
  ),
);

void main() {
  testWidgets('a dropdown row is as tall as the text row beside it', (
    tester,
  ) async {
    await _pump(
      tester,
      Column(
        children: [
          TextEditorRow(
            label: 'Tag',
            initialValue: 'player',
            onSubmitted: (_) {},
          ),
          DropdownEditorRow(
            label: 'Standby',
            value: 'never',
            options: const ['never', 'always'],
            onChanged: (_) {},
          ),
        ],
      ),
    );
    final dropdown = tester.getSize(find.byType(EditorDropdown<String>));
    final text = tester.getSize(find.byType(TextFormField));
    // Not a guessed constant: sized the way the text field is, so they agree
    // at any font and text scale.
    expect(dropdown.height, text.height);
    expect(dropdown.width, text.width, reason: 'the same column');
  });

  testWidgets('the list opens below the field, ticks the current value, and '
      'reports the choice', (tester) async {
    String? chosen;
    await _pump(
      tester,
      DropdownEditorRow(
        label: 'Standby',
        value: 'never',
        options: const ['never', 'always'],
        onChanged: (v) => chosen = v,
      ),
    );
    final field = tester.getRect(find.byType(EditorDropdown<String>));
    await tester.tap(find.byType(EditorDropdown<String>));
    await tester.pumpAndSettle();

    final always = tester.getRect(find.text('always'));
    expect(always.top, greaterThanOrEqualTo(field.bottom), reason: 'below');
    expect(always.height, lessThanOrEqualTo(EditorDropdown.itemHeight));
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'a short list');

    await tester.tap(find.text('always'));
    await tester.pumpAndSettle();
    expect(chosen, 'always');
    expect(find.text('always'), findsNothing, reason: 'the list has closed');
  });

  testWidgets('dismissing the list changes nothing', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      DropdownEditorRow(
        label: 'Mode',
        value: 'a',
        options: const ['a', 'b'],
        onChanged: (_) => calls++,
      ),
    );
    await tester.tap(find.byType(EditorDropdown<String>));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('a searchable list filters as you type; Enter takes the first', (
    tester,
  ) async {
    String? chosen;
    await _pump(
      tester,
      DropdownEditorRow(
        label: 'Follow',
        value: '(none)',
        options: const ['(none)', 'Boss', 'Platform_1', 'Platform_2', 'Player'],
        searchable: true,
        onChanged: (v) => chosen = v,
      ),
    );
    await tester.tap(find.byType(EditorDropdown<String>));
    await tester.pumpAndSettle();
    expect(find.text('Boss'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'plat');
    await tester.pumpAndSettle();
    expect(find.text('Boss'), findsNothing);
    expect(find.text('Platform_1'), findsOneWidget);
    expect(find.text('Platform_2'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(chosen, 'Platform_1');
  });

  testWidgets('what was typed may be used when the row allows it', (
    tester,
  ) async {
    String? chosen;
    Future<void> open({required bool allowCustom}) async {
      await _pump(
        tester,
        DropdownEditorRow(
          key: ValueKey(allowCustom),
          label: 'Follow',
          value: 'Boss',
          options: const ['Boss'],
          searchable: true,
          allowCustom: allowCustom,
          onChanged: (v) => chosen = v,
        ),
      );
      await tester.tap(find.byType(EditorDropdown<String>));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Hero');
      await tester.pumpAndSettle();
    }

    await open(allowCustom: false);
    expect(find.text('Nothing matches'), findsOneWidget);
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();

    await open(allowCustom: true);
    await tester.tap(find.text('Use "Hero"'));
    await tester.pumpAndSettle();
    expect(chosen, 'Hero');
  });

  testWidgets('a toolbar dropdown is only as wide as its label', (
    tester,
  ) async {
    await _pump(
      tester,
      Row(
        children: [
          EditorDropdown<String>(
            value: null,
            hint: 'clip',
            isExpanded: false,
            height: 22,
            options: const [EditorDropdownOption(value: 'run', label: 'run')],
            onChanged: (_) {},
          ),
        ],
      ),
    );
    final size = tester.getSize(find.byType(EditorDropdown<String>));
    expect(size.height, 22);
    expect(size.width, lessThan(120));
    expect(find.text('clip'), findsOneWidget);
  });

  test('no stock Material dropdown is left in the editor', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      if (RegExp(r'\bDropdownButton(FormField)?<').hasMatch(source)) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty, reason: 'use EditorDropdown');
  });
}
