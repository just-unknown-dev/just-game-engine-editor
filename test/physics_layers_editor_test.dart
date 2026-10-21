// Collision layers in the editor, made like tags: a store that makes,
// renames, recolours, describes and clears them; a delete that moves what is
// on a layer first, in every scene, with a preview; a picker that makes a
// layer from what is typed; chips for what a body collides with; the
// Physics Layers dock; and the Problems check for a pair that never meets.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/physics/layer_refactor.dart';
import 'package:just_game_engine_editor/src/core/validation/physics_checks.dart';
import 'package:just_game_engine_editor/src/ui/inspector/physics_field_editors.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/physics/physics_layers_dock.dart';

void main() {
  late Directory root;
  late jge.World world;
  late EditorScope scope;

  setUp(() {
    root = Directory.systemTemp.createTempSync('physics_layers_editor');
    world = jge.World()..initialize();
    scope = testScope(world: world, scenesRoot: root.path);
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold it for a moment; it is a temp one.
    }
  });

  jge.Entity body({int layer = 0, int? collidesWith, String name = 'Thing'}) =>
      world.createEntityWithComponents([
        jge.TransformComponent(),
        jge.RigidBody2D(layer: layer, collidesWith: collidesWith),
        jge.Collider2D(size: jge.Vector2(20, 20)),
      ], name: name);

  group('the layer store', () {
    test('makes a layer in the first free slot, and refuses near twins', () {
      final store = scope.physicsLayers;
      expect(store.create('Player'), 1);
      expect(store.create('Enemies', color: const Color(0xFFE57373)), 2);
      expect(store.value.colorOf(2), const Color(0xFFE57373));
      expect(store.problemWithNew('player'), contains('already'));
      expect(store.problemWithNew('Players'), contains('Too close'));
      expect(store.problemWithNew('  '), contains('needs a name'));
      expect(store.create('player'), isNull);
    });

    test('renames, recolours, describes and clears; the file follows', () {
      final store = scope.physicsLayers;
      final i = store.create('Coins')!;
      expect(store.rename(i, 'Pickups'), isTrue);
      expect(store.problemWithRename(i, 'Pickups'), contains('already'));
      store
        ..recolor(i, const Color(0xFFFFD54F))
        ..describe(i, 'Things the player collects');
      final saved = jge.PhysicsLayers.fromJson(
        jsonDecode(File('${root.path}/physics.json').readAsStringSync()),
      );
      expect(saved.nameOf(i), 'Pickups');
      expect(saved.colorOf(i), const Color(0xFFFFD54F));
      expect(saved.descriptionOf(i), 'Things the player collects');
      store
        ..setCollision(i, 0, false)
        ..clear(i);
      expect(store.value.isNamed(i), isFalse);
      // Made there again, it starts colliding with everything.
      expect(store.value.collides(i, 0), isTrue);
    });

    test('says when all sixteen are in use', () {
      final store = scope.physicsLayers;
      for (var i = 1; i < jge.PhysicsLayers.count; i++) {
        expect(store.create('L$i'), i);
      }
      expect(store.problemWithNew('More'), contains('All 16'));
    });
  });

  group('deleting a layer', () {
    test('moves what is on it in the open scene, as one undo step', () async {
      final store = scope.physicsLayers;
      final coins = store.create('Coins')!;
      store.create('Pickups');
      scope.sceneState.activeScene.value = EditorScene(name: 'open');
      final a = body(layer: coins, name: 'A');
      final b = body(layer: coins, name: 'B');
      body(name: 'C');

      final refactor = LayerRefactor(scope);
      final found = refactor.plan(coins);
      expect([for (final u in found.openUses) u.owner], ['A', 'B']);
      await refactor.apply(found.movingTo(2));
      expect(a.getComponent<jge.RigidBody2D>()!.layer, 2);
      expect(b.getComponent<jge.RigidBody2D>()!.layer, 2);
      expect(store.value.isNamed(coins), isFalse);
      scope.history.undo();
      expect(a.getComponent<jge.RigidBody2D>()!.layer, coins);
    });

    test('rewrites the other scenes on disk, after a backup', () async {
      final store = scope.physicsLayers;
      final ghost = store.create('Ghost')!;
      File('${root.path}/other.scene.json').writeAsStringSync(
        jsonEncode({
          'version': jge.SceneFormat.current,
          'name': 'other',
          'entities': [
            {
              'name': 'Spook',
              'components': [
                {
                  'type': 'RigidBody2D',
                  'fields': {'layer': ghost},
                },
                {
                  'type': 'Collider2D',
                  'fields': {'shape': 'circle', 'radius': 5.0},
                },
              ],
            },
          ],
        }),
      );
      final refactor = LayerRefactor(scope);
      final found = refactor.plan(ghost);
      expect(found.scenes.keys, ['other']);
      final result = await refactor.apply(found);
      expect(result.failures, isEmpty);
      final saved =
          jsonDecode(File('${root.path}/other.scene.json').readAsStringSync())
              as Map<String, dynamic>;
      final fields =
          ((saved['entities'] as List).single['components'] as List)
                  .first['fields']
              as Map;
      expect(fields['layer'], 0);
    });
  });

  group('the inspector', () {
    Future<void> pump(WidgetTester tester, jge.Entity e) async {
      await tester.binding.setSurfaceSize(const Size(420, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorScopeProvider(
              scope: scope,
              child: SingleChildScrollView(
                child: Column(
                  children: buildComponentSections(
                    entity: e,
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
    }

    testWidgets('a chip per named layer switches it, and back to the grid', (
      tester,
    ) async {
      final store = scope.physicsLayers;
      final player = store.create('Player')!;
      final coins = store.create('Coins')!;
      final e = body(layer: player);
      final b = e.getComponent<jge.RigidBody2D>()!;
      await pump(tester, e);
      expect(find.text('As the grid says for Player'), findsOneWidget);
      expect(find.textContaining('unnamed'), findsNothing);

      await tester.tap(find.text('Coins').last);
      await tester.pump();
      expect(b.collidesWith, jge.PhysicsLayers.all & ~(1 << coins));
      await pump(tester, e);
      expect(find.text('Its own list'), findsOneWidget);

      await tester.tap(find.text('Coins').last);
      await tester.pump();
      expect(b.collidesWith, isNull, reason: 'what the grid says again');
    });

    testWidgets('warns when a listed layer does not collide back', (
      tester,
    ) async {
      final store = scope.physicsLayers;
      final player = store.create('Player')!;
      final coins = store.create('Coins')!;
      store.setCollision(coins, player, false);
      // Its own list says Coins; the grid's Coins row does not say Player.
      final e = body(layer: player, collidesWith: jge.PhysicsLayers.all);
      await pump(tester, e);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('the picker makes a layer from a name typed into it', (
      tester,
    ) async {
      final e = body();
      final b = e.getComponent<jge.RigidBody2D>()!;
      await pump(tester, e);
      await tester.tap(
        find.descendant(
          of: find.byType(PhysicsLayerField),
          matching: find.text(jge.PhysicsLayers.defaultName),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Hazards');
      await tester.pumpAndSettle();
      expect(find.text('Create layer "Hazards"'), findsOneWidget);
      await tester.tap(find.text('Create layer "Hazards"'));
      await tester.pumpAndSettle();
      expect(scope.physicsLayers.value.indexOf('Hazards'), 1);
      expect(b.layer, 1);
    });
  });

  testWidgets('the dock lists layers, and makes one from New layer', (
    tester,
  ) async {
    scope.physicsLayers.create('Player');
    body(layer: 1);
    await tester.binding.setSurfaceSize(const Size(1200, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorScopeProvider(
            scope: scope,
            child: PhysicsLayersDock(scope: scope),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('2 of 16 in use'), findsOneWidget);
    expect(find.text('1 body here'), findsOneWidget);
    expect(find.text('WHAT COLLIDES'), findsOneWidget);

    await tester.tap(find.text('New layer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Enemies');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(scope.physicsLayers.value.nameOf(2), 'Enemies');
    expect(find.text('3 of 16 in use'), findsOneWidget);
  });

  test('Problems names a pair that never meets, with both fixes', () {
    final store = scope.physicsLayers;
    final player = store.create('Player')!;
    final coins = store.create('Coins')!;
    store.setCollision(coins, player, false);
    final e = body(layer: player, collidesWith: jge.PhysicsLayers.all);
    List<SceneProblem> check() => PhysicsChecks.layers(
      ValidationContext(scope: scope, projectRoot: root.path),
    );
    final problem = check().single;
    expect(problem.message, contains('never touch'));
    // Take Coins off its list: what is left is what the grid says.
    problem.fixes.last.apply();
    expect(e.getComponent<jge.RigidBody2D>()!.collidesWith, isNull);
    expect(check(), isEmpty);
  });
}
