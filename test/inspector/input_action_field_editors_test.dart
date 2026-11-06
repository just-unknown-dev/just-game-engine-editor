// An input action field in the inspector: a picker over the actions the
// project's input assets have — a name they lack kept and marked — and a
// plain text box in a project with none.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/inspector/built_in_field_editors.dart';
import 'package:just_game_engine_editor/src/inspector/input_action_field_editors.dart';

import '../support/real_io.dart' show ioTimeout;

/// An input asset of [maps]: map name → its actions' names and types.
String _asset(Map<String, Map<String, String>> maps) {
  var id = 0;
  return jsonEncode({
    'format': 'just_inputs',
    'version': 3,
    'name': 'game',
    'maps': [
      for (final m in maps.entries)
        {
          'id': 'm${++id}',
          'name': m.key,
          'actions': [
            for (final a in m.value.entries)
              {'id': 'a${++id}', 'name': a.key, 'type': a.value},
          ],
        },
    ],
  });
}

final _game = _asset({
  'player': {'move': 'vector2', 'jump': 'button'},
  'ui': {'pause': 'button', 'jump': 'button'},
});

/// The project's asset index, not watching the folder: a rescan the watcher
/// asked for would come on the fake clock at a moment of its own. Each test
/// scans when it has changed something (watching is just_editor_core's to
/// test).
class _Index extends AssetIndex {
  _Index({super.projectRoot});

  @override
  void startWatching() {}
}

/// A project folder with [files] (path → text), and a scope editing it
/// whose asset index is [_Index], scanned; the folder is removed once the
/// scope is gone.
Future<EditorScope> _project(
  WidgetTester tester,
  Map<String, String> files,
) async {
  final root = Directory.systemTemp.createTempSync('input_fields');
  addTearDown(() {
    // Registered first, so it runs after the scope and its index are gone.
    final clock = Stopwatch()..start();
    while (root.existsSync()) {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        if (clock.elapsed > ioTimeout) rethrow;
        sleep(const Duration(milliseconds: 50));
      }
    }
  });
  for (final MapEntry(key: path, value: text) in files.entries) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }
  final scope = EditorScope(
    builtIns: const [BuiltInEditorModule.new],
    world: World(extensions: [BuiltInComponents.extension])..initialize(),
    projectRoot: root.path,
  );
  addTearDown(scope.dispose);
  final index = scope.service<AssetIndex>(
    () => _Index(projectRoot: root.path),
    dispose: (index) => index.dispose(),
  );
  await tester.runAsync(index.scan);
  return scope;
}

/// The field [name] of [definition], edited on [component] in [scope]'s
/// inspector; what it is set to goes to [changed].
Widget _row(
  EditorScope scope,
  ComponentDefinition definition,
  String name,
  Component component,
  List<Object?> changed,
) {
  final field = definition.fields.singleWhere((f) => f.name == name);
  return EditorScopeProvider(
    scope: scope,
    child: scope.fieldEditors.build(
      FieldEditorContext(
        field: field,
        hint: definition.hints.fields[name] ?? const FieldHint(),
        value: field.read(component),
        component: component,
        editors: scope.fieldEditors,
        scope: scope,
        onChanged: changed.add,
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, child: child)),
    ),
  ),
);

/// A component with a list of actions, for the list's editor.
class _Combo extends Component {
  List<String> steps = ['jump', 'dash'];
}

final _comboDefinition = ComponentDefinition<_Combo>(
  type: 'ComboComponent',
  create: _Combo.new,
  fields: [
    FieldDefinition(
      name: 'steps',
      kind: InputDefinitions.actionListType,
      read: (c) => (c as _Combo).steps,
      write: (c, v) => (c as _Combo).steps = [...(v! as List).cast<String>()],
    ),
  ],
);

