// The inspector is built from runtime definitions. Every field the engine
// can save must therefore have a control, and a field whose type has none
// must still be visible, saying so — never a value on disk nobody can see.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

/// A field type only a module knows about.
class _ThingType extends jge.FieldType<String> {
  const _ThingType();
  @override
  String get id => 'test.thing';
  @override
  Object? encode(String value) => value;
  @override
  String? decode(Object? json, jge.FieldConstraints constraints) =>
      json as String?;
}

class _NobodyType extends _ThingType {
  const _NobodyType();
  @override
  String get id => 'test.nobody';
}

class _ThingModule extends EditorModule {
  @override
  String get id => 'test.thing';
  @override
  String get name => 'Thing';
  @override
  Map<String, FieldEditorBuilder> get fieldEditors => {
    'test.thing': (c) => Text('THING EDITOR ${c.value}'),
  };
}

jge.SchemaField _field(jge.FieldType kind) =>
    jge.SchemaField(name: 'f', kind: kind, read: (_) => 'v', write: (_, _) {});

Widget _host(EditorScope scope, jge.SchemaField field) => MaterialApp(
  home: Scaffold(
    body: scope.fieldEditors.build(
      FieldEditorContext(
        field: field,
        hint: const jge.FieldHint(label: 'F'),
        value: field.read(jge.TransformComponent()),
        component: jge.TransformComponent(),
        onChanged: (_) {},
        editors: scope.fieldEditors,
      ),
    ),
  ),
);

void main() {
  test('every built-in definition field has a registered editor', () {
    final scope = testScope();
    final missing = <String>[
      for (final d in scope.definitions.definitions)
        for (final f in d.fields)
          if (!scope.fieldEditors.canEdit(f))
            '${d.type}.${f.name}:${f.kind.id}',
    ];
    expect(missing, isEmpty);
    expect(scope.definitions.definitions.length, greaterThan(30));
  });

  test('every built-in definition carries a name and a group', () {
    final scope = testScope();
    final bare = [
      for (final d in scope.definitions.definitions)
        if (d.hints.name == null || d.hints.group == null) d.type,
    ];
    expect(bare, isEmpty);
  });

  testWidgets('an enum field renders a dropdown from its EnumFieldType', (
    tester,
  ) async {
    final scope = testScope();
    final field = jge.SchemaField(
      name: 'bodyType',
      kind: const jge.EnumFieldType(jge.BodyType.values),
      read: (_) => jge.BodyType.values.first,
      write: (_, _) {},
    );
    await tester.pumpWidget(_host(scope, field));
    expect(find.byType(DropdownEditorRow), findsOneWidget);
  });

  testWidgets("a module's field type renders the module's editor", (
    tester,
  ) async {
    final scope = testScope(modules: [_ThingModule()]);
    await tester.pumpWidget(_host(scope, _field(const _ThingType())));
    expect(find.text('THING EDITOR v'), findsOneWidget);
  });

  testWidgets('a field whose type has no editor renders a visible row', (
    tester,
  ) async {
    final scope = testScope();
    await tester.pumpWidget(_host(scope, _field(const _NobodyType())));
    expect(find.byType(ReadonlyRow), findsOneWidget);
    expect(find.textContaining('no editor for "test.nobody"'), findsOneWidget);
  });

  testWidgets('hints drive a section: labels, groups, hidden fields', (
    tester,
  ) async {
    final scope = testScope();
    final transform = jge.TransformComponent();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DefinitionSection(
              component: transform,
              definition: scope.definitions.definitionFor(transform)!,
              scope: scope,
              onDelete: () {},
              onChanged: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Transform'), findsOneWidget);
    expect(find.text('POSITION'), findsOneWidget);
    expect(find.text('Position X'), findsOneWidget);
    expect(find.text('Angle'), findsOneWidget);
    expect(find.text('Tilt X'), findsNothing, reason: 'hidden by its hint');
  });
}
