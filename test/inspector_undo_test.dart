// An inspector edit undoes exactly: whatever the field reads (a live
// vector), after a play-test put fresh components in place, and one step
// per change — not every change of a field folded into one.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/state/play_snapshot.dart';

import 'support/test_scope.dart';

void main() {
  late EditorScope scope;
  late jge.Entity entity;

  setUp(() {
    scope = testScope();
    scope.sceneState.openScene(EditorScene(name: 'level_test'));
    entity = scope.world.createEntityWithComponents([
      jge.TransformComponent(),
      jge.HealthComponent(maxHealth: 3),
    ], name: 'Crate');
    scope.sceneState.registerEntity(entity);
  });

  Future<void> pumpInspector(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(480, 1600)
      ..devicePixelRatio = 1;
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

  AxesFieldRow axes(WidgetTester tester, String label) => tester
      .widgetList<AxesFieldRow>(find.byType(AxesFieldRow))
      .firstWhere((w) => w.label == label);

  /// Health's Max cell, on the row it shares with HP, set to [value].
  void setMax(WidgetTester tester, double value) {
    final row = axes(tester, 'Health');
    row.onChanged([row.values[0], value]);
  }

  jge.Vector3 scale() => entity.getComponent<jge.TransformComponent>()!.scale;

  testWidgets('a scale edit undoes, though the field reads the live vector', (
    tester,
  ) async {
    await pumpInspector(tester);
    final row = axes(tester, 'Scale');
    row.onChanged([2, ...row.values.skip(1)]);
    expect(scale().x, 2);

    scope.history.undo();
    expect(scale().x, 1, reason: 'back to what it was');
    scope.history.redo();
    expect(scale().x, 2);
  });

  testWidgets('an edit made before a play-test undoes after Stop', (
    tester,
  ) async {
    await pumpInspector(tester);
    setMax(tester, 9);
    expect(entity.getComponent<jge.HealthComponent>()!.maxHealth, 9);

    // Play, then Stop: every component is put back as a fresh instance.
    final before = entity.getComponent<jge.HealthComponent>();
    final snapshot = PlaySnapshot.capture(scope.world, scope.codec);
    snapshot.restoreInto(
      scope.world,
      onRecreated: scope.sceneState.entityRebuilt,
    );
    expect(entity.getComponent<jge.HealthComponent>(), isNot(same(before)));

    scope.history.undo();
    expect(
      entity.getComponent<jge.HealthComponent>()!.maxHealth,
      3,
      reason: 'the undo reaches the component there now',
    );
  });

  testWidgets('two separate changes of one field are two undo steps', (
    tester,
  ) async {
    await pumpInspector(tester);
    final field = find.byWidgetPredicate(
      (w) => w is AxesFieldRow && w.label == 'Health',
    );
    Future<void> pressAndChange(double value) async {
      // A press in the card starts a new edit, as a click on a field does.
      await tester.tap(field, kind: PointerDeviceKind.mouse);
      await tester.pump();
      setMax(tester, value);
      await tester.pump();
    }

    await pressAndChange(5);
    await pressAndChange(7);
    expect(entity.getComponent<jge.HealthComponent>()!.maxHealth, 7);

    scope.history.undo();
    expect(entity.getComponent<jge.HealthComponent>()!.maxHealth, 5);
    scope.history.undo();
    expect(entity.getComponent<jge.HealthComponent>()!.maxHealth, 3);
  });

  testWidgets('one drag of a field is one undo step', (tester) async {
    await pumpInspector(tester);
    for (final v in [4.0, 5.0, 6.0]) {
      setMax(tester, v); // a scrub writes on every step of the drag
    }
    scope.history.undo();
    expect(entity.getComponent<jge.HealthComponent>()!.maxHealth, 3);
  });
  test('a move made before a play-test undoes on the entity Stop made '
      'again, which keeps its place', () {
    final other = scope.world.createEntityWithComponents([
      jge.TransformComponent(),
    ], name: 'Other');
    scope.sceneState.registerEntity(other);
    final t = entity.getComponent<jge.TransformComponent>()!;
    final before = TransformSnapshot.of(entity);
    t.setPositionXY(40, 20);
    scope.history.pushApplied(
      TransformCommand(
        label: 'Move',
        entities: [entity],
        before: [before],
        after: [TransformSnapshot.of(entity)],
        sceneState: scope.sceneState,
      ),
    );
    final order = [
      for (final id in scope.sceneState.rootOrder(scope.world))
        scope.world.getEntity(id)!.name,
    ];

    // Play destroys the crate (collected, say); Stop makes it again.
    final snapshot = PlaySnapshot.capture(scope.world, scope.codec);
    scope.world.destroyEntity(entity);
    snapshot.restoreInto(
      scope.world,
      onRecreated: scope.sceneState.entityRebuilt,
    );
    final crate = scope.world.entities.firstWhere((e) => e.name == 'Crate');
    expect(crate.id, isNot(entity.id));
    expect(
      [
        for (final id in scope.sceneState.rootOrder(scope.world))
          scope.world.getEntity(id)!.name,
      ],
      order,
      reason: 'back in its place among the roots',
    );

    scope.history.undo();
    final p = crate.getComponent<jge.TransformComponent>()!.position;
    expect((p.x, p.y), (0.0, 0.0), reason: 'the undo reaches it');
  });
}
