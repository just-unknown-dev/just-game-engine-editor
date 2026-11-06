// How the editor's hot paths scale with a big scene: what one scene
// revision costs with the scene tree and the inspector mounted (every
// pointer move of a drag is one), what the problem scan costs, and what a
// rename frame costs. Each under a wall-clock ceiling far above what it
// measures, so only a change in how it scales — per entity where it was per
// change — fails it.
//
// Skipped in a plain run (dart_test.yaml); run with:
//   flutter test --tags perf --run-skipped test/perf
@Tags(['perf'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/entities/entity_ops.dart';
import 'package:just_game_engine_editor/src/inspector/entity_inspector_panel.dart';
import 'package:just_game_engine_editor/src/problems/problem_scan.dart';
import 'package:just_game_engine_editor/src/scene_tree/scene_tree_controller.dart';
import 'package:just_game_engine_editor/src/scene_tree/scene_tree_panel.dart';

import '../support/test_scope.dart';

/// How many entities the scene holds: a big level.
const int _entities = 5000;

/// The ceilings, in microseconds, in the debug JIT the editor runs in.
/// Measured on 2026-11-05: about 1.8 ms, 20 ms and 60 ms.
const int _revisionCeiling = 8000;
const int _problemScanCeiling = 100000;
const int _renameFrameCeiling = 250000;

void main() {
  testWidgets('a big scene: a revision, the problem scan and a rename stay '
      'under their ceilings', (tester) async {
    final scope = testScope();
    final ops = EntityOps(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
      camera: () => GameCameraEditorView.of(OutputCamera()),
    );
    final controller = SceneTreeController(world: () => scope.world);
    addTearDown(controller.dispose);
    scope.sceneState.openScene(EditorScene(name: 'level'));
    late Entity first;
    for (var i = 0; i < _entities; i++) {
      final e = scope.world.createEntityWithComponents([
        TransformComponent(),
        LayerComponent(),
        TagComponent('t${i % 7}'),
      ], name: 'E$i');
      scope.sceneState.registerEntity(e);
      if (i == 0) first = e;
    }

    tester.view
      ..physicalSize = const Size(640, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 300,
                child: SceneTreePanel(
                  scope: scope,
                  entities: ops,
                  controller: controller,
                  onFocusEntity: (_) {},
                ),
              ),
              Expanded(
                child: EntityInspectorPanel(
                  sceneState: scope.sceneState,
                  world: scope.world,
                  scope: scope,
                  onGroupSelection: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    scope.sceneState.selectEntity(first);
    await tester.pump();

    // One revision, as each pointer move of a drag makes, with everything
    // that follows it mounted.
    var clock = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      scope.sceneState.refresh();
    }
    final revision = clock.elapsedMicroseconds ~/ 50;

    final scan = ProblemScan.of(scope);
    clock = Stopwatch()..start();
    for (var i = 0; i < 3; i++) {
      scan.refresh();
    }
    final problems = clock.elapsedMicroseconds ~/ 3;

    clock = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      first.name = 'Renamed$i';
      scope.sceneState.refresh();
      await tester.pump(const Duration(milliseconds: 16));
    }
    final rename = clock.elapsedMicroseconds ~/ 10;

    // ignore: avoid_print
    print(
      '$_entities entities: a revision ${revision / 1000} ms, the problem '
      'scan ${problems / 1000} ms, a rename frame ${rename / 1000} ms',
    );
    expect(revision, lessThan(_revisionCeiling), reason: 'a revision');
    expect(problems, lessThan(_problemScanCeiling), reason: 'the scan');
    expect(rename, lessThan(_renameFrameCeiling), reason: 'a rename');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
