// Rows in the inspector line up: the same label column, the same box, the
// picker where it always is — and a row pointing at other entities names
// them from the world being edited.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view
    ..physicalSize = const Size(360, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(8), child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a colour row keeps its picker at the end, whatever the value', (
    tester,
  ) async {
    await _pump(
      tester,
      Column(
        children: [
          ColorEditorRow(
            label: 'a',
            paintStyle: const jge.ShapePaintStyle(color: Color(0xFFFFFFFF)),
            onChanged: (_) {},
          ),
          ColorEditorRow(
            label: 'b',
            paintStyle: const jge.ShapePaintStyle(color: Color(0x33101820)),
            onChanged: (_) {},
          ),
        ],
      ),
    );

    final pickers = find.byIcon(Icons.colorize_rounded);
    expect(pickers, findsNWidgets(2));
    expect(
      tester.getTopLeft(pickers.first).dx,
      tester.getTopLeft(pickers.last).dx,
    );
  });

  testWidgets('a read-only row is a box like the rest, on the same column', (
    tester,
  ) async {
    await _pump(
      tester,
      Column(
        children: [
          const ReadonlyRow(label: 'Image', value: 'assets/a.png'),
          DropdownEditorRow(
            label: 'Mode',
            value: 'one',
            options: const ['one', 'two'],
            onChanged: (_) {},
          ),
        ],
      ),
    );

    final box = find.ancestor(
      of: find.text('assets/a.png'),
      matching: find.byType(Container),
    );
    expect(tester.getSize(box.first).height, InspectorField.height);
    expect(
      tester.getTopLeft(find.text('assets/a.png')).dx,
      closeTo(tester.getTopLeft(find.text('one')).dx, 1),
    );
  });

  testWidgets('links to other entities name them from the world edited', (
    tester,
  ) async {
    final scope = testScope();
    // The level holds something else under the same ids.
    scope.world.createEntityWithComponents([], name: 'LevelThing');
    final screen = jge.World()..initialize();
    addTearDown(screen.dispose);
    final child = screen.createEntityWithComponents([], name: 'Button');
    final parent = screen.createEntityWithComponents([
      jge.ChildrenComponent()..addChild(child.id),
    ], name: 'Panel');

    await _pump(
      tester,
      EditorScopeProvider(
        scope: scope,
        child: Column(
          children: buildComponentSections(
            entity: parent,
            sceneState: scope.sceneState,
            scope: scope,
            history: EditorHistory(),
            world: screen,
          ),
        ),
      ),
    );

    expect(find.text('Button'), findsOneWidget);
    expect(find.text('LevelThing'), findsNothing);
  });

  testWidgets('a menu line with no icon can keep its room', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showEditorMenu<int>(context, Offset.zero, [
            editorMenuItem(1, 'Ticked', icon: Icons.check),
            editorMenuItem(2, 'Not ticked', iconSlot: true),
          ]),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Ticked')).dx,
      tester.getTopLeft(find.text('Not ticked')).dx,
    );
  });
}
