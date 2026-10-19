import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/entity/entity_ops.dart';
import 'package:just_game_engine_editor/src/ui/scene_tree/scene_tree_panel.dart';

void main() {
  testWidgets('search filters by name and by component type', (tester) async {
    final scope = testScope();
    scope.sceneState.openScene(EditorScene(name: 'level'));
    final ops = EntityOps(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
      camera: () => GameCameraEditorView.of(Camera()),
    );
    scope.world
      ..createEntityWithComponents([
        TransformComponent(),
        SpawnComponent(),
      ], name: 'PlayerStart')
      ..createEntityWithComponents([
        TransformComponent(),
        RectangleComponent(width: 10, height: 10),
      ], name: 'Ledge')
      ..createEntityWithComponents([TransformComponent()], name: 'Marker');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SceneTreePanel(scope: scope, entities: ops),
        ),
      ),
    );
    expect(find.text('Ledge'), findsOneWidget);
    expect(find.text('Marker'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'spawn');
    await tester.pump();
    expect(find.text('PlayerStart'), findsOneWidget, reason: 'by component');
    expect(find.text('Ledge'), findsNothing);

    await tester.enterText(find.byType(TextField), 'ledge');
    await tester.pump();
    expect(find.text('Ledge'), findsOneWidget, reason: 'by name');
    expect(find.text('Marker'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.pump();
    expect(find.textContaining('Nothing matches'), findsOneWidget);
  });
}
