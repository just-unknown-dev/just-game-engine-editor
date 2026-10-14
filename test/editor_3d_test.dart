// The editor in a 3-D scene: the orbit view it swaps to, picking and
// placing with rays, the 3-D gizmo's drags (and their undo), the kinds of
// file a module adds, commands that belong to one scene mode, and edits
// that keep an entity's depth.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

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

/// A shape test that says every entity in [misses] is not there.
class _Misses implements EntityRayTest {
  _Misses(this.misses);

  final Set<Entity> misses;

  @override
  double? distanceTo(Entity entity, Ray3 ray) =>
      misses.contains(entity) ? double.infinity : null;
}

class _Models extends EditorModule {
  _Models(this.dropped);

  final List<AssetDrop> dropped;

  @override
  String get id => 'test.models';

  @override
  String get name => 'Models';

  @override
  List<AssetKind> get assetKinds => [
    AssetKind(
      'model',
      'Models',
      icon: Icons.view_in_ar,
      endings: const ['.glb', '.gltf'],
      filterable: true,
      drop: (drop) {
        dropped.add(drop);
        return null;
      },
    ),
  ];
}

class _Views extends EditorModule {
  @override
  String get id => 'test.views';

  @override
  String get name => 'Views';

  @override
  Map<SceneMode, EditorView Function(EditorScope scope)> get viewFactories => {
    SceneMode.threeD: (scope) => OrbitFlyEditorView(() => scope.mainCamera)..distance = 42,
  };
}

/// A view from 10 m behind the origin, looking along +Z.
OrbitFlyEditorView _ahead() {
  final view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(200, 200)))
    ..viewportSize = const Size(200, 200)
    ..pivot.setValues(0, 0, 0)
    ..distance = 10
    ..yaw = 0
    ..pitch = 0;
  return view..sync();
}

