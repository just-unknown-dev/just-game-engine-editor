// The gizmos do what their handles say: an arrow moves along its axis even
// with surface snapping on, a typed value is the move exactly, and a scale
// handle keeps a flipped entity flipped and a big one as big as it was.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/input/gizmo_drag_solver.dart';
import 'package:just_game_engine_editor/src/core/input/ray_gizmo_drag_solver.dart';
import 'package:just_game_engine_editor/src/ui/overlay/gizmo_painter.dart';

OrbitFlyEditorView _ahead() {
  final view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(200, 200)))
    ..viewportSize = const Size(200, 200)
    ..pivot.setValues(0, 0, 0)
    ..distance = 10
    ..yaw = 0
    ..pitch = 0;
  return view..sync();
}

void main() {
  group('3-D moves with snaps on (EC-24)', () {
    late World world;
    late Entity entity;
    late EditorSceneState state;

    setUp(() {
      world = World()..initialize();
      addTearDown(world.dispose);
      entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3.zero()),
      ]);
      state = EditorSceneState()
        ..setGridSnapping(enabled: false, gridSize: 32)
        ..selectEntity(entity);
    });

    Vector3 position() => entity.getComponent<TransformComponent>()!.position;

    // A snap that would put it anywhere: onto a surface up and away.
    Vector3 anywhere(Vector3 delta, Ray3 ray, Offset screen) =>
        Vector3(delta.x + 0.5, 3, 4);

    test('an arrow keeps to its axis', () {
      final view = _ahead();
      final solver = RayGizmoDragSolver(state)..adjustMove = anywhere;
      solver
        ..begin(entity, view.projectToScreen(Vector3.zero())!)
        ..update(
          GizmoHandle.translateX,
          entity,
          view.projectToScreen(Vector3(2, 0, 0))!,
          view,
        );
      expect(position().x, closeTo(2.5, 1e-6), reason: 'slid along it');
      expect(position().y, closeTo(0, 1e-9));
      expect(position().z, closeTo(0, 1e-9));
    });

    test('a typed value is the move, exactly', () {
      final view = _ahead();
      final solver = RayGizmoDragSolver(state)..adjustMove = anywhere;
      solver.begin(entity, view.projectToScreen(Vector3.zero())!);
      solver.exact = 2;
      solver.update(
        GizmoHandle.translateX,
        entity,
        view.projectToScreen(Vector3(0.7, 0, 0))!,
        view,
      );
      expect(position().x, closeTo(2, 1e-9));
      expect(position().y, closeTo(0, 1e-9));
      expect(position().z, closeTo(0, 1e-9));
    });
  });

  group('2-D scale handles (EC-37)', () {
    test('keep the sign and have no cap', () {
      expect(PlanarGizmoDragSolver.scaledBy(-1, 2), -2);
      expect(PlanarGizmoDragSolver.scaledBy(64, 1.5), 96);
      expect(
        PlanarGizmoDragSolver.scaledBy(2, 0),
        PlanarGizmoDragSolver.minScale,
      );
      expect(
        PlanarGizmoDragSolver.scaledBy(-2, 0),
        -PlanarGizmoDragSolver.minScale,
      );
    });
  });
}
