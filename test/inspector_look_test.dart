// One look for every control in the inspector: a number, a vector, a line of
// text, a dropdown and a yes-or-no all read as the same kind of thing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);

  late EditorScope scope;
  late Entity entity;

  Future<void> pumpInspector(WidgetTester tester) async {
    scope = testScope();
    entity = scope.world.createEntityWithComponents([
      TransformComponent(position: Vector3(2400, 416, 0)),
      VirtualCameraComponent(
        priority: 10,
        follow: const EntityTarget.tag('player'),
      ),
      CameraFramingComponent(),
    ], name: 'Camera');
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: buildComponentSections(
                entity: entity,
                sceneState: scope.sceneState,
                scope: scope,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Builds the sections again over the same world, for after a change.
  Future<void> pumpInspector2(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: buildComponentSections(
                entity: entity,
                sceneState: scope.sceneState,
                scope: scope,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The box a control draws itself in, whatever kind it is.
  Rect boxOf(WidgetTester tester, Finder control) =>
      tester.getRect(control.first);

  testWidgets('every control is the same box, and they all start at the same '
      'place', (tester) async {
    await pumpInspector(tester);

    // A lone number, a vector's cells, a line of text and a dropdown.
    final angle = boxOf(tester, find.byType(ScrubFieldRow));
    final position = tester
        .widgetList<ScrubbableNumberField>(find.byType(ScrubbableNumberField))
        .toList();
    expect(
      position.any((f) => f.labelInside),
      isTrue,
      reason: 'a vector puts its letter in the box',
    );

    // Every box begins where the label column ends, whether or not the
    // control has an axis letter in it.
    final boxes = <Rect>[
      for (final finder in [
        find.byType(TextField),
        find.byType(EditorDropdown<String>),
      ])
        for (final element in finder.evaluate())
          tester.getRect(find.byWidget(element.widget)),
    ];
    expect(boxes, isNotEmpty);

    // A vector has a box per axis, so what must line up is where each row's
    // controls begin — the first box on every row.
    final firstOnRow = <int, double>{};
    for (final box in boxes) {
      final row = box.top.round();
      final at = firstOnRow[row];
      if (at == null || box.left < at) firstOnRow[row] = box.left;
      expect(
        box.height,
        closeTo(InspectorField.height, 1.5),
        reason: 'every box is the same height',
      );
    }
    expect(firstOnRow.length, greaterThan(4), reason: 'several rows');
    final left = firstOnRow.values.first;
    for (final start in firstOnRow.values) {
      expect(start, closeTo(left, 1), reason: 'every row starts together');
    }
    expect(angle.left, lessThan(left), reason: 'the label column is outside');
  });

  testWidgets('a yes-or-no is a box with a word in it, not a bare tick', (
    tester,
  ) async {
    await pumpInspector(tester);
    final enabled = find.ancestor(
      of: find.text('On'),
      matching: find.byType(InkWell),
    );
    expect(enabled, findsWidgets, reason: 'Enabled reads as On');
    expect(find.byType(Checkbox), findsNothing);

    final box = tester.getRect(enabled.first);
    expect(box.height, closeTo(InspectorField.height, 1.5));
    expect(box.width, greaterThan(100), reason: 'it fills the value column');

    final camera = entity.getComponent<VirtualCameraComponent>()!;
    expect(camera.enabled, isTrue);
    await tester.tap(find.text('On').first);
    await tester.pump();
    expect(camera.enabled, isFalse);

    // The bare Column above does not listen to anything, so it is built
    // again to see what the row says now.
    await pumpInspector2(tester);
    expect(find.text('Off'), findsWidgets);
  });

  testWidgets('a number is scrubbed by its letter, inside the box', (
    tester,
  ) async {
    await pumpInspector(tester);
    final transform = entity.getComponent<TransformComponent>()!;
    expect(transform.position.x, 2400);

    // The X inside the first cell is the drag handle.
    final x = find.descendant(
      of: find.byType(AxesFieldRow).first,
      matching: find.text('X'),
    );
    expect(x, findsOneWidget);
    await tester.drag(x, const Offset(24, 0));
    await tester.pump();
    expect(
      transform.position.x,
      greaterThan(2400),
      reason: 'dragging the letter still scrubs',
    );
    expect(transform.position.y, 416, reason: 'and only that axis');
  });
}
