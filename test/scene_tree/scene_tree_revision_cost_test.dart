// What the scene tree does per scene revision: a gizmo drag bumps it on
// every pointer move without changing anything a row shows, so the tree
// must not walk the whole world each time — while an edit that does change
// a row (an undo step, an entity made) still shows at once. And a row's
// problem mark is read from an index, not by every row going through every
// problem.
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/entities/entity_ops.dart';
import 'package:just_game_engine_editor/src/entities/scope_entities.dart';
import 'package:just_game_engine_editor/src/problems/problem_scan.dart';
import 'package:just_game_engine_editor/src/scene_tree/scene_tree_controller.dart';
import 'package:just_game_engine_editor/src/scene_tree/scene_tree_panel.dart';

import '../support/test_scope.dart';

/// A world that counts how often all of its entities are asked for: what
/// working out the tree's shape costs, once per walk.
class _CountingWorld extends World {
  int walks = 0;

  @override
  UnmodifiableListView<Entity> get entities {
    walks++;
    return super.entities;
  }
}

/// Finds, for each name in [about], that many problems with its entity.
class _Checks extends EditorModule {
  _Checks(this.about);

  final Map<String, int> about;

  @override
  String get id => 'checks';

  @override
  String get name => 'Checks';

  @override
  List<SceneValidator> get validators => [
    (context) => [
      for (final MapEntry(key: name, value: count) in about.entries)
        for (var i = 0; i < count; i++)
          SceneProblem(
            message: '$name $i',
            entity: context.world.findEntityByName(name),
          ),
    ],
  ];
}

void main() {
  late _CountingWorld world;
  late EditorScope scope;
  late EntityOps ops;

  Entity make(String name) {
    final e = world.createEntityWithComponents([
      TransformComponent(),
    ], name: name);
    scope.sceneState.registerEntity(e);
    return e;
  }

  Future<void> pumpTree(WidgetTester tester) async {
    final controller = SceneTreeController(world: () => scope.world);
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(300, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SceneTreePanel(
            scope: scope,
            entities: ops,
            controller: controller,
            onFocusEntity: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
  }

  setUp(() {
    world = _CountingWorld()..initialize();
    scope = testScope(world: world);
    ops = EntityOps(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
      camera: () => GameCameraEditorView.of(OutputCamera()),
    );
    scope.sceneState.openScene(EditorScene(name: 'level'));
  });

  testWidgets('a drag walks the world a few times, not once a move', (
    tester,
  ) async {
    for (var i = 0; i < 50; i++) {
      make('E$i');
    }
    final moved = make('Moved');
    await pumpTree(tester);
    final t = moved.getComponent<TransformComponent>()!;
    world.walks = 0;
    for (var i = 0; i < 30; i++) {
      t.position = Vector3(i.toDouble(), 0, 0);
      scope.sceneState.refresh();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      world.walks,
      lessThan(12),
      reason: '30 moves in half a second: about one look each 250 ms',
    );
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('mid-drag, a rename through the undo history shows at once', (
    tester,
  ) async {
    final crate = make('Crate');
    await pumpTree(tester);
    final t = crate.getComponent<TransformComponent>()!;
    for (var i = 0; i < 3; i++) {
      t.position = Vector3(i.toDouble(), 0, 0);
      scope.sceneState.refresh();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(ops.renameEntity(crate, 'Barrel'), isTrue);
    await tester.pump();
    expect(find.text('Barrel'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('mid-drag, an entity made shows at once', (tester) async {
    final crate = make('Crate');
    await pumpTree(tester);
    final t = crate.getComponent<TransformComponent>()!;
    for (var i = 0; i < 3; i++) {
      t.position = Vector3(i.toDouble(), 0, 0);
      scope.sceneState.refresh();
      await tester.pump(const Duration(milliseconds: 16));
    }
    make('Spawned');
    scope.sceneState.refresh();
    await tester.pump();
    expect(find.text('Spawned'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets("a row's problem mark and the Problems filter are read from "
      "the scan's index", (tester) async {
    final checks = _Checks({'A': 2, 'B': 1});
    scope = testScope(world: world, modules: [checks]);
    scope.sceneState.openScene(EditorScene(name: 'level'));
    final a = make('A'), b = make('B'), c = make('C');
    final controller = SceneTreeController(world: () => scope.world);
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(300, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorScopeProvider(
            scope: scope,
            child: SceneTreePanel(
              scope: scope,
              entities: scope.entities,
              controller: controller,
              onFocusEntity: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final scan = ProblemScan.of(scope);
    expect(scan.problemsFor(a.id), hasLength(2));
    expect(scan.problemsFor(c.id), isEmpty);
    // A's mark counts its two; B's is the mark alone; C has none.
    expect(find.text(' 2'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));

    controller.filter.value = const TreeFilter(problems: true);
    await tester.pump();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsNothing);
    expect(
      scan.entitiesWithProblems,
      unorderedEquals([a.id, b.id]),
      reason: 'what the filter keeps',
    );
    await tester.pump(const Duration(seconds: 2));
  });
}
