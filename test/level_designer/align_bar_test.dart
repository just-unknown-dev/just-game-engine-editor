// Align and Distribute line the selection up as one undo step — and when
// it is lined up already, record nothing and leave the scene unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import '../support/test_scope.dart';
import 'package:just_game_engine_editor/src/level_designer/panels/align_bar.dart';

void main() {
  late World world;
  late EditorScope scope;
  late LevelDesignerSession session;

  Entity block(String name, double x, double y) {
    final e = world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, y, 0)),
      Rectangle2DComponent(width: 64, height: 32),
      LayerComponent(),
    ], name: name);
    session.sceneState.registerEntity(e);
    return e;
  }

  setUp(() {
    world = World()..initialize();
    scope = testScope(world: world);
    scope.sceneState.openScene(EditorScene(name: 'level'));
    session = LevelDesignerSession(
      scope: scope,
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => const ModifierKeys(),
    );
    addTearDown(session.dispose);
  });

  Future<void> pump(WidgetTester tester, List<Entity> selected) async {
    for (final e in selected) {
      session.sceneState.toggleMultiSelect(e);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AlignBar(session: session, gridSize: 32)),
      ),
    );
  }

  testWidgets('lining up what is lined up already is no undo step, and '
      'the scene stays saved', (tester) async {
    final a = block('A', 32, 16);
    final b = block('B', 32, 116);
    await pump(tester, [a, b]);
    final dirty = scope.sceneState.isDirty.value;
    await tester.tap(find.byTooltip('Align left edges'));
    await tester.pump();
    expect(scope.history.undoEntries, isEmpty);
    expect(scope.sceneState.isDirty.value, dirty);
    expect(a.getComponent<TransformComponent>()!.position.x, 32);
  });

  testWidgets('lining up what is not is one undo step', (tester) async {
    final a = block('A', 32, 16);
    final b = block('B', 72, 116);
    await pump(tester, [a, b]);
    await tester.tap(find.byTooltip('Align left edges'));
    await tester.pump();
    expect(b.getComponent<TransformComponent>()!.position.x, 32);
    expect(scope.history.undoEntries, hasLength(1));
    scope.history.undo();
    expect(b.getComponent<TransformComponent>()!.position.x, 72);
  });

  testWidgets('spacing out what is evenly spaced already is no undo step', (
    tester,
  ) async {
    final a = block('A', 0, 0);
    final b = block('B', 100, 0);
    final c = block('C', 200, 0);
    await pump(tester, [a, b, c]);
    await tester.tap(find.byTooltip('Distribute horizontally'));
    await tester.pump();
    expect(scope.history.undoEntries, isEmpty);
  });
}
