// The World dock: entities, systems and component types as tables that act
// on the scene.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/world/world_dock.dart';

import 'support/test_scope.dart';

void main() {
  late EditorScope scope;
  late Entity hero;
  late Entity coin;

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1400, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    scope = testScope();
    hero = scope.world.createEntityWithComponents([
      TransformComponent(),
      HealthComponent(maxHealth: 3),
      TagComponent('player'),
    ], name: 'Hero');
    coin = scope.world.createEntityWithComponents([
      TransformComponent(),
    ], name: 'Coin');
    scope.world.addSystem(HealthSystem());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldDock(
            scope: scope,
            dock: DockContext(
              scope: scope,
              height: 300,
              onResize: (_) {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
  }

  Future<void> done(WidgetTester tester) async {
    // The dock refreshes on a timer; take it down before the test ends.
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('entities: filter by name, tag or component; a click selects', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Hero'), findsOneWidget);
    expect(find.text('Coin'), findsOneWidget);
    expect(find.text('player'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'health');
    await tester.pump();
    expect(find.text('Coin'), findsNothing, reason: 'it has no Health');
    await tester.tap(find.text('Hero'));
    expect(scope.sceneState.selectedEntity.value, same(hero));
    await done(tester);
  });

  testWidgets('systems: a click on the dot switches one off, and on again; '
      'a click on the name does not', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Systems'));
    await tester.pump();
    final system = scope.world.systems.whereType<HealthSystem>().single;
    await tester.tap(find.text('HealthSystem'));
    await tester.pump();
    expect(system.isActive, isTrue, reason: 'the row is not a switch');

    // The dot, in the On column just left of the name.
    Offset dot() {
      final name = tester.getRect(find.text('HealthSystem'));
      return Offset(name.left - 20, name.center.dy);
    }

    await tester.tapAt(dot());
    await tester.pump();
    expect(system.isActive, isFalse);
    await tester.tapAt(dot());
    await tester.pump();
    expect(system.isActive, isTrue);
    await done(tester);
  });

  testWidgets('components: a click selects everything that carries one', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Components'));
    await tester.pump();
    await tester.tap(find.text('TransformComponent'));
    expect(
      scope.sceneState.multiSelectedIds.value,
      containsAll([hero.id, coin.id]),
    );
    await done(tester);
  });
}
