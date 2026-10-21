// The 3-D gizmo on a selection: where it sits (centre, pivot, base), the
// whole selection moved, turned and scaled about it as one undo step, a
// value typed while dragging, the ring that turns about the view, and a
// move landing on a surface, beside a neighbour's box, or corner on corner.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart' show Cube3D, Graphics3D;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/input/selection_pivot.dart';
import 'package:just_game_engine_editor/src/core/input/translate_snaps_3d.dart';
import 'package:just_game_engine_editor/src/core/input/viewport_input.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/ui/overlay/gizmo_3d.dart';
import 'package:just_game_engine_editor/src/ui/overlay/gizmo_painter.dart';

/// Reports a press on [handle] of the selected entity, wherever it lands.
class _OnHandle extends GizmoHitTester {
  _OnHandle(this.handle);

  final GizmoHandle handle;

  @override
  GizmoHitResult hitTest(
    Offset screenPos,
    Entity? selected,
    List<Entity> entities,
    EditorView camera,
    Size canvasSize, {
    TransformMode mode = TransformMode.all,
    Set<TransformMode>? allows,
  }) => GizmoHitResult(handle, selected);
}

/// A view from 20 m above the origin, looking down.
OrbitFlyEditorView _above() {
  final view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(400, 400)))
    ..viewportSize = const Size(400, 400)
    ..pivot.setValues(0, 0, 0)
    ..distance = 20
    ..yaw = 0
    ..pitch = -math.pi / 2;
  return view..sync();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EditorScope scope;
  late OrbitFlyEditorView view;
  late Entity a, b;
  final commits = <TransformCommand>[];

  setUp(() {
    final world = World()..initialize();
    // Shapes' sizes, for their boxes.
    Graphics3D.registerSchemas(world.context);
    scope = testScope(world: world);
    scope.sceneState.openScene(EditorScene(name: 'deep', mode: SceneMode.threeD));
    view = _above();
    a = world.createEntityWithComponents([TransformComponent(position: Vector3(0, -0.5, 0)), Cube3D()], name: 'a');
    b = world.createEntityWithComponents([TransformComponent(position: Vector3(4, -0.5, 0)), Cube3D()], name: 'b');
    commits.clear();
  });

  Vector3 at(Entity e) => e.getComponent<TransformComponent>()!.position;

  ViewportInput input(GizmoHandle handle, {TranslateSnaps3D? snaps}) => ViewportInput(
    world: () => scope.world,
    sceneState: scope.sceneState,
    camera: () => view,
    designer: () => null,
    gridSize: () => 32,
    isActive: () => true,
    isAuthoring: () => true,
    hitTester3D: _OnHandle(handle),
    commitTransform: commits.add,
    selection: () => scope.entities.selectionEntities,
    pivotOf: (entities) => SelectionPivot.of(entities, scope.designer3D.pivotMode.value),
    snaps3D: snaps,
  )..updateCanvasSize(const Size(400, 400));

  void selectBoth() {
    scope.sceneState
      ..selectEntity(a)
      ..toggleMultiSelect(b);
  }

  group('the pivot', () {
    test('the middle, the first one\'s origin, or the middle of the base', () {
      final both = [a, b];
      final centre = SelectionPivot.of(both, PivotMode3D.centre);
      expect([centre.x, centre.y, centre.z], [2, -0.5, 0]);
      final pivot = SelectionPivot.of(both, PivotMode3D.pivot);
      expect([pivot.x, pivot.z], [0, 0]);
      final base = SelectionPivot.of(both, PivotMode3D.base);
      expect(base.y, closeTo(0, 1e-9), reason: 'the bottom: up is -Y');
    });

    test('the gizmo sits on the pivot', () {
      final gizmo = Gizmo3D.of(a, view, pivot: Vector3(2, -0.5, 0))!;
      expect((gizmo.origin - view.projectToScreen(Vector3(2, -0.5, 0))!).distance, lessThan(1e-6));
    });
  });

  group('the whole selection', () {
    test('moves together, one undo step', () {
      selectBoth();
      final i = input(GizmoHandle.translateX);
      final from = view.projectToScreen(at(a))!;
      final to = view.projectToScreen(at(a) + Vector3(2, 0, 0))!;
      i
        ..onPointerDown(PointerDownEvent(position: from))
        ..onPointerMove(PointerMoveEvent(position: to))
        ..onPointerUp(PointerUpEvent(position: to));
      expect(at(a).x, closeTo(2, 1e-3));
      expect(at(b).x, closeTo(6, 1e-3));
      expect(commits, hasLength(1));
      expect(commits.single.entities, hasLength(2));
      commits.single.undo();
      expect([at(a).x, at(b).x], [0, 4]);
    });

    test('turns about the pivot: a typed 90 degrees about up', () {
      selectBoth();
      scope.designer3D.pivotMode.value = PivotMode3D.centre;
      final i = input(GizmoHandle.rotateY);
      final from = view.projectToScreen(at(a))!;
      i.onPointerDown(PointerDownEvent(position: from));
      expect(i.typeKey(LogicalKeyboardKey.digit9), isTrue);
      expect(i.typeKey(LogicalKeyboardKey.digit0), isTrue);
      expect(i.typedLabel, 'Turn 90°');
      expect(i.typeKey(LogicalKeyboardKey.enter), isTrue);
      // About (2, -0.5, 0): a, two metres to its left, ends up two metres
      // ahead or behind, b opposite it.
      expect(at(a).x, closeTo(2, 1e-6));
      expect(at(a).z.abs(), closeTo(2, 1e-6));
      expect(at(b).z, closeTo(-at(a).z, 1e-6));
      expect(commits, hasLength(1), reason: 'Enter keeps it');
    });

    test('scales about the pivot, spreading apart', () {
      selectBoth();
      scope.designer3D.pivotMode.value = PivotMode3D.centre;
      final i = input(GizmoHandle.scaleUniform);
      i.onPointerDown(PointerDownEvent(position: view.projectToScreen(Vector3(2, -0.5, 0))!));
      i
        ..typeKey(LogicalKeyboardKey.digit2)
        ..typeKey(LogicalKeyboardKey.enter);
      expect(a.getComponent<TransformComponent>()!.scale.x, closeTo(2, 1e-6));
      expect([at(a).x, at(b).x], [closeTo(-2, 1e-6), closeTo(6, 1e-6)]);
    });

    test('what is inside something selected moves with it, not twice', () {
      final child = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, -2, 0)),
        ParentComponent(parentId: a.id),
      ], name: 'child');
      scope.sceneState
        ..selectEntity(a)
        ..toggleMultiSelect(child);
      final i = input(GizmoHandle.translateX);
      i.onPointerDown(PointerDownEvent(position: view.projectToScreen(at(a))!));
      i
        ..typeKey(LogicalKeyboardKey.digit1)
        ..typeKey(LogicalKeyboardKey.enter);
      expect(commits.single.entities.map((e) => e.name), ['a']);
    });

    test('Escape puts everything back', () {
      selectBoth();
      final i = input(GizmoHandle.translateX);
      i.onPointerDown(PointerDownEvent(position: view.projectToScreen(at(a))!));
      i
        ..typeKey(LogicalKeyboardKey.digit5)
        ..typeKey(LogicalKeyboardKey.escape);
      expect([at(a).x, at(b).x], [0, 4]);
      expect(commits, isEmpty);
    });
  });

  test('the outer ring turns about the way the view looks', () {
    final gizmo = Gizmo3D.of(a, view)!;
    // Between the arms, out on the ring.
    final onRing = gizmo.origin + Offset.fromDirection(math.pi / 4, Gizmo3D.viewRingRadius);
    expect(gizmo.handleAt(onRing, TransformMode.all), GizmoHandle.rotateView);
    scope.sceneState.selectEntity(b);
    final i = input(GizmoHandle.rotateView);
    i.onPointerDown(PointerDownEvent(position: view.projectToScreen(at(b))!));
    i
      ..typeKey(LogicalKeyboardKey.digit9)
      ..typeKey(LogicalKeyboardKey.digit0)
      ..typeKey(LogicalKeyboardKey.enter);
    // Looking down, a turn about the view is a turn about up.
    final t = b.getComponent<TransformComponent>()!;
    expect(t.eulerY.abs(), closeTo(math.pi / 2, 1e-3));
  });

  group('snapping a move', () {
    late bool holdingV;
    late TranslateSnaps3D snaps;

    setUp(() {
      // Off, so only the snaps under test move things onto round numbers.
      scope.sceneState.setGridSnapping(enabled: false, gridSize: 32);
      holdingV = false;
      snaps = TranslateSnaps3D(
        view: () => view,
        state: () => scope.designer3D,
        surfaceAt: (screen, ignore) => RayEntityPicker(tests: () => scope.pickTests).placementAt(
          view,
          screen,
          scope.world.entities.where((e) => !ignore.contains(e)),
        ),
        candidates: () => scope.world.entities,
        vertexSources: () => scope.pickTests.whereType<EntityVertexSource>(),
        holdingV: () => holdingV,
      );
    });

    void moveA(Vector3 to) {
      scope.sceneState.selectEntity(a);
      final i = input(GizmoHandle.translateXZ, snaps: snaps);
      i
        ..onPointerDown(PointerDownEvent(position: view.projectToScreen(at(a))!))
        ..onPointerMove(PointerMoveEvent(position: view.projectToScreen(to)!))
        ..onPointerUp(PointerUpEvent(position: view.projectToScreen(to)!));
    }

    test('onto the surface under the pointer', () {
      scope.designer3D.surfaceSnap.value = true;
      moveA(Vector3(4, -1, 0));
      expect(at(a).y, closeTo(-1.5, 1e-6), reason: 'standing on b\'s top');
      expect(at(a).x, closeTo(4, 1e-3));
    });

    test('lined up with a neighbour\'s side', () {
      scope.designer3D.boundsSnap.value = true;
      moveA(Vector3(2.9, -0.5, 0.1));
      expect(at(a).x, closeTo(3, 1e-6), reason: 'its side against b\'s');
      expect(at(a).z, closeTo(0, 1e-6), reason: 'and level with it');
    });

    test('a corner on a corner, V held', () {
      holdingV = true;
      // Taken hold of at a's corner (0.5, -1, 0.5), let go over b's
      // (3.5, -1, 0.5): the ground-plane move alone would not land there,
      // seen in perspective.
      scope.sceneState.selectEntity(a);
      final i = input(GizmoHandle.translateXZ, snaps: snaps);
      i
        ..onPointerDown(PointerDownEvent(position: view.projectToScreen(Vector3(0.5, -1, 0.5))!))
        ..onPointerMove(PointerMoveEvent(position: view.projectToScreen(Vector3(3.5, -1, 0.5))!))
        ..onPointerUp(PointerUpEvent(position: view.projectToScreen(Vector3(3.5, -1, 0.5))!));
      expect([at(a).x, at(a).z], [closeTo(3, 1e-6), closeTo(0, 1e-6)]);
    });
  });
}
