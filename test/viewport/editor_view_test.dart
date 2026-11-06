import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/viewport/gizmos/gizmo_drag_solver.dart';
import 'package:just_game_engine_editor/src/viewport/gizmos/gizmo_2d_painter.dart';

GameCameraEditorView _flatView() => GameCameraEditorView.of(
  OutputCamera(
    position: const Offset(40, -20),
    zoom: 2,
    rotation: 0.3,
    viewportSize: const Size(800, 600),
  ),
);

/// A camera in space: 20 units in front of the world plane, looking at it.
GameCameraEditorView _deepView() => GameCameraEditorView.of(
  OutputCamera(
    viewportSize: const Size(400, 400),
    z: -20,
    lens: const CameraLens.perspective(fieldOfView: math.pi / 2),
  ),
);

void main() {
  group('the 2-D editor view', () {
    test('converts as its camera does, and its rays agree', () {
      final view = _flatView();
      expect(view.isPlanar, isTrue);
      const screen = Offset(123, 456);
      final world = view.screenToWorld(screen);
      expect(view.camera.screenToWorld(screen), world);
      final ray = view.screenToRay(screen);
      final hit = Vector3.zero();
      ray.atInto(ray.intersectZ()!, hit);
      expect(hit.x, closeTo(world.dx, 1e-6));
      expect(hit.y, closeTo(world.dy, 1e-6));
      final back = view.projectToScreen(Vector3(world.dx, world.dy, 0))!;
      expect(back.dx, closeTo(screen.dx, 1e-6));
      expect(back.dy, closeTo(screen.dy, 1e-6));
    });

    test('pans and zooms its camera', () {
      final view = _flatView();
      view.moveBy(const Offset(10, 0));
      expect(view.position, const Offset(50, -20));
      view.setZoom(1000);
      expect(view.zoom, view.maxZoom);
      final state = view.state;
      view.setPosition(Offset.zero);
      view.apply(state);
      expect(view.position, const Offset(50, -20));
    });
  });

  group('in a view in space', () {
    test('a point behind the viewer has no place on screen', () {
      final view = _deepView();
      expect(view.isPlanar, isFalse);
      expect(view.projectToScreen(Vector3(0, 0, 0)), isNotNull);
      expect(view.projectToScreen(Vector3(0, 0, -30)), isNull);
    });
  });

  group('gizmo handles', () {
    test('say what they do and along which axes', () {
      expect(GizmoHandle.translateXY.op, GizmoOp.translate);
      expect(GizmoHandle.translateXY.uses(GizmoAxes.x), isTrue);
      expect(GizmoHandle.translateXY.uses(GizmoAxes.z), isFalse);
      expect(GizmoHandle.rotate.op, GizmoOp.rotate);
      expect(GizmoHandle.rotate.axes, GizmoAxes.z);
      expect(GizmoHandle.scaleZ.axes, GizmoAxes.z, reason: 'ready for 3-D');
    });

    test('the 2-D solver drags a move handle by the pointer', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 7)),
      ]);
      final state = EditorSceneState()
        ..setGridSnapping(enabled: false, gridSize: 32);
      final view = GameCameraEditorView.of(
        OutputCamera(viewportSize: const Size(200, 200)),
      );
      final solver = Gizmo2DDragSolver(state)
        ..begin(entity, const Offset(100, 100));
      solver.update(
        GizmoHandle.translateX,
        entity,
        const Offset(130, 140),
        view,
      );
      final t = entity.getComponent<TransformComponent>()!;
      expect([t.position.x, t.position.y, t.position.z], [30, 0, 7]);
      solver.end();
    });
  });
}
