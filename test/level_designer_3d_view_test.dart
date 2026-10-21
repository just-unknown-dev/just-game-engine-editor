// Selecting and seeing in the 3-D designer: a marquee from empty space,
// everything like the selection, bookmarks that keep the whole view,
// orthographic and back, the VIEW section and the view cube, hiding a
// group's children with it — and the editor's aids reaching the 3-D
// renderer while authoring, and only then.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/panels/view_3d_panel.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/panels/view_cube.dart';

EditorScope _scope({SceneMode mode = SceneMode.threeD}) {
  final world = World()..initialize();
  Graphics3D.registerSchemas(world.context);
  final scope = testScope(world: world);
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

/// A view from 20 m above the origin, looking down.
OrbitFlyEditorView _above() {
  final view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(200, 200)))
    ..viewportSize = const Size(200, 200)
    ..pivot.setValues(0, 0, 0)
    ..distance = 20
    ..yaw = 0
    ..pitch = -math.pi / 2;
  return view..sync();
}

Entity _cube(EditorScope scope, String name, double x, double z) =>
    scope.world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, -0.5, z)),
      Cube3D(),
    ], name: name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the marquee', () {
    late EditorScope scope;
    late OrbitFlyEditorView view;
    late LevelDesignerSession session;
    late Entity a, b, far;

    setUp(() {
      scope = _scope();
      view = _above();
      session = _open(scope, view: view);
      a = _cube(scope, 'a', 2, 2);
      b = _cube(scope, 'b', 4, 2);
      far = _cube(scope, 'far', -6, -6);
    });

    void drag(Vector3 from, Vector3 to) {
      final s = view.projectToScreen(from)!, e = view.projectToScreen(to)!;
      expect(session.onPointerDown(Offset.zero, 32, screen: s, canvasSize: const Size(200, 200)), isTrue);
      session.onPointerMove(Offset.zero, 32, screen: e, canvasSize: const Size(200, 200));
      expect(session.controller.screenRect.value, isNotNull, reason: 'drawn while dragged');
      session.onPointerUp(Offset.zero, 32, screen: e, canvasSize: const Size(200, 200));
    }

    test('selects what it holds, from empty space', () {
      drag(Vector3(1, 0, 1), Vector3(5, 0, 3));
      final state = scope.sceneState;
      expect(state.isInMultiSelection(a.id) || state.selectedEntity.value == a, isTrue);
      expect(state.isInMultiSelection(b.id) || state.selectedEntity.value == b, isTrue);
      expect(state.isInMultiSelection(far.id), isFalse);
      expect(session.controller.screenRect.value, isNull, reason: 'gone when let go');
    });

    test('a press on something is the viewport\'s, not the marquee\'s', () {
      final on = view.projectToScreen(Vector3(2, -0.5, 2))!;
      expect(session.onPointerDown(Offset.zero, 32, screen: on, canvasSize: const Size(200, 200)), isFalse);
    });

    test('a click on empty space clears the selection', () {
      scope.sceneState.selectEntity(a);
      final empty = view.projectToScreen(Vector3(-2, 0, 6))!;
      session
        ..onPointerDown(Offset.zero, 32, screen: empty, canvasSize: const Size(200, 200))
        ..onPointerUp(Offset.zero, 32, screen: empty, canvasSize: const Size(200, 200));
      expect(scope.sceneState.selectedEntity.value, isNull);
    });
  });

  test('Shift+G selects everything like the selection', () {
    final scope = _scope();
    final session = _open(scope, modifiers: () => const ModifierKeys(shift: true));
    final one = _cube(scope, 'Cube_1', 0, 0);
    final two = _cube(scope, 'Cube_2', 3, 0);
    final ball = scope.world.createEntityWithComponents([TransformComponent(), Sphere3D()], name: 'Ball');
    scope.sceneState.selectEntity(one);
    expect(session.handleKey(LogicalKeyboardKey.keyG, gridSize: 32), isTrue);
    final state = scope.sceneState;
    bool picked(Entity e) => state.selectedEntity.value == e || state.isInMultiSelection(e.id);
    expect(picked(one) && picked(two), isTrue);
    expect(picked(ball), isFalse);
  });

  group('the view', () {
    test('a bookmark keeps the whole view, and travels with the scene', () {
      final scope = _scope();
      final view = _above();
      final session = _open(scope, view: view);
      view
        ..yaw = 0.7
        ..pitch = -0.3
        ..distance = 12
        ..orthographic = true;
      view.pivot.setValues(1, -2, 3);
      view.sync();
      session.storeBookmark(1);
      final saved = session.editorData();
      view
        ..yaw = 0
        ..distance = 50
        ..orthographic = false;
      session.recallBookmark(1);
      expect([view.yaw, view.pitch, view.distance], [0.7, -0.3, 12]);
      expect([view.pivot.x, view.pivot.y, view.pivot.z], [1, -2, 3]);
      expect(view.orthographic, isTrue);
      view.distance = 50;
      session.restoreEditorData(saved);
      session.recallBookmark(1);
      expect(view.distance, 12);
    });

    test('orthographic: a flat lens, still in space, the same scale', () {
      final view = _above();
      final before = view.zoom;
      view.orthographic = true;
      expect(view.camera.lens.isOrthographic, isTrue);
      expect(view.camera.isPlanar, isFalse, reason: 'in space, not a 2-D camera');
      expect(view.camera.zoom, closeTo(before, 1e-9), reason: 'no jump');
      final ray = view.screenToRay(const Offset(30, 40));
      expect(ray.direction.y, closeTo(1, 1e-3), reason: 'straight down (the tilt stops a hair short), wherever on screen');
      view.orthographic = false;
      expect(view.camera.lens.isOrthographic, isFalse);
    });

    testWidgets('the VIEW section sets how the scene is drawn', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scope = _scope();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: View3DPanel(scope: scope))));
      for (final mode in ViewMode3D.values) {
        expect(find.text(mode.label), findsOneWidget);
      }
      await tester.tap(find.text('Wire'));
      await tester.pump();
      expect(scope.designer3D.viewMode.value, ViewMode3D.wireframe);
      expect(find.text('Slice above'), findsOneWidget);
    });

    testWidgets('the view cube looks from the side clicked', (tester) async {
      final view = _above()
        ..pitch = -0.4
        ..yaw = 0.3;
      view.sync();
      (double, double)? looked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ViewCube(
                view: view,
                onViewAlong: (yaw, pitch) => looked = (yaw, pitch),
                onToggleOrthographic: () {},
              ),
            ),
          ),
        ),
      );
      final box = tester.getTopLeft(
        find.descendant(of: find.byType(ViewCube), matching: find.byType(CustomPaint)),
      );
      // The top's end (engine -Y) is drawn up the widget by how much the
      // view's own up leans that way.
      const centre = Offset(ViewCube.size / 2, ViewCube.size / 2 - 6);
      final top = centre + Offset(0, view.up.y * 26);
      await tester.tapAt(box + top);
      expect(looked, isNotNull);
      expect(looked!.$2, closeTo(-math.pi / 2, 1e-9), reason: 'from above');
      expect(find.text('Persp'), findsOneWidget);
    });
  });

  test('hiding a group hides what it holds, in the designer too', () {
    final scope = _scope();
    final session = _open(scope);
    final group = scope.world.createEntityWithComponents([TransformComponent()], name: 'group');
    final child = scope.world.createEntityWithComponents([
      TransformComponent(),
      Cube3D(),
      ParentComponent(parentId: group.id),
    ], name: 'child');
    scope.view.setHidden([group.id], hidden: true);
    expect(session.controller.isShownInViewport(child), isFalse);
    expect(session.controller.isPickable(child), isFalse);
  });

  group('the editor\'s aids reach the 3-D renderer', () {
    late Engine engine;
    late Graphics3D graphics;
    late JustGameEditorPlugin plugin;

    setUp(() async {
      graphics = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders), keepEdges: true);
      engine = Engine(config: EngineConfig(graphics3D: graphics));
      await engine.initialize();
      plugin = JustGameEditorPlugin(engine: engine, startVisible: false);
      await plugin.attach(plugin.engine);
      plugin.setVisible(true);
    });
    tearDown(() {
      plugin.dispose();
      engine.dispose();
    });

    test('while authoring a 3-D scene, as set; otherwise none', () {
      plugin.sceneState.openScene(EditorScene(name: 'deep', mode: SceneMode.threeD));
      plugin.scope.designer3D
        ..viewMode.value = ViewMode3D.wireframe
        ..sliceOn.value = true
        ..sliceY.value = -3;
      plugin.update(1 / 60);
      final aids = graphics.sceneRenderer.aids;
      expect(aids, isNotNull);
      expect(aids!.viewMode, RenderViewMode.wireframe);
      expect(aids.sliceY, -3);
      expect(aids.highlighted, isNotNull);

      plugin.scope.designer3D.viewMode.value = ViewMode3D.collision;
      plugin.update(1 / 60);
      expect(graphics.sceneRenderer.aids!.viewMode, RenderViewMode.unlit, reason: 'colliders over an unlit scene');

      plugin.sceneState.openScene(EditorScene(name: 'flat'));
      plugin.update(1 / 60);
      expect(graphics.sceneRenderer.aids, isNull);
    });
  });
}
