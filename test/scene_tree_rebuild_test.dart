// The scene tree builds its rows again when what they show changes, not on
// every edit: a gizmo drag bumps the scene's revision on every pointer move,
// and building every row each time made the drag stutter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/entity/entity_ops.dart';
import 'package:just_game_engine_editor/src/ui/scene_tree/scene_tree_controller.dart';
import 'package:just_game_engine_editor/src/ui/scene_tree/scene_tree_panel.dart';

import 'support/test_scope.dart';

/// Counts how often the tree asks for a row's decorations: once per row
/// built.
class _RowCounter extends EditorModule {
  _RowCounter(this.built);

  final void Function() built;

  @override
  String get id => 'test.rowCounter';

  @override
  String get name => 'Row counter';

  @override
  List<SceneTreeRowDecoration> get rowDecorations => [
    SceneTreeRowDecoration(
      id: 'count',
      build: (context, entity) {
        built();
        return null;
      },
    ),
  ];
}

void main() {
  testWidgets('a move builds no row; a rename shows at once; the marks '
      'catch up once the scene is still', (tester) async {
    var built = 0;
    final scope = testScope(modules: [_RowCounter(() => built++)]);
    final ops = EntityOps(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
      camera: () => GameCameraEditorView.of(Camera()),
    );
    final controller = SceneTreeController(world: () => scope.world);
    addTearDown(controller.dispose);
    scope.sceneState.openScene(EditorScene(name: 'level'));
    final crate = scope.world.createEntityWithComponents([
      TransformComponent(),
    ], name: 'Crate');
    scope.sceneState.registerEntity(crate);

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
    await tester.pump();
    expect(find.text('Crate'), findsOneWidget);

    // A drag: the crate moves on every frame.
    final transform = crate.getComponent<TransformComponent>()!;
    built = 0;
    for (var i = 0; i < 20; i++) {
      transform.position = Vector3.fromXY(i.toDouble(), 0);
      scope.sceneState.refresh();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(built, 0, reason: 'no row built again while it moved');

    // Still for a moment: built once more, for what a row shows from the
    // values.
    await tester.pump(const Duration(seconds: 2));
    expect(built, greaterThan(0));

    // A rename is the tree's business: shown at once.
    crate.name = 'Barrel';
    scope.sceneState.refresh();
    await tester.pump();
    expect(find.text('Barrel'), findsOneWidget);
  });
}