void main() {
  test('both input action kinds have an editor', () {
    for (final kind in InputDefinitions.fieldTypes) {
      expect(BuiltInFieldEditors.all, contains(kind.id));
    }
  });

  group('ProjectInputActions', () {
    testWidgets('every action of every input asset, by name, maps beside it', (
      tester,
    ) async {
      final scope = await _project(tester, {
        'assets/input/game.input.json': _game,
        'assets/input/broken.input.json': '{"format": "just_inputs"',
        'assets/scenes/level.scene.json': '{}',
      });
      final actions = scope.inputActions;
      expect(actions.files, [
        'assets/input/broken.input.json',
        'assets/input/game.input.json',
      ], reason: 'one that does not read is listed, and offers nothing');
      expect(
        [for (final a in actions.actions) a.name],
        ['move', 'jump', 'pause'],
      );
      final jump = actions.actions.singleWhere((a) => a.name == 'jump');
      expect(jump.paths, ['player/jump', 'ui/jump']);
      expect(jump.detail, 'player, ui · button');
      expect(actions.knows('move'), isTrue);
      expect(actions.knows('ui/pause'), isTrue);
      expect(actions.knows('hop'), isFalse);
      expect(actions.knows('player/pause'), isFalse);
    });

    testWidgets('a file changed on disk is read again', (tester) async {
      final scope = await _project(tester, {
        'assets/input/game.input.json': _game,
      });
      expect(scope.inputActions.knows('dash'), isFalse);
      await tester.runAsync(() async {
        await File(
          scope.assetIndex.absolute('assets/input/game.input.json'),
        ).writeAsString(
          _asset({
            'player': {'move': 'vector2', 'dash': 'button'},
          }),
        );
        await scope.assetIndex.scan();
      });
      expect(scope.inputActions.knows('dash'), isTrue);
      expect(scope.inputActions.knows('jump'), isFalse);
    });
  });

  group('one action', () {
    final definition = InputDefinitions.simpleMovement;

    testWidgets('picked from the project\'s actions', (tester) async {
      final scope = await _project(tester, {
        'assets/input/game.input.json': _game,
      });
      final changed = <Object?>[];
      await _pump(
        tester,
        _row(scope, definition, 'action', SimpleMovementComponent(), changed),
      );
      expect(find.byType(InputActionFieldRow), findsOneWidget);
      expect(find.byType(EditorDropdown<String>), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'no box to type in');
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

      await tester.tap(find.byType(EditorDropdown<String>));
      await tester.pumpAndSettle();
      expect(find.text('player · vector2'), findsOneWidget);
      expect(find.text('player, ui · button'), findsOneWidget);
      await tester.tap(find.text('jump').last);
      await tester.pumpAndSettle();
      expect(changed, ['jump']);
    });

    testWidgets('a name no asset has is kept, listed and marked', (
      tester,
    ) async {
      final scope = await _project(tester, {
        'assets/input/game.input.json': _game,
      });
      final changed = <Object?>[];
      await _pump(
        tester,
        _row(
          scope,
          definition,
          'action',
          SimpleMovementComponent(action: 'walk'),
          changed,
        ),
      );
      expect(find.text('walk'), findsOneWidget, reason: 'shown, not lost');
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      await tester.tap(find.byType(EditorDropdown<String>));
      await tester.pumpAndSettle();
      expect(find.text(InputActionFieldEditors.unknownDetail), findsOneWidget);
      // Choosing it again changes nothing.
      await tester.tap(find.text('walk').last);
      await tester.pumpAndSettle();
      expect(changed, isEmpty);
    });

    testWidgets('a project with no input asset types the name', (tester) async {
      final scope = await _project(tester, {
        'assets/scenes/level.scene.json': '{}',
      });
      final changed = <Object?>[];
      await _pump(
        tester,
        _row(scope, definition, 'action', SimpleMovementComponent(), changed),
      );
      expect(find.byType(EditorDropdown<String>), findsNothing);
      await tester.enterText(find.byType(TextField), ' hop ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(changed, ['hop']);
    });
  });

  group('a list of actions', () {
    testWidgets('chips, a name no asset has marked; one taken off, one added', (
      tester,
    ) async {
      final scope = await _project(tester, {
        'assets/input/game.input.json': _game,
      });
      final changed = <Object?>[];
      await _pump(
        tester,
        _row(scope, _comboDefinition, 'steps', _Combo(), changed),
      );
      final chips = tester
          .widgetList<InputActionChip>(find.byType(InputActionChip))
          .toList();
      expect(
        [for (final c in chips) (c.name, c.isKnown)],
        [('jump', true), ('dash', false)],
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputActionChip, 'dash'),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      expect(changed.removeLast(), ['jump']);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(
        find.text('player, ui · button'),
        findsNothing,
        reason: 'what the list has already is not offered',
      );
      await tester.tap(find.text('pause'));
      await tester.pumpAndSettle();
      expect(changed.removeLast(), ['jump', 'dash', 'pause']);
    });
  });
}
