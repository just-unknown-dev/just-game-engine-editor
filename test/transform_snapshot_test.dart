import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/state/editor_scene_state.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/state/editor_commands.dart';

void main() {
  test('undoing a 2-D move keeps the z, the tilts and the z scale', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final entity = world.createEntityWithComponents([
      TransformComponent(
        position: Vector3(10, 20, 5),
        euler: Vector3(0.3, -0.2, 0.4),
        scale: Vector3(2, 3, 4),
      ),
    ]);
    final t = entity.getComponent<TransformComponent>()!;

    final before = TransformSnapshot.of(entity);
    // A 2-D gesture: moves x/y, turns about Z, scales x/y.
    t
      ..setPositionXY(50, 60)
      ..angle = 1.0;
    t.scale
      ..x = 1
      ..y = 1;
    final after = TransformSnapshot.of(entity);
    expect(before.matches(after), isFalse);

    final command = TransformCommand(
      label: 'Move',
      entities: [entity],
      before: [before],
      after: [after],
      sceneState: EditorSceneState(),
    );

    // Something else changes the 3-D values in between; undo restores them.
    t.position.z = -1;
    t.eulerX = 0;
    t.scale.z = 1;
    command.undo();
    expect([t.position.x, t.position.y, t.position.z], [10, 20, 5]);
    expect([t.eulerX, t.eulerY, t.angle], [0.3, -0.2, 0.4]);
    expect([t.scale.x, t.scale.y, t.scale.z], [2, 3, 4]);

    command.redo();
    expect([t.position.x, t.position.y, t.position.z], [50, 60, 5]);
    expect([t.eulerX, t.eulerY, t.angle], [0.3, -0.2, 1.0]);
    expect([t.scale.x, t.scale.y, t.scale.z], [1, 1, 4]);
    expect(TransformSnapshot.of(entity).matches(after), isTrue);
  });

  test('moving or turning a parent in the editor carries its children, '
      'and undo brings them back', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final parent = world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, 0, 0)),
      ChildrenComponent(),
    ], name: 'Group');
    final child = world.createEntityWithComponents([
      TransformComponent(position: Vector3(10, 0, 3)),
      ParentComponent(parentId: parent.id),
    ], name: 'Piece');
    parent.getComponent<ChildrenComponent>()!.addChild(child.id);
    final state = EditorSceneState()
      ..setGridSnapping(enabled: false, gridSize: 32);
    final ct = child.getComponent<TransformComponent>()!;

    // No world update has run: authoring, the game's clock stands still.
    final before = TransformSnapshot.of(parent);
    state.setPosition(parent, const Offset(100, 50));
    expect([ct.position.x, ct.position.y, ct.position.z], [110, 50, 3]);

    state.setRotation(parent, math.pi / 2);
    expect(ct.position.x, closeTo(100, 1e-9));
    expect(ct.position.y, closeTo(60, 1e-9));

    TransformCommand(
      label: 'Move',
      entities: [parent],
      before: [before],
      after: [TransformSnapshot.of(parent)],
      sceneState: state,
    ).undo();
    expect(ct.position.x, closeTo(10, 1e-9));
    expect(ct.position.y, closeTo(0, 1e-9));
    expect(ct.position.z, 3);
  });
}
