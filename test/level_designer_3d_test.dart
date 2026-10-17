// The Level Designer in a 3-D scene: the same designer with the default
// kit for 3-D — Select, Place and the basic shapes — and only the kits made
// for 3-D in its switch. What is 2-D only (the Level Map, its layers and
// tileset, the 2-D tools and framing) stays out of it, and the 3-D gizmo
// keeps working with it open.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

/// A kit for 2-D levels: a prefab that places in 2-D.
class _Flat extends EditorModule {
  @override
  String get id => 'flat';
  @override
  String get name => 'Flat';
  @override
  List<PrefabDefinition> get prefabs => [
    PrefabDefinition(
      id: 'flat.thing',
      name: 'Flat thing',
      category: 'Flat',
      icon: Icons.crop_square,
      color: Colors.blue,
      build: (_, _) => [TransformComponent()],
    ),
  ];
}

/// A kit for 3-D levels: a prefab that places in 3-D, and a tool.
class _Deep extends EditorModule {
  @override
  String get id => 'deep';
  @override
  String get name => 'Deep';
  @override
  List<PrefabDefinition> get prefabs => [
    PrefabDefinition(
      id: 'deep.thing',
      name: 'Deep thing',
      category: 'Deep',
      icon: Icons.view_in_ar,
      color: Colors.teal,
      dimensions: Dimensions.threeD,
      build: (_, _) => [TransformComponent()],
    ),
  ];
  @override
  List<LevelToolHandler> createTools(DesignerToolContext context) => [_DeepTool()];
}

class _DeepTool extends LevelToolHandler {
  @override
  String get id => 'deep.tool';
  @override
  String get label => 'Deep';
  @override
  IconData get icon => Icons.star;
  @override
  Dimensions get dimensions => Dimensions.threeD;
}

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

EditorScope _scope({SceneMode mode = SceneMode.threeD, List<EditorModule> modules = const []}) {
  final world = World()..initialize();
  Graphics3D.registerSchemas(world.context);
  final scope = testScope(world: world, modules: modules);
  scope.sceneState.openScene(EditorScene(name: 'level', mode: mode));
  return scope;
}

LevelDesignerSession _open(
  EditorScope scope, {
  EditorView? view,
  ModifierKeys Function()? modifiers,
}) {
  final session = LevelDesignerSession(
    scope: scope,
    uniqueName: scope.entities.uniqueName.call,
    onDuplicate: () {},
    onDelete: () {},
    onArray: (_, _) {},
    readModifiers: modifiers ?? () => const ModifierKeys(),
    camera: view == null ? null : () => view,
  );
  addTearDown(session.dispose);
  return session;
}

