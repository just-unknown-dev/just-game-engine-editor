// A vector in the inspector is one row — its label, then a cell per axis —
// not a row per number.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

Future<void> _pump(WidgetTester tester, Widget child, {double width = 320}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

Widget _editor(
  EditorScope scope,
  ComponentDefinition definition,
  String fieldName,
  Component component, {
  bool readOnly = false,
}) {
  final field = definition.fields.firstWhere((f) => f.name == fieldName);
  return scope.fieldEditors.build(
    FieldEditorContext(
      field: field,
      hint: definition.hints.fields[field.name] ?? const FieldHint(),
      value: field.read(component),
      component: component,
      editors: scope.fieldEditors,
      readOnly: readOnly,
      onChanged: (v) => field.write!(component, v),
    ),
  );
}

void main() {
  testWidgets('the axes share a row, under one label', (tester) async {
    await _pump(
      tester,
      AxesFieldRow(
        label: 'Scale',
        axes: const ['X', 'Y', 'Z'],
        values: const [1, 2, 3],
        scrubConfig: const NumberScrubConfig(fractionDigits: 1),
        onChanged: (_) {},
      ),
    );
    expect(find.text('Scale'), findsOneWidget);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    final tops = {for (var i = 0; i < 3; i++) tester.getRect(fields.at(i)).top};
    expect(tops, hasLength(1), reason: 'one row');
    expect(
      tester.getRect(fields.at(0)).right,
      lessThan(tester.getRect(fields.at(1)).left),
    );
    // The label sits beside them, in the inspector's label column.
    expect(
      tester.getRect(find.text('Scale')).right,
      lessThanOrEqualTo(tester.getRect(find.text('X')).left),
    );
    expect(tester.getRect(find.text('X')).left, 96);
  });

  testWidgets('editing one axis leaves the others', (tester) async {
    List<double>? out;
    await _pump(
      tester,
      AxesFieldRow(
        label: 'Position',
        axes: const ['X', 'Y'],
        values: const [10, 20],
        scrubConfig: const NumberScrubConfig(fractionDigits: 1),
        onChanged: (v) => out = v,
      ),
    );
    await _type(tester, find.byType(TextField).at(1), '42.5');
    expect(out, [10, 42.5]);

    out = null;
    await _type(tester, find.byType(TextField).at(0), 'abc');
    expect(out?.first ?? 0, 0, reason: 'not a number is not a value');
  });

  testWidgets('a narrow panel moves the label up; the axes stay together', (
    tester,
  ) async {
    await _pump(
      tester,
      width: 236,
      AxesFieldRow(
        label: 'Scale',
        axes: const ['X', 'Y', 'Z'],
        values: const [1, 1, 1],
        scrubConfig: const NumberScrubConfig(fractionDigits: 1),
        onChanged: (_) {},
      ),
    );
    final fields = find.byType(TextField);
    final tops = {for (var i = 0; i < 3; i++) tester.getRect(fields.at(i)).top};
    expect(tops, hasLength(1));
    expect(
      tester.getRect(find.text('Scale')).bottom,
      lessThanOrEqualTo(tops.single),
    );
    expect(tester.takeException(), isNull, reason: 'nothing overflows');
  });

  testWidgets('read-only shows the numbers and nothing to type in', (
    tester,
  ) async {
    await _pump(
      tester,
      AxesFieldRow(
        label: 'Position',
        axes: const ['X', 'Y'],
        values: const [3, 4.5],
        scrubConfig: const NumberScrubConfig(fractionDigits: 1),
        readOnly: true,
        onChanged: (_) => fail('read-only'),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('3.0'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
  });

  testWidgets('vector fields use it, one axis at a time', (tester) async {
    final scope = testScope();
    final transform = TransformComponent();
    final definition = scope.definitions.definitionFor(transform)!;
    await _pump(tester, _editor(scope, definition, 'position', transform));
    expect(find.byType(AxesFieldRow), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byTooltip('Position Y'), findsOneWidget);

    await _type(tester, find.byType(TextField).at(1), '64');
    expect(transform.position.y, 64);
    expect(transform.position.x, 0);
  });

  testWidgets('numbers a definition pairs up share a row, each its own field', (
    tester,
  ) async {
    final scope = testScope();
    final framing = CameraFramingComponent();
    var changes = 0;
    await _pump(
      tester,
      SingleChildScrollView(
        child: DefinitionSection(
          component: framing,
          definition: scope.definitions.definitionFor(framing)!,
          scope: scope,
          onDelete: () {},
          onChanged: () => changes++,
        ),
      ),
    );
    // Screen position, dead zone, soft zone, damping: four rows of two.
    expect(find.byType(AxesFieldRow), findsNWidgets(4));
    expect(find.text('Dead zone'), findsOneWidget);
    expect(find.text('Width'), findsNothing);

    final height = find.descendant(
      of: find.byTooltip('Dead zone H'),
      matching: find.byType(TextField),
    );
    final before = framing.deadZoneWidth;
    await _type(tester, height, '0.4');
    expect(framing.deadZoneHeight, 0.4);
    expect(framing.deadZoneWidth, before, reason: 'only the edited field');
    expect(changes, greaterThan(0));
  });

  testWidgets('every row a definition declares names fields it has', (
    tester,
  ) async {
    final scope = testScope();
    for (final definition in scope.definitions.definitions) {
      final names = {for (final f in definition.fields) f.name};
      for (final row in definition.hints.fieldRows) {
        expect(
          names.containsAll(row.cells.keys),
          isTrue,
          reason: '${definition.type}: ${row.label}',
        );
      }
    }
  });
}
