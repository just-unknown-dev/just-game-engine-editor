// Rearranging an entity's components in the inspector: a card dragged by
// the grip on its header, or moved from its ⋮ menu. Transform stays first;
// a move is one undo step; the order is the entity's, so the scene saves it
// and a removed component comes back in its place.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/inspector/component_reorder.dart';

import 'support/test_scope.dart';

List<Type> typesOf(jge.Entity e) => [
  for (final c in e.components) c.componentType,
];

void main() {
  group('placeComponent', () {
    const order = [jge.TransformComponent, int, double, String];

    test('puts a type before or after another', () {
      expect(placeComponent(order, String, before: int), [
        jge.TransformComponent,
        String,
        int,
        double,
      ]);
      expect(placeComponent(order, int, after: String), [
        jge.TransformComponent,
        double,
        String,
        int,
      ]);
    });

    test('keeps Transform first, whatever is asked', () {
      expect(placeComponent(order, String, before: jge.TransformComponent), [
        jge.TransformComponent,
        String,
        int,
        double,
      ]);
    });
  });

  group('the inspector', () {
    late jge.World world;
    late EditorScope scope;
    late jge.Entity entity;

    setUp(() {
      world = jge.World()..initialize();
      scope = testScope(world: world);
      entity = world.createEntityWithComponents([
        jge.TransformComponent(),
        jge.VelocityComponent(),
        jge.HealthComponent(maxHealth: 3),
        jge.LifetimeComponent(5),
      ], name: 'Thing');
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Rebuilt as the scene changes, as the inspector is.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorScopeProvider(
              scope: scope,
              child: ValueListenableBuilder(
                valueListenable: scope.sceneState.revision,
                builder: (context, _, _) => SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in buildComponentSections(
                        entity: entity,
                        sceneState: scope.sceneState,
                        scope: scope,
                      )) ...[s, const SizedBox(height: 6)],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Finder menuOf(Type type) => find.byWidgetPredicate(
      (w) => w is ComponentPlaceMenu && w.placement.type == type,
    );
    Finder gripOf(Type type) => find.byWidgetPredicate(
      (w) => w is ComponentDragGrip && w.placement.type == type,
    );

    Future<void> choose(WidgetTester tester, Type type, String item) async {
      await tester.tap(menuOf(type));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('Transform has no grip and no menu: it stays first', (
      tester,
    ) async {
      await pump(tester);
      expect(gripOf(jge.TransformComponent), findsNothing);
      expect(menuOf(jge.TransformComponent), findsNothing);
      expect(gripOf(jge.HealthComponent), findsOneWidget);
      expect(menuOf(jge.HealthComponent), findsOneWidget);
    });

    testWidgets('Move up, from the menu, is one undo step', (tester) async {
      await pump(tester);

      await choose(tester, jge.HealthComponent, 'Move up');

      expect(typesOf(entity), [
        jge.TransformComponent,
        jge.HealthComponent,
        jge.VelocityComponent,
        jge.LifetimeComponent,
      ]);
      expect(scope.sceneState.isDirty.value, isTrue);

      scope.history.undo();
      expect(typesOf(entity), [
        jge.TransformComponent,
        jge.VelocityComponent,
        jge.HealthComponent,
        jge.LifetimeComponent,
      ]);
    });

    testWidgets('Move to top goes under Transform; to bottom, last', (
      tester,
    ) async {
      await pump(tester);

      await choose(tester, jge.LifetimeComponent, 'Move to top');
      expect(typesOf(entity), [
        jge.TransformComponent,
        jge.LifetimeComponent,
        jge.VelocityComponent,
        jge.HealthComponent,
      ]);

      await choose(tester, jge.LifetimeComponent, 'Move to bottom');
      expect(typesOf(entity).last, jge.LifetimeComponent);
    });

    testWidgets('the first card cannot move up', (tester) async {
      await pump(tester);
      final before = typesOf(entity);

      await choose(tester, jge.VelocityComponent, 'Move up');

      expect(typesOf(entity), before);
    });

    testWidgets('a card dragged onto the top half of another goes above it', (
      tester,
    ) async {
      await pump(tester);
      final target = tester.getRect(
        find.byKey(const ValueKey(jge.VelocityComponent)),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(gripOf(jge.LifetimeComponent)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveTo(target.topCenter + const Offset(0, 6));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(typesOf(entity), [
        jge.TransformComponent,
        jge.LifetimeComponent,
        jge.VelocityComponent,
        jge.HealthComponent,
      ]);
    });

    testWidgets('a card dropped on Transform goes just below it', (
      tester,
    ) async {
      await pump(tester);
      final transform = tester.getRect(
        find.byKey(const ValueKey(jge.TransformComponent)),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(gripOf(jge.HealthComponent)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveTo(transform.topCenter + const Offset(0, 4));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(typesOf(entity).take(2), [
        jge.TransformComponent,
        jge.HealthComponent,
      ]);
    });
  });

  group('the order is kept', () {
    late jge.World world;
    late EditorScope scope;
    late jge.Entity entity;

    setUp(() {
      world = jge.World()..initialize();
      scope = testScope(world: world);
      entity = world.createEntityWithComponents([
        jge.TransformComponent(),
        jge.VelocityComponent(),
        jge.HealthComponent(maxHealth: 3),
      ], name: 'Thing');
    });

    test('in what the scene saves, and what loads from it', () {
      entity.reorderComponents([
        jge.TransformComponent,
        jge.HealthComponent,
        jge.VelocityComponent,
      ]);
      final saved = scope.codec.encodeAll(entity.components);
      expect(
        [for (final c in saved) c['type']],
        ['TransformComponent', 'HealthComponent', 'VelocityComponent'],
      );

      final loaded = jge.World()..initialize();
      addTearDown(loaded.dispose);
      final again = loaded.createEntityWithComponents(
        scope.codec.decodeAll(saved),
      );
      expect(typesOf(again), typesOf(entity));
    });

    test('a removed component comes back in its place on undo', () {
      final health = entity.getComponent<jge.HealthComponent>()!;
      scope.history.push(
        RemoveComponentCommand(
          entity: entity,
          component: health,
          sceneState: scope.sceneState,
        ),
      );
      expect(typesOf(entity), [jge.TransformComponent, jge.VelocityComponent]);

      scope.history.undo();

      expect(typesOf(entity), [
        jge.TransformComponent,
        jge.VelocityComponent,
        jge.HealthComponent,
      ]);
    });

    test('putting an entity back from a record puts its order back', () {
      final spec = EntitySpec.of(entity, scope.codec, world: world);
      entity.reorderComponents([jge.HealthComponent]);

      spec.applyTo(entity);

      expect(typesOf(entity), [
        jge.TransformComponent,
        jge.VelocityComponent,
        jge.HealthComponent,
      ]);
    });
  });
}
