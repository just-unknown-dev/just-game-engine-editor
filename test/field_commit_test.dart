// A typed value is kept when the field is left — Enter, Tab, or a click
// anywhere else — not only on Enter.
//
// Every number field in the inspector used to keep what was typed on Enter
// alone: a click elsewhere left the new number on screen and the component
// as it was (seen first on a Physics Body's collider). Now every typed field
// follows the editor's one rule. Esc puts back what was there; text that is
// not a number does too, rather than writing 0.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_item_bar.dart'
    show TimelineField;

import 'support/test_scope.dart';

/// Desktop, where a click outside a text field takes its focus away.
final _desktop = TargetPlatformVariant.only(TargetPlatform.windows);

const _cfg = NumberScrubConfig(fractionDigits: 1);

Future<void> _pump(WidgetTester tester, Widget field) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(width: 360, child: field),
            // Somewhere else to go: Tab moves here.
            const SizedBox(width: 200, child: TextField(key: Key('other'))),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      ),
    ),
  );
}

/// A press on empty ground, as a mouse makes it.
Future<void> _clickAway(WidgetTester tester) async {
  await tester.tapAt(const Offset(500, 500), kind: PointerDeviceKind.mouse);
  await tester.pump();
}

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.tap(field, kind: PointerDeviceKind.mouse);
  await tester.pump();
  await tester.enterText(field, text);
  await tester.pump();
}

