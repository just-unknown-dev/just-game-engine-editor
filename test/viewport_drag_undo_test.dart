// A drag of the transform gizmo in the plain viewport (no Level Designer
// open) is one undo step. Before, the gizmo moved the entity through the
// scene state's setters and nothing was recorded, so Ctrl+Z could not take
// a drag back.
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/input/viewport_input.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late World world;
  late Entity entity;
  late List<TransformCommand> commits;
  late ViewportInput input;

  ViewportInput viewport(GizmoHandle handle) {
    final state = EditorSceneState()
      ..setGridSnapping(enabled: false, gridSize: 32)
      ..selectEntity(entity);
    final view = GameCameraEditorView.of(
      Camera(viewportSize: const Size(200, 200)),
    );
    return ViewportInput(
      world: () => world,
      sceneState: state,
      camera: () => view,
      designer: () => null,
      gridSize: () => 32,
      isActive: () => true,
      isAuthoring: () => true,
      hitTester: _OnHandle(handle),
      commitTransform: commits.add,
    )..updateCanvasSize(const Size(200, 200));
  }

  setUp(() {
    world = World()..initialize();
    addTearDown(world.dispose);
    entity = world.createEntityWithComponents([
      TransformComponent(position: Vector3(10, 20, 3)),
    ]);
    commits = [];
    input = viewport(GizmoHandle.translateX);
  });

  void drag(Offset from, Offset to) {
    input.onPointerDown(PointerDownEvent(position: from));
    input.onPointerMove(PointerMoveEvent(position: Offset.lerp(from, to, 0.5)!));
    input.onPointerMove(PointerMoveEvent(position: to));
  }

  TransformComponent transform() => entity.getComponent<TransformComponent>()!;

  test('a gizmo drag becomes one command that undoes and redoes it', () {
    drag(const Offset(100, 100), const Offset(130, 100));
    expect(commits, isEmpty, reason: 'nothing is recorded mid-drag');
    input.onPointerUp(const PointerUpEvent(position: Offset(130, 100)));

    expect(commits, hasLength(1));
    expect(commits.single.label, startsWith('Move'));
    expect(transform().position.x, 40);

    commits.single.undo();
    final p = transform().position;
    expect([p.x, p.y, p.z], [10, 20, 3]);
    commits.single.redo();
    expect(transform().position.x, 40);
  });

  test('a press that moves nothing records nothing', () {
    input.onPointerDown(const PointerDownEvent(position: Offset(100, 100)));
    input.onPointerUp(const PointerUpEvent(position: Offset(100, 100)));
    expect(commits, isEmpty);
  });

  test('a drag the system cancels is still recorded, so it can be undone', () {
    drag(const Offset(100, 100), const Offset(150, 100));
    input.onPointerCancel(const PointerCancelEvent());
    expect(commits, hasLength(1));
    expect(transform().position.x, 60);
    commits.single.undo();
    expect(transform().position.x, 10);
  });

  test('a rotation is labelled as one', () {
    input = viewport(GizmoHandle.rotate);
    drag(const Offset(150, 100), const Offset(100, 150));
    input.onPointerUp(const PointerUpEvent(position: Offset(100, 150)));
    expect(commits, hasLength(1));
    expect(commits.single.label, startsWith('Rotate'));
  });
}