/// A view from 10 m above the origin, looking down.
OrbitFlyEditorView _above() {
  final view = _ahead()..pitch = -math.pi / 2;
  return view..sync();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the view follows the scene mode', () {
    test('a 3-D scene is seen through the orbit view, a 2-D one flat', () {
      final scope = testScope();
      scope.sceneState.openScene(EditorScene(name: 'deep', mode: SceneMode.threeD));
      final view = scope.editorView;
      expect(view, isA<OrbitFlyEditorView>());
      expect(view.isPlanar, isFalse);
      expect(scope.mainCamera.isPlanar, isFalse, reason: 'it took the camera');

      scope.sceneState.openScene(EditorScene(name: 'flat'));
      expect(scope.editorView, isA<GameCameraEditorView>());
      expect(scope.mainCamera.isPlanar, isTrue, reason: 'handed back flat');
      // Kept: back in 3-D, the same view where it was.
      scope.sceneState.openScene(EditorScene(name: 'deep', mode: SceneMode.threeD));
      expect(identical(scope.editorView, view), isTrue);
    });

    test("a module's view stands in for the built-in one", () {
      final scope = testScope(modules: [_Views()]);
      scope.sceneState.openScene(EditorScene(name: 'deep', mode: SceneMode.threeD));
      expect((scope.editorView as OrbitFlyEditorView).distance, 42);
    });

    test('focusing frames a box whole, and an axis view keeps the pivot', () {
      final view = _ahead();
      view.focusOn(Aabb3.minMax(Vector3(4, -1, 4), Vector3(6, 1, 6)));
      expect([view.pivot.x, view.pivot.y, view.pivot.z], [5, 0, 5]);
      expect(view.distance, greaterThan(math.sqrt(3)));
      view.viewFrom(yaw: 0, pitch: -math.pi / 2);
      expect(view.forward.y, closeTo(1, 1e-3), reason: 'looking down (+Y)');
      expect([view.pivot.x, view.pivot.z], [5, 5]);
    });

    test('the ground under the pointer is where it meets y = 0', () {
      final view = _above();
      final ground = view.screenToGround(view.projectToScreen(Vector3(2, 0, 3))!);
      expect(ground.x, closeTo(2, 1e-6));
      expect(ground.y, closeTo(0, 1e-9));
      expect(ground.z, closeTo(3, 1e-6));
    });
  });

  group('picking and placing with rays', () {
    late World world;

    setUp(() {
      world = World()..initialize();
      addTearDown(world.dispose);
    });

    Entity at(double x, double y, double z) => world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, y, z)),
    ]);

    test('the nearest box under the pointer is picked', () {
      final near = at(0, 0, 0), far = at(0, 0, 5);
      final view = _ahead();
      final centre = view.projectToScreen(Vector3.zero())!;
      expect(RayEntityPicker().pickAt(view, centre, [far, near]), near);
      expect(RayEntityPicker().pickAt(view, centre + const Offset(80, 0), [far, near]), isNull);
    });

    test("a shape test that misses the near one picks what's behind", () {
      final near = at(0, 0, 0), far = at(0, 0, 5);
      final view = _ahead();
      final centre = view.projectToScreen(Vector3.zero())!;
      final picker = RayEntityPicker(tests: () => [_Misses({near})]);
      expect(picker.pickAt(view, centre, [near, far]), far);
    });

    test('placing lands on the top of a box, or on the ground', () {
      final crate = at(0, 0, 0);
      final view = _above();
      final onTop = RayEntityPicker().placementAt(
        view,
        view.projectToScreen(Vector3.zero())!,
        [crate],
      );
      expect(onTop.onto, crate);
      expect(onTop.position.y, closeTo(-0.25, 1e-6), reason: 'its top, up is -Y');
      expect([onTop.normal.x, onTop.normal.y, onTop.normal.z], [0, -1, 0]);

      final beside = RayEntityPicker().placementAt(
        view,
        view.projectToScreen(Vector3(3, 0, 0))!,
        [crate],
      );
      expect(beside.onto, isNull);
      expect(beside.position.x, closeTo(3, 1e-6));
      expect(beside.normal.y, -1);
    });

    test('an entity seen on screen is boxed in 3-D', () {
      final view = _ahead();
      final rect = screenBoundsOf3D(at(0, 0, 0), view)!;
      expect(rect.center.dx, closeTo(100, 1e-6));
      expect(rect.width, greaterThan(4));
    });
  });

  group('the 3-D gizmo', () {
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

    TransformComponent transform() => entity.getComponent<TransformComponent>()!;

    void drag(GizmoDragSolver solver, GizmoHandle handle, EditorView view, Offset from, Offset to) {
      solver
        ..begin(entity, from)
        ..update(handle, entity, to, view)
        ..end();
    }

    test('the point on a line nearest a ray', () {
      final ray = Ray3()..setValues(3, -5, 0, 0, 1, 0);
      expect(RayGizmoDragSolver.closestAlong(Vector3.zero(), Vector3(1, 0, 0), ray), closeTo(3, 1e-9));
      final parallel = Ray3()..setValues(0, -1, 0, 1, 0, 0);
      expect(RayGizmoDragSolver.closestAlong(Vector3.zero(), Vector3(1, 0, 0), parallel), isNull);
    });

    test('an arrow moves along its axis as far as the pointer went', () {
      final view = _ahead();
      drag(
        RayGizmoDragSolver(state),
        GizmoHandle.translateX,
        view,
        view.projectToScreen(Vector3.zero())!,
        view.projectToScreen(Vector3(2, 0, 0))!,
      );
      final p = transform().position;
      expect(p.x, closeTo(2, 1e-6));
      expect(p.y, closeTo(0, 1e-9));
      expect(p.z, closeTo(0, 1e-9));
    });

    test('moving snaps to the 3-D step while snapping is on', () {
      final view = _ahead();
      state.setGridSnapping(enabled: true, gridSize: 32);
      drag(
        RayGizmoDragSolver(state),
        GizmoHandle.translateX,
        view,
        view.projectToScreen(Vector3.zero())!,
        view.projectToScreen(Vector3(1.1, 0, 0))!,
      );
      expect(transform().position.x, closeTo(1.0, 1e-9));
    });

    test('a ring turns by the angle swept about its axis', () {
      final view = _above();
      drag(
        RayGizmoDragSolver(state),
        GizmoHandle.rotateY,
        view,
        view.projectToScreen(Vector3(1, 0, 0))!,
        view.projectToScreen(Vector3(0, 0, 1))!,
      );
      final q = Quaternion.identity();
      transform().rotationInto(q);
      final x = Vector3(1, 0, 0);
      q.rotate(x);
      expect(x.x, closeTo(0, 1e-6));
      expect(x.z, closeTo(1, 1e-6));
    });

    test('the centre box scales evenly by the distance dragged', () {
      final view = _ahead();
      final centre = view.projectToScreen(Vector3.zero())!;
      drag(RayGizmoDragSolver(state), GizmoHandle.scaleUniform, view, centre + const Offset(20, 0), centre + const Offset(40, 0));
      final s = transform().scale;
      expect([s.x, s.y, s.z], [2, 2, 2]);
    });

    test('the gizmo has three arms on screen, Y drawn up', () {
      final view = _ahead();
      final gizmo = Gizmo3D.of(entity, view)!;
      expect(gizmo.tips.whereType<Offset>(), hasLength(3));
      expect(gizmo.tips[1]!.dy, lessThan(gizmo.origin.dy));
      expect(gizmo.handleAt(gizmo.tips[0]!, TransformMode.move), GizmoHandle.translateX);
    });

    test('a drag in the viewport is one undo step, z and all', () {
      final commits = <TransformCommand>[];
      final view = _ahead();
      transform().position.setValues(0, 0, 3);
      final input = ViewportInput(
        world: () => world,
        sceneState: state,
        camera: () => view,
        designer: () => null,
        gridSize: () => 32,
        isActive: () => true,
        isAuthoring: () => true,
        hitTester3D: _OnHandle(GizmoHandle.translateY),
        commitTransform: commits.add,
      )..updateCanvasSize(const Size(200, 200));
      final from = view.projectToScreen(Vector3(0, 0, 3))!;
      final to = view.projectToScreen(Vector3(0, -2, 3))!;
      input
        ..onPointerDown(PointerDownEvent(position: from))
        ..onPointerMove(PointerMoveEvent(position: Offset.lerp(from, to, 0.5)!))
        ..onPointerMove(PointerMoveEvent(position: to))
        ..onPointerUp(PointerUpEvent(position: to));
      expect(commits, hasLength(1));
      expect(transform().position.y, closeTo(-2, 1e-6), reason: 'up is -Y');
      expect(transform().position.z, closeTo(3, 1e-9));
      commits.single.undo();
      final p = transform().position;
      expect([p.x, p.y, p.z], [0, 0, 3]);
      commits.single.redo();
      expect(transform().position.y, closeTo(-2, 1e-6));
    });

    test('a right-click that never moved opens the menu; a drag looks', () {
      final view = _ahead();
      Offset? menuAt;
      final input = ViewportInput(
        world: () => world,
        sceneState: state,
        camera: () => view,
        designer: () => null,
        gridSize: () => 32,
        isActive: () => true,
        isAuthoring: () => true,
        commitTransform: (_) {},
      )..updateCanvasSize(const Size(200, 200));
      input.openMenu = (local, global) => menuAt = local;
      const right = kSecondaryButton;
      input.onPointerDown(const PointerDownEvent(position: Offset(50, 50), buttons: right));
      expect(input.isLooking, isTrue);
      input.onPointerUp(const PointerUpEvent(position: Offset(50, 50)));
      expect(menuAt, const Offset(50, 50));

      menuAt = null;
      final yaw = view.yaw;
      input
        ..onPointerDown(const PointerDownEvent(position: Offset(50, 50), buttons: right))
        ..onPointerMove(const PointerMoveEvent(position: Offset(90, 50), delta: Offset(40, 0), buttons: right))
        ..onPointerUp(const PointerUpEvent(position: Offset(90, 50)));
      expect(menuAt, isNull);
      expect(view.yaw, isNot(yaw));
    });
  });

  group('kinds of file', () {
    test("a module's kind is known while it is in, with its drop", () {
      final dropped = <AssetDrop>[];
      final scope = testScope(modules: [_Models(dropped)]);
      final kind = AssetKind.of('assets/models/Crate.GLB');
      expect(kind.id, 'model');
      expect(AssetKinds.active.filters.map((k) => k.id), contains('model'));
      expect(AssetKind.of('assets/a.scene.json'), AssetKind.scene);
      expect(AssetKind.of('assets/a.json'), AssetKind.data);

      Entity? placed;
      final drop = AssetDrop(
        scope: scope,
        path: 'assets/models/crate.glb',
        at: Vector3(1, 0, 2),
        place: (components, name) => placed = scope.world.createEntityWithComponents(components, name: name),
      );
      kind.drop!(drop);
      expect(dropped.single.path, 'assets/models/crate.glb');
      drop.place(const []);
      final p = placed!.getComponent<TransformComponent>()!.position;
      expect([p.x, p.y, p.z], [1, 0, 2], reason: 'stood where it was dropped');

      testScope();
      expect(AssetKind.of('assets/models/crate.glb'), AssetKind.other);
    });
  });

  group('commands of one scene mode', () {
    test('a chord runs the command for the mode the scene is in', () {
      final scope = testScope();
      final ran = <String>[];
      final registry = CommandRegistry()
        ..register(DesignerCommand(id: 'flat', label: 'flat', scope: CommandScope.editor, dimensions: Dimensions.twoD, run: (_) => ran.add('flat')))
        ..register(DesignerCommand(id: 'deep', label: 'deep', scope: CommandScope.editor, dimensions: Dimensions.threeD, run: (_) => ran.add('deep')))
        ..bind(const KeyBinding(LogicalKeyboardKey.keyX, 'flat'))
        ..bind(const KeyBinding(LogicalKeyboardKey.keyX, 'deep'));
      final context = CommandContext(scope: scope, modifiers: const ModifierKeys());
      scope.sceneState.openScene(EditorScene(name: 'flat'));
      registry.dispatch(LogicalKeyboardKey.keyX, context, scopes: const {CommandScope.editor});
      scope.sceneState.openScene(EditorScene(name: 'deep', mode: SceneMode.threeD));
      registry.dispatch(LogicalKeyboardKey.keyX, context, scopes: const {CommandScope.editor});
      expect(ran, ['flat', 'deep']);
    });

    test('the built-in 3-D view commands have keys', () {
      final scope = testScope();
      for (final id in ['editor.view.frame', 'editor.view.top', 'editor.view.front', 'editor.gizmo.local']) {
        expect(scope.commands.byId(id), isNotNull, reason: id);
        expect(scope.commands.bindingsFor(id), isNotEmpty, reason: id);
      }
    });
  });

  group('edits keep depth', () {
    late EditorScope scope;
    late EntityOps ops;
    late EditorView view;

    setUp(() {
      scope = testScope();
      view = GameCameraEditorView.of(Camera());
      ops = EntityOps(
        scope: scope,
        world: () => scope.world,
        sceneState: scope.sceneState,
        camera: () => view,
      );
      scope.sceneState.openScene(EditorScene(name: 'level_test'));
    });

    Entity box(String name, double x, double y, double z) {
      final e = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(x, y, z)),
      ], name: name);
      scope.sceneState.registerEntity(e);
      return e;
    }

    Vector3 where(Entity e) => e.getComponent<TransformComponent>()!.position;

    test('a duplicate keeps z; in space it steps a metre along X', () {
      final a = box('a', 10, 20, 7);
      scope.sceneState.selectEntity(a);
      ops.duplicateSelection(scope.history, gridSize: 32);
      final flatCopy = scope.sceneState.selectedEntity.value!;
      expect([where(flatCopy).x, where(flatCopy).y, where(flatCopy).z], [42, 52, 7]);

      view = _ahead();
      scope.sceneState.selectEntity(a);
      ops.duplicateSelection(scope.history, gridSize: 32);
      final deepCopy = scope.sceneState.selectedEntity.value!;
      expect([where(deepCopy).x, where(deepCopy).y, where(deepCopy).z], [11, 20, 7]);
    });

    test('a group sits at the middle of what it holds, depth too', () {
      final a = box('a', 0, 0, 2), b = box('b', 4, 2, 6);
      scope.sceneState
        ..selectEntity(a)
        ..toggleMultiSelect(b);
      final group = ops.groupSelection()!;
      final p = where(group);
      expect([p.x, p.y, p.z], [2, 1, 4]);
    });

    test('a paste keeps its depth in 2-D and lands on the point in 3-D', () {
      final a = box('a', 0, 0, 9);
      ops.copyEntity(a);
      ops.pasteEntity(at: const Offset(5, 6));
      var p = where(scope.sceneState.selectedEntity.value!);
      expect([p.x, p.y, p.z], [5, 6, 9]);

      ops.pasteEntity(point: Vector3(1, 0, 3));
      p = where(scope.sceneState.selectedEntity.value!);
      expect([p.x, p.y, p.z], [1, 0, 3]);
    });

    test('a new entity in space goes where the view looks', () {
      view = _ahead()..pivot.setValues(3, 0, 4);
      ops.createEntity();
      final p = where(scope.sceneState.selectedEntity.value!);
      expect([p.x, p.y, p.z], [3, 0, 4]);
    });
  });
}