void main() {
  group('a number field', () {
    late List<double> kept;
    Finder field() => find.descendant(
      of: find.byType(ScrubbableNumberField),
      matching: find.byType(TextField),
    );
    String shown(WidgetTester tester) =>
        tester.widget<TextField>(field()).controller!.text;

    Future<void> pumpRow(WidgetTester tester) => _pump(
      tester,
      ScrubFieldRow(
        label: 'Mass',
        value: 1,
        scrubConfig: _cfg,
        onChanged: kept.add,
      ),
    );

    setUp(() => kept = []);

    testWidgets('keeps what was typed when clicked away from', (tester) async {
      await pumpRow(tester);
      await _type(tester, field(), '12.5');
      expect(kept, isEmpty, reason: 'nothing kept while typing');

      await _clickAway(tester);

      expect(kept, [12.5]);
    }, variant: _desktop);

    testWidgets('keeps what was typed on Tab', (tester) async {
      await pumpRow(tester);
      await _type(tester, field(), '3');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(kept, [3]);
    }, variant: _desktop);

    testWidgets('keeps it once on Enter, and not again on leaving', (
      tester,
    ) async {
      await pumpRow(tester);
      await _type(tester, field(), '7');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(kept, [7]);

      await _clickAway(tester);
      expect(kept, [7]);
    }, variant: _desktop);

    testWidgets('Esc puts back what was there and keeps nothing', (
      tester,
    ) async {
      await pumpRow(tester);
      await _type(tester, field(), '99');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await _clickAway(tester);

      expect(kept, isEmpty);
      expect(shown(tester), '1.0');
    }, variant: _desktop);

    testWidgets('text that is not a number puts back what was there', (
      tester,
    ) async {
      await pumpRow(tester);
      await _type(tester, field(), 'abc');

      await _clickAway(tester);

      expect(kept, isEmpty, reason: 'not written as 0');
      expect(shown(tester), '1.0');
    }, variant: _desktop);

    testWidgets('leaving without a change keeps nothing', (tester) async {
      await pumpRow(tester);
      await tester.tap(field(), kind: PointerDeviceKind.mouse);
      await tester.pump();

      await _clickAway(tester);

      expect(kept, isEmpty);
    }, variant: _desktop);

    testWidgets('Save while typing keeps what was typed first', (tester) async {
      await pumpRow(tester);
      await _type(tester, field(), '4');

      PendingFieldEdits.flush(); // what Ctrl+S does before it saves

      expect(kept, [4]);
      await _clickAway(tester);
      expect(kept, [4], reason: 'kept once');
    }, variant: _desktop);
  });

  testWidgets('one axis of a vector row is kept on clicking away', (
    tester,
  ) async {
    final kept = <List<double>>[];
    await _pump(
      tester,
      AxesFieldRow(
        label: 'Offset',
        axes: const ['X', 'Y'],
        values: const [1, 2],
        scrubConfig: _cfg,
        onChanged: kept.add,
      ),
    );
    final y = find
        .descendant(
          of: find.byType(ScrubbableNumberField),
          matching: find.byType(TextField),
        )
        .at(1);
    await _type(tester, y, '8');

    await _clickAway(tester);

    expect(kept, [
      [1, 8],
    ]);
  }, variant: _desktop);

  testWidgets('a compact number field is kept on clicking away', (
    tester,
  ) async {
    final kept = <double>[];
    await _pump(tester, MiniNumberField(value: 2, onSubmitted: kept.add));
    final box = find.descendant(
      of: find.byType(MiniNumberField),
      matching: find.byType(TextField),
    );
    await _type(tester, box, '6');

    await _clickAway(tester);

    expect(kept, [6]);
  }, variant: _desktop);

  group('a text field', () {
    testWidgets('Esc with nothing typed is left to whoever wants it', (
      tester,
    ) async {
      var dismissed = 0;
      final kept = <String>[];
      await _pump(
        tester,
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () => dismissed++,
          },
          child: CommitTextField(value: 'Thing', onCommit: kept.add),
        ),
      );
      final box = find.descendant(
        of: find.byType(CommitTextField),
        matching: find.byType(TextField),
      );
      await tester.tap(box, kind: PointerDeviceKind.mouse);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(dismissed, 1, reason: 'a dialog still closes on Esc');

      await tester.enterText(box, 'Other');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(dismissed, 1, reason: 'this Esc put the text back');
      expect(tester.widget<TextField>(box).controller!.text, 'Thing');
      expect(kept, isEmpty);
    }, variant: _desktop);

    testWidgets('text it does not accept puts back what was there', (
      tester,
    ) async {
      final kept = <String>[];
      await _pump(
        tester,
        CommitTextField(
          value: 'red',
          accept: (t) => t.isNotEmpty,
          onCommit: kept.add,
        ),
      );
      final box = find.descendant(
        of: find.byType(CommitTextField),
        matching: find.byType(TextField),
      );
      await _type(tester, box, '');

      await _clickAway(tester);

      expect(kept, isEmpty);
      expect(tester.widget<TextField>(box).controller!.text, 'red');
    }, variant: _desktop);
  });

  testWidgets("a Physics Body's collider takes a typed size on clicking away", (
    tester,
  ) async {
    final world = jge.World()..initialize();
    final scope = testScope(world: world);
    final entity = world.createEntityWithComponents([
      jge.TransformComponent(position: jge.Vector3(100, 100, 0)),
      jge.PhysicsBodyComponent(shape: jge.CircleShape(10)),
    ], name: 'Ball');
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorScopeProvider(
            scope: scope,
            child: SingleChildScrollView(
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
      ),
    );
    await tester.pump();
    final radius = find.descendant(
      of: find.widgetWithText(ScrubFieldRow, 'Radius'),
      matching: find.byType(TextField),
    );
    expect(radius, findsOneWidget);

    await tester.tap(radius, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.enterText(radius, '25');
    await tester.pump();
    await tester.tapAt(const Offset(400, 1590), kind: PointerDeviceKind.mouse);
    await tester.pump();

    final shape = entity.getComponent<jge.PhysicsBodyComponent>()!.shape;
    expect((shape as jge.CircleShape).radius, 25);
  }, variant: _desktop);

  group("the Timeline's fields", () {
    late List<String> kept;
    Future<Finder> pumpField(WidgetTester tester) async {
      kept = [];
      await _pump(
        tester,
        TimelineField(
          label: 'Name',
          tooltip: '',
          text: 'hit',
          width: 120,
          onSubmitted: kept.add,
        ),
      );
      final box = find.descendant(
        of: find.byType(TimelineField),
        matching: find.byType(TextField),
      );
      await _type(tester, box, 'land');
      return box;
    }

    testWidgets('keep what was typed on clicking away', (tester) async {
      await pumpField(tester);

      await _clickAway(tester);

      expect(kept, ['land']);
    }, variant: _desktop);

    testWidgets('Esc puts back what was there', (tester) async {
      final box = await pumpField(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(kept, isEmpty);
      expect(tester.widget<TextField>(box).controller!.text, 'hit');
    }, variant: _desktop);

    testWidgets('Save while typing keeps what was typed first', (tester) async {
      await pumpField(tester);

      PendingFieldEdits.flush();

      expect(kept, ['land']);
    }, variant: _desktop);
  });
}