/// A view from 10 m above the origin, looking down.
OrbitFlyEditorView _above() {
  final view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(200, 200)))
    ..viewportSize = const Size(200, 200)
    ..pivot.setValues(0, 0, 0)
    ..distance = 10
    ..yaw = 0
    ..pitch = -math.pi / 2;
  return view..sync();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the switch lists the kits for the scene\'s mode', () {
    test('a kit designs the modes its prefabs place in', () {
      expect(_Flat().designerModes, {SceneMode.twoD});
      expect(_Deep().designerModes, {SceneMode.threeD});
    });

    test('2-D kits in a 2-D scene, 3-D kits in a 3-D one', () {
      final flat = _scope(mode: SceneMode.twoD, modules: [_Flat(), _Deep()]);
      expect(flat.designers.map((m) => m.id), ['flat']);
      final deep = _scope(modules: [_Flat(), _Deep()]);
      expect(deep.designers.map((m) => m.id), ['deep']);
    });

    test('a kit of the other mode cannot be chosen, nor restored with a scene', () {
      final scope = _scope(modules: [_Flat(), _Deep()]);
      scope.selectDesigner('flat');
      expect(scope.activeDesigner.value, isNull);
      scope.selectDesigner('deep');
      expect(scope.activeDesigner.value, 'deep');

      final session = _open(scope);
      session.restoreEditorData(const {'designer': 'flat'});
      expect(scope.activeDesigner.value, isNull, reason: 'Default instead');
    });
  });

  group('the default kit in 3-D', () {
    test('Select and Place, the 3-D ones; no 2-D tool', () {
      final session = _open(_scope());
      final ids = session.tools.all.map((t) => t.id).toList();
      expect(ids, containsAll([BuiltInTools.select, BuiltInTools.place]));
      expect(ids, isNot(contains(BuiltInTools.draw)));
      expect(ids, isNot(contains(BuiltInTools.paint)));
      expect(session.tools.byId(BuiltInTools.select), isA<Select3DTool>());
      expect(session.tools.byId(BuiltInTools.draw), isNull);
      expect(session.controller.activeTool, isA<Select3DTool>());
    });

    test('in 2-D the same ids are the 2-D tools', () {
      final session = _open(_scope(mode: SceneMode.twoD));
      expect(session.tools.byId(BuiltInTools.select), isNot(isA<Select3DTool>()));
      expect(session.tools.byId(BuiltInTools.place), isNull);
      expect(session.tools.byId(BuiltInTools.draw), isNotNull);
    });

    test("a chosen 3-D kit's tools join the default kit's", () {
      final scope = _scope(modules: [_Deep()]);
      final session = _open(scope);
      scope.selectDesigner('deep');
      expect(session.tools.byId('deep.tool'), isNotNull);
      expect(session.tools.byId(BuiltInTools.place), isNotNull);
    });

    test('the basic shapes are its palette; the one in hand is a 3-D one', () {
      final scope = _scope();
      final session = _open(scope);
      expect(scope.prefabs.byId('shape.cube'), isNotNull);
      final active = session.controller.activePrefab;
      expect(active, isNotNull);
      expect(active!.dimensions.allows(SceneMode.threeD), isTrue);
    });

    test('Select declines a press on something: picking and the gizmo are the viewport\'s', () {
      final view = _above();
      final scope = _scope();
      final session = _open(scope, view: view);
      scope.world.createEntityWithComponents([TransformComponent(position: Vector3(0, -0.5, 0)), Cube3D()]);
      expect(
        session.onPointerDown(
          Offset.zero,
          32,
          screen: view.projectToScreen(Vector3(0, -1, 0))!,
          canvasSize: const Size(200, 200),
        ),
        isFalse,
      );
    });

    test('Place stands the prefab on what is under the pointer, one undo step', () {
      final view = _above();
      final scope = _scope();
      final session = _open(scope, view: view);
      session.setTool(BuiltInTools.place);
      session.controller.activePrefabId.value = 'shape.cube';
      final claimed = session.onPointerDown(
        Offset.zero,
        32,
        screen: view.projectToScreen(Vector3(2, 0, 3))!,
        canvasSize: const Size(200, 200),
      );
      session.onPointerUp(Offset.zero, 32);
      expect(claimed, isTrue);
      final cube = scope.world.entities.singleWhere((e) => e.getComponent<Primitive3D>() is Cube3D);
      final p = cube.getComponent<TransformComponent>()!.position;
      expect(p.x, closeTo(2, 1e-6));
      expect(p.y, closeTo(-0.5, 1e-6), reason: 'resting on the ground: up is -Y');
      expect(p.z, closeTo(3, 1e-6));
      expect(scope.sceneState.selectedEntity.value, cube);
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(cube.isAlive, isFalse);
    });

    test('a 2-D framing key is not the designer\'s in 3-D', () {
      final session = _open(_scope());
      expect(session.handleKey(LogicalKeyboardKey.keyF, gridSize: 32), isFalse);
      final flat = _open(_scope(mode: SceneMode.twoD));
      expect(flat.handleKey(LogicalKeyboardKey.keyF, gridSize: 32), isTrue);
    });

    test('the gizmo drags with the designer open', () {
      final view = _above();
      final scope = _scope();
      final session = _open(scope, view: view);
      final entity = scope.world.createEntityWithComponents([TransformComponent()], name: 'box');
      scope.sceneState.selectEntity(entity);
      final commits = <TransformCommand>[];
      final input = ViewportInput(
        world: () => scope.world,
        sceneState: scope.sceneState,
        camera: () => view,
        designer: () => session,
        gridSize: () => 32,
        isActive: () => true,
        isAuthoring: () => true,
        hitTester3D: _OnHandle(GizmoHandle.translateX),
        commitTransform: commits.add,
      )..updateCanvasSize(const Size(200, 200));
      final from = view.projectToScreen(Vector3.zero())!;
      final to = view.projectToScreen(Vector3(2, 0, 0))!;
      input
        ..onPointerDown(PointerDownEvent(position: from))
        ..onPointerMove(PointerMoveEvent(position: to))
        ..onPointerUp(PointerUpEvent(position: to));
      expect(entity.getComponent<TransformComponent>()!.position.x, closeTo(2, 1e-3));
      expect(commits, hasLength(1));
    });
  });

  group('the shapes', () {
    test('every shape, once, offered in 3-D scenes', () {
      final prefabs = ShapePrefabs.all;
      expect(prefabs, hasLength(11));
      expect({for (final p in prefabs) p.id}, hasLength(11));
      for (final prefab in prefabs) {
        expect(prefab.dimensions, Dimensions.threeD);
        final parts = prefab.buildAt!(SurfacePoint(Vector3.zero(), Vector3(0, -1, 0)));
        expect(parts.whereType<Primitive3D>(), hasLength(1), reason: prefab.name);
        expect(parts.whereType<SolidShapeSource>(), hasLength(1), reason: 'a Solid variant can take it');
      }
    });

    test('placed resting on the surface clicked', () {
      final cube = ShapePrefabs.all.firstWhere((p) => p.id == 'shape.cube');
      Vector3 at(Vector3 point, Vector3 normal) =>
          cube.buildAt!(SurfacePoint(point, normal)).whereType<TransformComponent>().single.position;
      final onGround = at(Vector3(2, 0, 3), Vector3(0, -1, 0));
      expect([onGround.x, onGround.y, onGround.z], [2, -0.5, 3], reason: 'up is -Y');
      final onWall = at(Vector3(5, -1, 0), Vector3(1, 0, 0));
      expect([onWall.x, onWall.y, onWall.z], [5.5, -1, 0]);
      final plane = ShapePrefabs.all.firstWhere((p) => p.id == 'shape.plane');
      final flat = plane.buildAt!(SurfacePoint(Vector3.zero(), Vector3(0, -1, 0)))
          .whereType<TransformComponent>()
          .single
          .position;
      expect(flat.y, closeTo(-0.001, 1e-9), reason: 'a hair above, not fighting the surface');
    });

    test('picks a shape by its triangles: a ray through a ring\'s hole misses it', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final ring = world.createEntityWithComponents([TransformComponent(), Torus3D(radius: 1, tubeRadius: 0.2)]);
      final other = world.createEntityWithComponents([TransformComponent()]);
      final test = ShapeRayTest();
      Ray3 down(double x) => Ray3.originDirection(Vector3(x, -5, 0), Vector3(0, 1, 0));
      expect(test.distanceTo(ring, down(0)), double.infinity);
      expect(test.distanceTo(ring, down(1)), closeTo(4.8, 0.02));
      expect(test.distanceTo(other, down(0)), isNull, reason: 'not a shape: the box decides');
    });

    test('the editor picks shapes by their triangles and drags a polygon\'s corners', () {
      final scope = _scope();
      expect(scope.pickTests.whereType<ShapeRayTest>(), hasLength(1));
      expect(scope.viewportHandles.whereType<PolygonHandles>(), hasLength(1));
    });

    group('a polygon\'s corners', () {
      late EditorScope scope;
      late Entity entity;
      late Polygon3D polygon;

      setUp(() {
        scope = _scope();
        polygon = Polygon3D(points: const [Offset(-1, -1), Offset(1, -1), Offset(1, 1), Offset(-1, 1)]);
        entity = scope.world.createEntityWithComponents([TransformComponent(), polygon], name: 'floor');
        scope.sceneState.selectEntity(entity);
      });

      List<ViewportHandle> handles() => PolygonHandles().handlesOf(entity, scope);

      test('a corner on each point of its top face, a + between each two', () {
        final all = handles();
        expect(all.where((h) => h.style == ViewportHandleStyle.point), hasLength(4));
        expect(all.where((h) => h.style == ViewportHandleStyle.add), hasLength(4));
        final first = all.first.position;
        expect([first.x, first.y, first.z], [-1, -0.5, -1], reason: 'on top: up is -Y');
        expect(PolygonHandles().handlesOf(scope.world.createEntityWithComponents([TransformComponent(), Cube3D()]), scope), isEmpty);
      });

      test('dragging one in the viewport moves that corner, one undo step', () {
        final view = _above();
        final drags = HandleDragSession(scope);
        final input = ViewportInput(
          world: () => scope.world,
          sceneState: scope.sceneState,
          camera: () => view,
          designer: () => null,
          gridSize: () => 0.5,
          isActive: () => true,
          isAuthoring: () => true,
          handles: handles,
          handleDrags: drags,
        )..updateCanvasSize(const Size(200, 200));
        final from = view.projectToScreen(Vector3(1, -0.5, 1))!;
        final to = view.projectToScreen(Vector3(2, -0.5, 3))!;
        input
          ..onPointerDown(PointerDownEvent(position: from))
          ..onPointerMove(PointerMoveEvent(position: to))
          ..onPointerUp(PointerUpEvent(position: to));
        expect(polygon.points[2].dx, closeTo(2, 1e-3));
        expect(polygon.points[2].dy, closeTo(3, 1e-3));
        expect(scope.history.undoEntries, hasLength(1));
        scope.history.undo();
        expect(polygon.points[2], const Offset(1, 1));
      });

      test('a + adds a corner there; Alt-click removes one, three always stay', () {
        handles().firstWhere((h) => h.style == ViewportHandleStyle.add).onClick!(const HandleClick(alt: false));
        expect(polygon.points, hasLength(5));
        expect(polygon.points[1], const Offset(0, -1));
        for (var i = 0; i < 4; i++) {
          handles().first.onClick!(const HandleClick(alt: true));
        }
        expect(polygon.points, hasLength(3));
      });

      test('dragging a + places the new corner where it is dropped, snapped', () {
        final add = handles().firstWhere((h) => h.style == ViewportHandleStyle.add);
        final drag = HandleDrag(
          ray: Ray3.originDirection(Vector3(0.1, -10, -2.2), Vector3(0, 1, 0)),
          start: add.position,
          snap: true,
          grid: 0.5,
        );
        add.onDrag(drag);
        add.onDrag(drag);
        expect(polygon.points, hasLength(5), reason: 'added once, then moved');
        expect(polygon.points[1], const Offset(0, -2));
      });
    });
  });

  group('the side panel', () {
    testWidgets('in 3-D: the palette of shapes, no layers or tileset', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scope = _scope();
      final session = _open(scope);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorScopeProvider(
              scope: scope,
              child: LevelDesignerWorkspace(
                session: session,
                gridSize: 32,
                onGridSizeChanged: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('PREFABS'), findsOneWidget);
      expect(find.text('Cube'), findsOneWidget);
      expect(find.text('LAYERS'), findsNothing);
      expect(find.text('TILESET'), findsNothing);
      expect(find.byType(AlignBar), findsNothing);
    });

    testWidgets('a short window with every section open scrolls, and nothing overflows', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 420)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scope = _scope();
      final session = _open(scope);
      for (final id in const ['prefabs', 'view3d', 'materials3d', 'groups3d', 'array3d']) {
        session.controller.setSectionOpen(id, open: true);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorScopeProvider(
              scope: scope,
              child: LevelDesignerWorkspace(
                session: session,
                gridSize: 32,
                onGridSizeChanged: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Make 3 copies'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('Make 3 copies'), findsOneWidget, reason: 'the last section, reached by scrolling');
      expect(tester.takeException(), isNull);
    });
  });

  group('the working plane', () {
    test('Page Up and Down move it a step (ten with Shift); backslash turns it', () {
      final scope = _scope();
      var shift = false;
      final session = _open(scope, modifiers: () => ModifierKeys(shift: shift));
      final state = scope.designer3D;
      expect(session.handleKey(LogicalKeyboardKey.pageUp, gridSize: 32), isTrue);
      expect(state.plane.offset, closeTo(-0.25, 1e-9), reason: 'a step up: -Y');
      shift = true;
      session.handleKey(LogicalKeyboardKey.pageDown, gridSize: 32);
      expect(state.plane.offset, closeTo(2.25, 1e-9), reason: 'ten steps down');
      shift = false;
      session.handleKey(LogicalKeyboardKey.backslash, gridSize: 32);
      expect(state.plane.axis, WorkingPlaneAxis.front);
    });

    test('the keys are not the 2-D designer\'s', () {
      final session = _open(_scope(mode: SceneMode.twoD));
      expect(session.handleKey(LogicalKeyboardKey.pageUp, gridSize: 32), isFalse);
    });

    test('Place puts a thing on the raised plane where nothing is below', () {
      final view = _above();
      final scope = _scope();
      final session = _open(scope, view: view);
      scope.designer3D.raise(2);
      session.setTool(BuiltInTools.place);
      session.controller.activePrefabId.value = 'shape.cube';
      session.onPointerDown(
        Offset.zero,
        32,
        screen: view.projectToScreen(Vector3(1.1, -2, 0.9))!,
        canvasSize: const Size(200, 200),
      );
      // Made on release: a press may be dragged to aim it first.
      session.onPointerUp(Offset.zero, 32);
      final cube = scope.world.entities.singleWhere((e) => e.getComponent<Primitive3D>() is Cube3D);
      final p = cube.getComponent<TransformComponent>()!.position;
      expect(p.y, closeTo(-2.5, 1e-6), reason: 'standing on the plane 2 m up');
      expect([p.x, p.z], [closeTo(1, 1e-6), closeTo(1, 1e-6)], reason: 'on the move step');
    });

    test('following the selection, the plane is at its base', () {
      final scope = _scope();
      final session = _open(scope);
      final box = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, -3, 0)),
      ]);
      scope.sceneState.selectEntity(box);
      expect(session.workingPlane.offset, 0, reason: 'not following yet');
      scope.designer3D.followSelection.value = true;
      expect(session.workingPlane.offset, closeTo(-2.75, 1e-9));
    });

    test('a handle dragged in space snaps in the move step', () {
      final view = _above();
      final scope = _scope();
      final polygon = Polygon3D(points: const [Offset(-1, -1), Offset(1, -1), Offset(1, 1), Offset(-1, 1)]);
      final entity = scope.world.createEntityWithComponents([TransformComponent(), polygon]);
      scope.sceneState.selectEntity(entity);
      final input = ViewportInput(
        world: () => scope.world,
        sceneState: scope.sceneState,
        camera: () => view,
        designer: () => null,
        gridSize: () => 32,
        isActive: () => true,
        isAuthoring: () => true,
        handles: () => PolygonHandles().handlesOf(entity, scope),
        handleDrags: HandleDragSession(scope),
      )..updateCanvasSize(const Size(200, 200));
      final from = view.projectToScreen(Vector3(1, -0.5, 1))!;
      final to = view.projectToScreen(Vector3(2.1, -0.5, 2.9))!;
      input
        ..onPointerDown(PointerDownEvent(position: from))
        ..onPointerMove(PointerMoveEvent(position: to))
        ..onPointerUp(PointerUpEvent(position: to));
      expect(polygon.points[2].dx, closeTo(2, 1e-6), reason: '0.25 m steps, not 32 px');
      expect(polygon.points[2].dy, closeTo(3, 1e-6));
    });

    test('the grid thins out to what can be seen apart', () {
      final view = _above()
        ..distance = 2
        ..sync();
      expect(gridSpacing(view, Vector3.zero(), 0.25), 0.25, reason: 'close: the step');
      view
        ..distance = 10
        ..sync();
      expect(gridSpacing(view, Vector3.zero(), 0.25), 1, reason: 'then metres');
      view
        ..distance = 2000
        ..sync();
      expect(gridSpacing(view, Vector3.zero(), 0.25), greaterThanOrEqualTo(10));
    });

    testWidgets('the status bar: the step in metres and the plane, no pixels', (tester) async {
      final scope = _scope();
      final session = _open(scope);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: DesignerStatusBar.height,
              child: DesignerStatusBar(
                session: session,
                gridSize: 32,
                onGridSizeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(MoveStep3DField), findsOneWidget);
      expect(find.text('0.25 m'), findsOneWidget);
      expect(find.byType(WorkingPlaneControl), findsOneWidget);
      expect(find.text('Ground 0.00 m'), findsOneWidget);
      expect(find.text('32px'), findsNothing);
      expect(find.text('Smart'), findsNothing);
    });
  });
}
