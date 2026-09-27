// What the Level Designer places goes under the level's map, on a layer: the
// map made for the first thing placed, a layer made for a depth that has
// none, the eraser and the eyedropper, and pictures dropped while designing.

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);

  group('in the designer', () {
    late World world;
    late EditorScope scope;
    late LevelDesignerSession session;

    setUp(() {
      world = World()..initialize();
      scope = testScope(world: world);
      session = LevelDesignerSession(
        scope: scope,
        uniqueName: (p) => p,
        onDuplicate: () {},
        onDelete: () {},
        onArray: (_, _) {},
        readModifiers: () => const ModifierKeys(),
      );
      addTearDown(session.dispose);
      session.controller.snapEnabled.value = false;
    });

    List<Entity> maps() => world.query([LevelMapComponent]).toList();
    LevelMapData data() =>
        maps().single.getComponent<LevelMapComponent>()!.inline!;
    List<Entity> members() => [
      for (final e in world.query([LayerComponent]))
        if (LevelMaps.memberLayer(world, e) != null) e,
    ];

    void drag(Offset from, Offset to) {
      session
        ..onPointerDown(from, 32)
        ..onPointerMove(to, 32)
        ..onPointerUp(to, 32);
    }

    test('the first thing drawn makes the Level Map, and goes under it on '
        'its layer; one undo takes both away', () {
      session
        ..setTool(BuiltInTools.draw)
        ..controller.activePrefabId.value = BuiltInPrefabs.solidId;
      drag(const Offset(0, 0), const Offset(128, 32));
      final map = maps().single;
      expect(map.name, LevelMaps.primaryName);
      final solid = members().single;
      expect(LevelMaps.ownerOf(world, solid), same(map));
      expect(
        solid.getComponent<LayerComponent>()!.mapLayer,
        data().layers.single.id,
      );
      expect(
        DesignerGeometry.worldBounds(solid),
        const Rect.fromLTWH(0, 0, 128, 32),
      );
      expect(solid.hasComponent<PhysicsBodyComponent>(), isTrue);
      expect(
        scope.sceneState.selectedEntity.value,
        same(solid),
        reason: 'what was placed is selected',
      );

      scope.history.undo();
      expect(maps(), isEmpty);
      expect(members(), isEmpty);
      scope.history.redo();
      expect(LevelMaps.ownerOf(world, members().single), same(maps().single));
    });

    test('a depth the map has no layer at gets one, in the same step', () {
      session
        ..setTool(BuiltInTools.draw)
        ..controller.activePrefabId.value = BuiltInPrefabs.rectangleId;
      drag(const Offset(0, 0), const Offset(64, 64));
      expect(data().layers.single.name, 'Ground');

      session.controller.activeLayerId.value = 'background';
      drag(const Offset(100, 0), const Offset(164, 64));
      final back = data().layers.firstWhere(
        (l) => l.sortLayerId == 'background',
      );
      expect(back.name, 'Background');
      expect(
        members().where(
          (e) => e.getComponent<LayerComponent>()!.mapLayer == back.id,
        ),
        hasLength(1),
      );
      expect(
        data().layers.indexOf(back),
        lessThan(data().layers.indexWhere((l) => l.name == 'Ground')),
        reason: 'drawn behind the main layer',
      );

      scope.history.undo();
      expect(data().layers.map((l) => l.name), ['Ground']);
      expect(members(), hasLength(1));
    });

    test('a locked layer is not drawn on, and says so', () {
      session
        ..setTool(BuiltInTools.draw)
        ..controller.activePrefabId.value = BuiltInPrefabs.rectangleId;
      drag(const Offset(0, 0), const Offset(64, 64));
      data().layers.single.locked = true;
      drag(const Offset(100, 0), const Offset(164, 64));
      expect(members(), hasLength(1));
      expect(session.controller.status.value, contains('locked'));
    });

    test('a prefab with no layer of its own still goes on one; a prefab\'s '
        'own depth wins over the one being placed at', () {
      scope.prefabs.register(
        PrefabDefinition(
          id: 'test.far',
          name: 'Far hill',
          category: 'Test',
          icon: Icons.landscape,
          color: Colors.green,
          depth: 'background',
          build: (at, size) => [
            TransformComponent(position: Vector3(at.dx, at.dy, 0)),
          ],
        ),
      );
      session
        ..setTool(BuiltInTools.draw)
        ..controller.activePrefabId.value = 'test.far';
      drag(const Offset(0, 0), const Offset(64, 64));
      final hill = members().single;
      expect(
        LevelMaps.memberLayer(world, hill)!.sortLayerId,
        'background',
        reason: 'placed at main, drawn in the background',
      );
    });

    test('the eraser takes what is on the map, never the map itself', () {
      session
        ..setTool(BuiltInTools.paint)
        ..controller.activePrefabId.value = BuiltInPrefabs.solidId;
      session
        ..onPointerDown(const Offset(16, 16), 32)
        ..onPointerUp(const Offset(16, 16), 32);
      expect(members(), hasLength(1));

      session.controller.paintMode.value = PaintMode.eraser;
      session
        ..onPointerDown(const Offset(16, 16), 32)
        ..onPointerUp(const Offset(16, 16), 32);
      expect(members(), isEmpty);
      expect(maps(), hasLength(1), reason: 'the map stays');
      scope.history.undo();
      expect(members(), hasLength(1));
      expect(LevelMaps.ownerOf(world, members().single), same(maps().single));
    });

    test('a sampled entity draws copies on the layer being placed on', () {
      session
        ..setTool(BuiltInTools.draw)
        ..controller.activePrefabId.value = BuiltInPrefabs.solidId;
      drag(const Offset(0, 0), const Offset(64, 32));
      session
        ..setTool(BuiltInTools.eyedropper)
        ..onPointerDown(const Offset(32, 16), 32)
        ..onPointerUp(const Offset(32, 16), 32);
      expect(session.controller.toolId.value, BuiltInTools.draw);

      drag(const Offset(200, 200), const Offset(296, 232));
      expect(members(), hasLength(2));
      final copy = members().firstWhere(
        (e) => e.getComponent<TransformComponent>()!.position.x > 100,
      );
      expect(LevelMaps.ownerOf(world, copy), same(maps().single));
      expect(DesignerGeometry.worldBounds(copy)!.size, const Size(96, 32));
    });
  });

  group('a picture dropped', () {
    late JustGameEditorPlugin plugin;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      Engine.resetInstance();
      final engine = Engine();
      await engine.initialize();
      plugin = JustGameEditorPlugin(engine: engine);
      await plugin.onInitialize();
      plugin.sceneState.openScene(Scene(name: 'level'), const {});
      plugin.engine.cameraSystem.mainCamera.viewportSize = const Size(800, 600);
    });

    tearDown(() {
      plugin.dispose();
      Engine.resetInstance();
    });

    test('while designing goes under the level\'s map; otherwise it is an '
        'entity of its own', () {
      final world = plugin.engine.world;
      plugin.openLevelDesigner();
      final tree = plugin.dropAsset(
        'assets/sprites/tree.png',
        const Offset(400, 300),
      )!;
      expect(tree.name, 'tree');
      expect(
        tree.getComponent<SpriteComponent>()!.spritePath,
        'assets/sprites/tree.png',
      );
      expect(LevelMaps.ownerOf(world, tree)?.name, LevelMaps.primaryName);
      expect(LevelMaps.memberLayer(world, tree), isNotNull);

      plugin.closeLevelDesigner();
      final rock = plugin.dropAsset(
        'assets/sprites/rock.png',
        const Offset(400, 300),
      )!;
      expect(
        rock.getComponent<SpriteComponent>()!.spritePath,
        'assets/sprites/rock.png',
      );
      expect(LevelMaps.ownerOf(world, rock), isNull);
    });
  });
}
