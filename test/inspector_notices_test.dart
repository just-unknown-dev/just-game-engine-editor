// The inspector starts with the components: no header of its own. Switching
// an entity off and pinning the inspector to it are the scene tree's, and a
// notice says when either is in force. Its component cards fold away.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);

  late EditorScope scope;
  late Entity hero;

  setUp(() {
    scope = testScope();
    hero = scope.world.createEntityWithComponents([
      TransformComponent(),
    ], name: 'Hero');
    scope.sceneState.selectEntity(hero);
  });

  Future<void> pumpInspector(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntityInspectorPanel(
            sceneState: scope.sceneState,
            world: scope.world,
            scope: scope,
            onDetachFromParent: (_) {},
            onGroupSelection: () {},
          ),
        ),
      ),
    );
  }

  Finder tooltipStarting(String start) => find.byWidgetPredicate(
    (w) => w is Tooltip && (w.message ?? '').startsWith(start),
  );

  testWidgets('no header: the components come first', (tester) async {
    await pumpInspector(tester);
    expect(
      find.textContaining('#${hero.id}', findRichText: true),
      findsNothing,
    );
    expect(find.byType(EditorToggle), findsNothing, reason: 'no switch');
    expect(tooltipStarting('Pin:'), findsNothing, reason: 'no pin');
  });

  testWidgets('switched off, it says so, and where to switch it on', (
    tester,
  ) async {
    scope.history.push(
      SetEnabledCommand(
        sceneState: scope.sceneState,
        entity: hero,
        enabled: false,
      ),
    );
    await pumpInspector(tester);
    expect(find.textContaining('Switched off'), findsOneWidget);
    expect(find.textContaining('tick above'), findsOneWidget);
    // And the tick above is there, working, while the rest waits.
    await tester.tap(find.byIcon(Icons.check_box_outline_blank_rounded));
    expect(hero.isActive, isTrue);
  });

  testWidgets('pinned, it says so, with the way to unpin', (tester) async {
    scope.view.togglePinned(hero.id);
    await pumpInspector(tester);
    expect(find.textContaining('Pinned to Hero'), findsOneWidget);
    await tester.tap(find.text('Unpin'));
    await tester.pump();
    expect(scope.view.isPinned(hero.id), isFalse);
  });

  testWidgets('a component card folds, on every entity, and opens again', (
    tester,
  ) async {
    await pumpInspector(tester);
    final fold = tooltipStarting('Fold ');
    expect(fold, findsWidgets);
    await tester.tap(fold.first);
    await tester.pump();
    expect(scope.chrome.collapsedComponents.value, isNotEmpty);
    expect(tooltipStarting('Show '), findsOneWidget);

    await tester.tap(tooltipStarting('Show '));
    await tester.pump();
    expect(scope.chrome.collapsedComponents.value, isEmpty);
  });
}
