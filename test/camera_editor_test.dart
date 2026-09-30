// The editor and the camera brain share one output camera. While authoring
// the editor owns it; the brain keeps thinking, so the author can see what
// the game would show.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('with a running engine', () {
    late Engine engine;
    late JustGameEditorPlugin plugin;

    Camera output() => engine.cameraSystem.mainCamera;
    CameraBrain brain() => engine.cameraSystem.brain;

    setUp(() async {
      Engine.resetInstance();
      engine = Engine();
      await engine.initialize();
      registerCameraSystems(engine.world, engine.cameraSystem);
      brain().defaultBlend = CameraBlend.cut;

      // Closed to begin with, so the hand-over can be watched from the start.
      plugin = JustGameEditorPlugin(engine: engine, startVisible: false);
      await plugin.onInitialize();
    });

    tearDown(() {
      plugin.dispose();
      Engine.resetInstance();
    });

    Entity shot(String name, Offset at, {int priority = 10, double zoom = 1}) =>
        engine.world.createEntityWithComponents([
          TransformComponent(position: Vector3(at.dx, at.dy, 0)),
          VirtualCameraComponent(priority: priority, zoom: zoom),
        ], name: name);

    test('authoring owns the view; Play hands it to the brain; Stop returns '
        'exactly where the author was', () {
      shot('Main', const Offset(900, 300), zoom: 2);
      expect(brain().driveOutput, isTrue, reason: 'editor closed: a game');

      plugin.setVisible(true);
      expect(brain().driveOutput, isFalse);
      output()
        ..setPosition(const Offset(-40, 25))
        ..setZoom(0.5);

      // The ECS frame still runs while authoring, and must not move the view.
      engine.world.update(1 / 60);
      expect(output().position, const Offset(-40, 25));

      plugin.playController.play();
      expect(brain().driveOutput, isTrue);
      engine.world.update(1 / 60);
      expect(output().position, const Offset(900, 300));
      expect(output().zoom, 2);

      plugin.playController.stop();
      expect(brain().driveOutput, isFalse);
      expect(output().position, const Offset(-40, 25));
      expect(output().zoom, 0.5);
    });

    test('closing the editor gives the camera back to the game', () {
      plugin.setVisible(true);
      plugin.setVisible(false);
      expect(brain().driveOutput, isTrue);
    });

    test('the brain keeps thinking while the game is frozen', () {
      shot('Main', const Offset(640, 0));
      plugin.setVisible(true);
      output().setPosition(const Offset(5, 5));
      plugin.onUpdate(1 / 60);
      expect(brain().liveCamera?.name, 'Main');
      expect(brain().liveState?.position, const Offset(640, 0));
      expect(output().position, const Offset(5, 5), reason: 'only thinking');
    });

    test('the game preview is drawn without disturbing the editor view', () {
      shot('Main', const Offset(2000, 1000), zoom: 3);
      plugin.setVisible(true);
      output()
        ..setPosition(const Offset(12, 34))
        ..setZoom(0.75);
      plugin.onUpdate(1 / 60);

      final canvas = ui.Canvas(ui.PictureRecorder());
      plugin.onRender(canvas, const Size(1280, 720));
      expect(output().position, const Offset(12, 34));
      expect(output().zoom, 0.75);

      plugin.showGamePreview.value = false;
      plugin.onRender(canvas, const Size(1280, 720));
      expect(output().position, const Offset(12, 34));
    });

    test(
      'the preview is a panel: a header, then the game view in its shape',
      () {
        const canvas = Size(1600, 900);
        final panel = JustGameEditorPlugin.gamePreviewRect(canvas);
        final view = JustGameEditorPlugin.gamePreviewViewRect(panel);
        expect(view.width / view.height, closeTo(1600 / 900, 1e-9));
        expect(panel.width, lessThan(1600 / 2));
        // Header above, the same padding all round — like the toolbar's frame.
        expect(
          view.top - panel.top,
          JustGameEditorPlugin.gamePreviewHeaderHeight + 5,
        );
        expect(view.left - panel.left, 5);
        expect(panel.right - view.right, 5);
        expect(panel.bottom - view.bottom, 5);

        // It hangs wherever the chrome says the play controls end.
        final moved = JustGameEditorPlugin.gamePreviewRect(
          canvas,
          origin: const Offset(74, 70),
        );
        expect(moved.topLeft, const Offset(74, 70));
        expect(moved.size, panel.size);
      },
    );

    test('Solo looks through one camera, and toggles off again', () {
      final low = shot('Low', Offset.zero, priority: 1);
      shot('High', const Offset(100, 0), priority: 99);
      plugin.setVisible(true);
      final scope = plugin.scope;
      final solo = scope.sceneTreeActions.firstWhere(
        (a) => a.id == BuiltInCameraContributions.soloActionId,
      );
      expect(solo.isEnabled!(low, scope), isTrue);

      solo.run(low, scope);
      plugin.onUpdate(1 / 60);
      expect(brain().liveCamera?.name, 'Low');

      solo.run(low, scope);
      plugin.onUpdate(1 / 60);
      expect(brain().liveCamera?.name, 'High');
    });

    test('Solo is for cameras only', () {
      final crate = engine.world.createEntityWithComponents([
        TransformComponent(),
      ]);
      final solo = plugin.scope.sceneTreeActions.firstWhere(
        (a) => a.id == BuiltInCameraContributions.soloActionId,
      );
      expect(solo.isEnabled!(crate, plugin.scope), isFalse);
    });
  });

  group('in the Level Designer', () {
    late World world;
    late LevelDesignerSession session;

    setUp(() {
      world = World()..initialize();
      session = LevelDesignerSession(
        scope: testScope(world: world),
        uniqueName: (p) => p,
        onDuplicate: () {},
        onDelete: () {},
        onArray: (_, _) {},
        readModifiers: () => const ModifierKeys(),
      );
      addTearDown(session.dispose);
      addTearDown(world.dispose);
    });

    test('the camera overlay and the track tool are built in', () {
      expect(session.overlays.byId(CameraRigOverlay.overlayId), isNotNull);
      expect(session.tools.byId(BuiltInTools.dolly), isNotNull);
    });

    test('every camera part draws, selected or not, with no brain at all', () {
      world.createEntityWithComponents([
        TransformComponent(),
        CameraBoundsComponent(width: 2000, height: 1000),
      ], name: 'Level');
      final main = world.createEntityWithComponents([
        TransformComponent(),
        VirtualCameraComponent(follow: const EntityTarget.tag('player')),
        CameraFramingComponent(),
        CameraConfinerComponent(boundsName: 'Level'),
      ], name: 'Main');
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(500, 0, 0)),
        VirtualCameraComponent(enabled: false, priority: 20),
        CameraTriggerComponent(),
      ], name: 'Zone');
      world.createEntityWithComponents([
        TransformComponent(),
        VirtualCameraComponent(),
        CameraDollyComponent(
          waypoints: const [Offset(0, 0), Offset(300, 0), Offset(300, 200)],
          closed: true,
        ),
      ], name: 'Dolly');
      final party = world.createEntityWithComponents([
        TransformComponent(),
        CameraTargetGroupComponent(),
      ], name: 'Party');

      final canvas = ui.Canvas(ui.PictureRecorder());
      void paint() =>
          session.paint(canvas, const Size(1280, 720), session.camera);

      paint();
      for (final entity in [main, party]) {
        session.sceneState.selectEntity(entity);
        paint();
      }
      session.controller.toolId.value = BuiltInTools.dolly;
      session.sceneState.selectEntity(world.findEntityByName('Dolly')!);
      paint();
    });

    test('a camera frame is the view at that lens', () {
      expect(
        CameraRigPainter.frameOf(
          const CameraState(position: Offset(100, 50), zoom: 2),
          const Size(800, 600),
        ),
        Rect.fromCenter(center: const Offset(100, 50), width: 400, height: 300),
      );
    });

    test('the track tool edits the selected dolly camera', () {
      final dolly = world.createEntityWithComponents([
        TransformComponent(),
        VirtualCameraComponent(),
        CameraDollyComponent(waypoints: const [Offset(0, 0), Offset(100, 0)]),
      ], name: 'Dolly');
      session.sceneState.selectEntity(dolly);
      session.controller.toolId.value = BuiltInTools.dolly;

      // A click away from the track appends a point; one undo takes it back.
      session
        ..onPointerDown(const Offset(100, 200), 32)
        ..onPointerUp(const Offset(100, 200), 32);
      final track = dolly.getComponent<CameraDollyComponent>()!;
      expect(track.waypoints, hasLength(3));
      session.history.undo();
      expect(track.waypoints, hasLength(2));
    });
  });

  test('the camera prefabs are in a Camera group of their own', () {
    final scope = testScope();
    final ids = {
      for (final p in scope.prefabs.byCategory['Camera'] ?? const []) p.id,
    };
    expect(ids, {
      BuiltInPrefabs.cameraId,
      BuiltInPrefabs.cameraZoneId,
      BuiltInPrefabs.cameraBoundsId,
      BuiltInPrefabs.targetGroupId,
      BuiltInPrefabs.dollyCameraId,
    });
    expect(
      scope.prefabCategoryOrder('Camera'),
      greaterThan(scope.prefabCategoryOrder('Scene')),
    );

    final zone = scope.prefabs
        .byId(BuiltInPrefabs.cameraZoneId)!
        .build(const Offset(10, 20), const Size(300, 200));
    expect(
      zone.whereType<VirtualCameraComponent>().single.enabled,
      isFalse,
      reason: 'the trigger turns it on',
    );
    final trigger = zone.whereType<CameraTriggerComponent>().single;
    expect((trigger.width, trigger.height), (300, 200));
    expect(
      trigger.target.isNone,
      isTrue,
      reason: 'the author names the target',
    );
  });

  testWidgets('an entity reference is picked from the scene', (tester) async {
    final scope = testScope();
    Object? written;
    final field = CameraDefinitions.trigger.fields.firstWhere(
      (f) => f.name == 'cameraName',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: scope.fieldEditors.build(
            FieldEditorContext(
              field: field,
              hint: const FieldHint(label: 'Camera'),
              value: 'Gone',
              component: CameraTriggerComponent(cameraName: 'Gone'),
              editors: scope.fieldEditors,
              entityNames: () => ['Player', 'Boss'],
              onChanged: (v) => written = v,
            ),
          ),
        ),
      ),
    );
    final row = tester.widget<DropdownEditorRow>(
      find.byType(DropdownEditorRow),
    );
    // A name the scene no longer has is kept, not silently dropped.
    expect(row.options, ['(none)', 'Boss', 'Gone', 'Player']);
    expect(row.value, 'Gone');

    row.onChanged('(none)');
    expect(written, '');
    row.onChanged('Boss');
    expect(written, 'Boss');
  });
}
