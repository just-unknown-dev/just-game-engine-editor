// The New Scene page's choice of 2-D or 3-D, and what each writes.
//
// Both can be picked; 2-D is chosen to start with.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine_editor/src/ui/dialogs/create_scene_overlay.dart';

import 'support/real_io.dart';

void main() {
  late Directory root;
  late SceneStore store;
  setUp(() {
    root = Directory.systemTemp.createTempSync('new_scene_');
    store = SceneStore(
      root: root.path,
      codec: SceneCodec(ComponentDefinitionRegistry.core()),
    );
  });
  tearDown(() => deleteWhenFree(root));

  Map<String, dynamic> read(String name) =>
      jsonDecode(
            readWhenFree(
              () => File('${root.path}/$name.scene.json').readAsStringSync(),
            ),
          )
          as Map<String, dynamic>;

  List<String> typesOf(Map<String, dynamic> scene, String entity) => [
    for (final c
        in ((scene['entities'] as List).cast<Map>().firstWhere(
                  (e) => e['name'] == entity,
                )['components']
                as List)
            .cast<Map>())
      c['type'] as String,
  ];

  Future<void> pumpPage(WidgetTester tester, List<String> created) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreateSceneOverlay(
              store: store,
              onSceneCreated: (name) async => created.add(name),
            ),
          ),
        ),
      );

  Future<void> create(
    WidgetTester tester,
    String name,
    List<String> created,
  ) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.pump();
    await tester.tap(find.text('Create scene'));
    // The files are real writes — each beside its file, flushed and moved
    // over it — and the page says it made the scene once they are done.
    await pumpUntil(
      tester,
      () => created.contains(name),
      what: 'scene "$name" to be made',
    );
    await tester.pump();
  }

  group('the page', () {
    testWidgets('offers 2-D, chosen, and makes a 2-D scene', (tester) async {
      final created = <String>[];
      await pumpPage(tester, created);

      expect(find.text('SCENE TYPE'), findsOneWidget);
      expect(find.text('2D'), findsOneWidget);
      expect(find.text('3D'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      await create(tester, 'level_a', created);
      expect(created, ['level_a']);
      expect(read('level_a')['mode'], '2d');
    });

    testWidgets('3-D can be picked and is made', (tester) async {
      final created = <String>[];
      await pumpPage(tester, created);

      await tester.tap(find.text('3D'));
      await tester.pump();
      await create(tester, 'level_b', created);
      expect(created, ['level_b']);
      expect(read('level_b')['mode'], '3d');
    });
  });

  group('the starter files', () {
    test('a 2-D scene keeps its 2-D starter', () async {
      await store.writeInitialFiles('flat');
      final scene = read('flat');
      expect(scene['mode'], '2d');
      expect(typesOf(scene, 'MainCamera'), contains('CameraConfinerComponent'));
      expect(typesOf(scene, 'LevelBounds'), contains('CameraBoundsComponent'));
    });

    test('a 3-D scene: a perspective camera looking at a spawn point, '
        'and nothing 2-D-only', () async {
      await store.writeInitialFiles('deep', mode: SceneMode.threeD);
      final scene = read('deep');
      expect(scene['mode'], '3d');
      expect((scene['entities'] as List).cast<Map>().map((e) => e['name']), [
        'MainCamera',
        'PlayerSpawn',
      ]);
      expect(typesOf(scene, 'MainCamera'), [
        'TransformComponent',
        'VirtualCameraComponent',
      ]);

      // Load it and look through the camera: the middle of the view is the
      // origin, where the spawn point is.
      final world = World()..initialize();
      addTearDown(world.dispose);
      final entities = SceneLoader.load(world, scene);
      final cam = entities.firstWhere((e) => e.name == 'MainCamera');
      final t = cam.getComponent<TransformComponent>()!;
      final vcam = cam.getComponent<VirtualCameraComponent>()!;
      expect(vcam.projection, CameraProjection.perspective);
      final camera = Camera(
        viewportSize: const Size(100, 100),
        position: Offset(t.position.x, t.position.y),
        z: t.position.z,
        pitch: t.eulerX,
        yaw: t.eulerY,
        lens: vcam.lens,
      );
      final centre = camera.screenToWorld(const Offset(50, 50));
      expect(centre.dx, closeTo(0, 1e-6));
      expect(centre.dy, closeTo(0, 1e-6));
      final spawn = entities.firstWhere((e) => e.name == 'PlayerSpawn');
      expect(spawn.getComponent<SpawnComponent>()!.spawner, 'player');
    });
  });
}
