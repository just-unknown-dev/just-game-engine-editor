// A list or a map in the inspector is rows to edit, not JSON to type.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

Future<void> _pump(WidgetTester tester, Widget child, {EditorScope? scope}) {
  final body = SingleChildScrollView(child: SizedBox(width: 320, child: child));
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: scope == null
            ? body
            : EditorScopeProvider(scope: scope, child: body),
      ),
    ),
  );
}

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

void main() {
  testWidgets('a list of values is rows that keep their type', (tester) async {
    Object? out;
    await _pump(
      tester,
      CollectionEditor(
        label: 'Layers',
        value: const [8, 7, 9],
        onChanged: (v) => out = v,
      ),
    );
    expect(find.textContaining('['), findsNothing, reason: 'no JSON');
    expect(find.byType(TextFormField), findsNWidgets(3));
    // The count, and the third row's number.
    expect(find.text('3'), findsNWidgets(2));

    await _type(tester, find.byType(TextFormField).at(1), '42');
    expect(out, [8, 42, 9]);
    expect((out! as List)[1], isA<int>());

    await tester.tap(find.byTooltip('Remove').first);
    expect(out, [7, 9]);

    await tester.tap(find.byTooltip('Add an item'));
    expect(out, [8, 7, 9, 0], reason: 'a blank of the same kind');
  });

  testWidgets('a list of objects is cards, and Add uses the template', (
    tester,
  ) async {
    Object? out;
    const template = {'child': '', 'hold': 1.0, 'blend': 0.5};
    await _pump(
      tester,
      CollectionEditor(
        label: 'Steps',
        value: const [
          {'child': 'Wide', 'hold': 2.0, 'blend': 0.0},
        ],
        template: template,
        onChanged: (v) => out = v,
      ),
    );
    for (final key in ['child', 'hold', 'blend']) {
      expect(find.text(key), findsOneWidget);
    }
    await _type(tester, find.widgetWithText(TextFormField, '2.0'), '3');
    expect(out, [
      {'child': 'Wide', 'hold': 3.0, 'blend': 0.0},
    ]);

    await tester.tap(find.byTooltip('Add an item'));
    expect((out! as List).last, template);
    expect(identical((out! as List).last, template), isFalse, reason: 'a copy');
  });

  testWidgets('an empty list can still be added to', (tester) async {
    Object? out;
    await _pump(
      tester,
      CollectionEditor(
        label: 'Members',
        value: const [],
        template: const {'name': '', 'weight': 1.0},
        onChanged: (v) => out = v,
      ),
    );
    expect(find.text('Empty'), findsOneWidget);
    await tester.tap(find.byTooltip('Add an item'));
    expect(out, [
      {'name': '', 'weight': 1.0},
    ]);
  });

  testWidgets('a map renames a key in place, adds and removes entries', (
    tester,
  ) async {
    Object? out;
    await _pump(
      tester,
      CollectionEditor(
        label: 'States',
        value: const {'grounded': 'Ground', 'falling': 'Fall'},
        template: '',
        onChanged: (v) => out = v,
      ),
    );
    await _type(tester, find.widgetWithText(TextFormField, 'grounded'), 'idle');
    expect((out! as Map).keys, ['idle', 'falling'], reason: 'order kept');
    expect((out! as Map)['idle'], 'Ground');

    // A name already taken is refused rather than merging two entries.
    out = null;
    // (The field still reads what was just typed; the entry is 'grounded'.)
    await _type(tester, find.widgetWithText(TextFormField, 'idle'), 'falling');
    expect(out, isNull);

    await tester.tap(find.byTooltip('Add an entry'));
    expect((out! as Map).keys, ['grounded', 'falling', 'key3']);
    await tester.tap(find.byTooltip('Remove').last);
    expect((out! as Map).keys, ['grounded']);
  });

  testWidgets('read-only shows the values and nothing to press', (
    tester,
  ) async {
    await _pump(
      tester,
      CollectionEditor(
        label: 'Ids',
        value: const [1, 2],
        readOnly: true,
        onChanged: (_) => fail('read-only'),
      ),
    );
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byTooltip('Add an item'), findsNothing);
    expect(find.byTooltip('Remove'), findsNothing);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('list and map fields use it, with the definition\'s template', (
    tester,
  ) async {
    final scope = testScope();
    final field = CameraDefinitions.targetGroup.fields.single;
    final hint = CameraDefinitions.targetGroup.hints.fields[field.name]!;
    expect(hint.itemTemplate, isA<Map>());
    final component = CameraTargetGroupComponent();
    await _pump(
      tester,
      scope.fieldEditors.build(
        FieldEditorContext(
          field: field,
          hint: hint,
          value: field.read(component),
          component: component,
          editors: scope.fieldEditors,
          onChanged: (v) => field.write!(component, v),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add an item'));
    expect(component.members.single.weight, 1.0);
  });

  testWidgets('Children shows who they are, and a click selects them', (
    tester,
  ) async {
    final scope = testScope();
    final parent = scope.world.createEntityWithComponents([
      TransformComponent(),
    ], name: 'Rig');
    final kid = scope.world.createEntityWithComponents([
      TransformComponent(),
    ], name: 'WideShot');
    final children = ChildrenComponent()
      ..addChild(kid.id)
      ..addChild(9999);
    parent.addComponent(children);

    final definition = scope.definitions.definitionFor(children)!;
    final field = definition.fields.single;
    final editor = scope.extras
        .forType(definition.type)!
        .fieldEditors[field.name]!;
    await _pump(
      tester,
      editor(
        FieldEditorContext(
          field: field,
          hint: definition.hints.fields[field.name] ?? const FieldHint(),
          value: field.read(children),
          component: children,
          editors: scope.fieldEditors,
          readOnly: true,
          onChanged: (_) {},
        ),
      ),
      scope: scope,
    );
    expect(find.text('WideShot'), findsOneWidget);
    expect(find.text('missing entity #9999'), findsOneWidget);
    expect(find.text('${kid.id}'), findsNothing, reason: 'names, not ids');

    await tester.tap(find.text('WideShot'));
    expect(scope.sceneState.selectedEntity.value, same(kid));
  });
}
