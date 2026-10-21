// The editor's 3-D graphics module: brought for a game with 3-D graphics
// only, what it registers, models dropped and placed in 3-D scenes only,
// picking by triangles, the inspector's sky presets and light notes, and a
// camera's frustum.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/materials.dart';
import 'package:just_game_engine_editor/src/graphics/graphics.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_graphics_engine/testing.dart';

import '../support/real_io.dart';

EditorScope _scope(List<EditorModule> modules) {
  final world = World()..initialize();
  Graphics3D.registerSchemas(world.context);
  final scope = EditorScope(world: world, modules: modules);
  addTearDown(scope.dispose);
  return scope;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('only for a game with 3-D graphics', () {
    test('the editor brings it to a 3-D game, not to a 2-D one', () {
      final flat = Engine();
      final deep = Engine(config: EngineConfig(graphics3D: Graphics3D()));
      expect(BuiltInGraphicsModule.isFor(flat), isFalse);
      expect(BuiltInGraphicsModule.isFor(deep), isTrue);
      expect(
        JustGameEditorPlugin.builtInsFor(flat),
        isNot(contains(BuiltInGraphicsModule.make)),
      );
      expect(
        JustGameEditorPlugin.builtInsFor(deep),
        contains(BuiltInGraphicsModule.make),
      );
      expect(
        JustGameEditorPlugin.builtInsFor(flat),
        containsAll([BuiltInEditorModule.new, BuiltInMaterialsModule.make]),
        reason: "the editor's tools and materials, whatever the game",
      );
    });

    for (final threeD in [false, true]) {
      test(
        threeD
            ? 'a 3-D game: models in the Assets dock'
            : 'a 2-D game: no models, no 3-D aids',
        () async {
          final engine = threeD
              ? Engine(config: EngineConfig(graphics3D: Graphics3D()))
              : Engine();
          addTearDown(engine.dispose);
          await engine.initialize();
          final plugin = JustGameEditorPlugin(engine: engine);
          addTearDown(plugin.dispose);
          final scope = plugin.scope;
          expect(
            scope.modules.byId(BuiltInGraphicsModule.moduleId),
            threeD ? isA<BuiltInGraphicsModule>() : isNull,
          );
          expect(
            scope.assetKinds.of('assets/models/crate.glb').id,
            threeD ? 'model' : isNot('model'),
          );
          expect(
            scope.viewportOverlays.map((o) => o.id),
            threeD
                ? contains('graphics.lightReach')
                : isNot(contains('graphics.lightReach')),
          );
          expect(
            scope.workspaces.map((w) => w.id),
            threeD
                ? contains(BuiltInGraphicsModule.workspaceId)
                : isNot(contains(BuiltInGraphicsModule.workspaceId)),
          );
        },
        timeout: bootTimeout,
      );
    }
  });

  group('models go in 3-D scenes', () {
    test('a model drops in a 3-D scene; a 2-D one turns it away, saying '
        'where it goes', () {
      final scope = _scope([
        BuiltInGraphicsModule(root: Directory.systemTemp.path),
      ]);
      const model = 'assets/models/crate.glb';
      bool drops(String path, SceneMode mode) =>
          JustGameEditorPlugin.canDropAsset(path, mode: mode, scope: scope);
      String? refusal(String path, SceneMode mode) =>
          JustGameEditorPlugin.dropRefusal(path, mode: mode, scope: scope);
      expect(scope.assetKinds.of(model).dropsIn, Dimensions.threeD);
      expect(drops(model, SceneMode.threeD), isTrue);
      expect(drops(model, SceneMode.twoD), isFalse);
      expect(refusal(model, SceneMode.threeD), isNull);
      expect(
        refusal(model, SceneMode.twoD),
        'Models go in 3D scenes: this one is 2D.',
      );

      // A sprite the other way round, said the same way.
      expect(drops('assets/sprites/hero.png', SceneMode.threeD), isFalse);
      expect(
        refusal('assets/sprites/hero.png', SceneMode.threeD),
        'Sprites and tile maps go in 2D scenes: this one is 3D.',
      );
      expect(refusal('assets/sprites/hero.png', SceneMode.twoD), isNull);

      // A sound drops in either; a cooked copy and a scene drop nowhere,
      // and say nothing.
      for (final mode in SceneMode.values) {
        expect(drops('assets/audio/jump.wav', mode), isTrue);
        expect(refusal('assets/models/crate.glb.jmodel', mode), isNull);
        expect(refusal('assets/scenes/level.scene.json', mode), isNull);
      }
    });

    test('a model dropped in a 2-D scene makes nothing; in a 3-D one, an '
        'entity showing it', () async {
      final engine = Engine(config: EngineConfig(graphics3D: Graphics3D()));
      addTearDown(engine.dispose);
      await engine.initialize();
      final plugin = JustGameEditorPlugin(engine: engine);
      addTearDown(plugin.dispose);
      await plugin.attach(engine);

      plugin.sceneState.openScene(EditorScene(name: 'flat'));
      expect(plugin.dropAsset('assets/models/crate.glb', Offset.zero), isNull);
      expect(
        engine.world.query([ModelComponent]),
        isEmpty,
        reason: 'no 3-D entity in a 2-D scene',
      );

      plugin.sceneState.openScene(
        EditorScene(name: 'deep', mode: SceneMode.threeD),
      );
      final made = plugin.dropAsset('assets/models/crate.glb', Offset.zero)!;
      expect(made.name, 'crate');
      expect(
        made.getComponent<ModelComponent>()!.model,
        'assets/models/crate.glb',
      );
    }, timeout: bootTimeout);

    test('placing a model with its lights and sockets is offered while a '
        '3-D scene is open', () {
      final module = BuiltInGraphicsModule(root: Directory.systemTemp.path);
      final scope = _scope([module]);
      final place = module.assetActions.singleWhere(
        (a) => a.id == BuiltInGraphicsModule.placeId,
      );
      bool offered() =>
          place.appliesTo('assets/models/lamp.glb', isDirectory: false);
      expect(offered(), isFalse, reason: 'no scene open');
      scope.sceneState.openScene(EditorScene(name: 'flat'));
      expect(offered(), isFalse, reason: 'a 2-D scene');
      scope.sceneState.openScene(
        EditorScene(name: 'deep', mode: SceneMode.threeD),
      );
      expect(offered(), isTrue);
    });

    test("a package's models are not cooked: its files are not the "
        "project's", () {
      final module = BuiltInGraphicsModule(root: Directory.systemTemp.path);
      _scope([module]);
      bool offers(String id, String path, {bool isDirectory = false}) => module
          .assetActions
          .singleWhere((a) => a.id == id)
          .appliesTo(path, isDirectory: isDirectory);
      expect(offers('graphics.cook', 'assets/models/crate.glb'), isTrue);
      expect(offers('graphics.cook', 'packages/kit/models/crate.glb'), isFalse);
      expect(
        offers('graphics.cookFolder', 'assets', isDirectory: true),
        isTrue,
      );
      expect(
        offers('graphics.cookFolder', 'packages/kit', isDirectory: true),
        isFalse,
      );
    });
  });

  group('registration', () {
    test('models are a kind of file, lights are marked, aids are drawn', () {
      final module = BuiltInGraphicsModule(root: Directory.systemTemp.path);
      final scope = _scope([module]);
      expect(scope.assetKinds.of('assets/models/Crate.glb').id, 'model');
      expect(scope.assetKinds.of('assets/models/tree.gltf').id, 'model');
      expect(scope.assetKinds.filters.map((k) => k.id), contains('model'));
      expect(scope.markers.map((m) => m.id), contains('light'));
      expect(
        scope.viewportOverlays.map((o) => o.id),
        containsAll(['graphics.lightReach', 'graphics.cameraFrustums']),
      );
      expect(scope.pickTests.whereType<ModelRayTest>(), hasLength(1));
      expect(
        scope.inspectorSections.map((s) => s.id),
        containsAll([
          'graphics.model',
          'graphics.light',
          'graphics.environment',
        ]),
      );
    });

    test(
      "a model opens in its workspace; material files are the editor's own",
      () {
        final module = BuiltInGraphicsModule(root: Directory.systemTemp.path);
        _scope([module]);
        expect(module.assetKinds.map((k) => k.id), ['model', 'cookedModel']);
        final model = module.workspaces.single;
        expect(model.id, BuiltInGraphicsModule.workspaceId);
        expect(
          model.matchOf('assets/models/crate.glb'),
          greaterThan(0),
          reason: 'endings without the dot',
        );
        expect(model.matchOf('assets/materials/stone.material.json'), 0);
        expect(
          module.assetActions.map((a) => a.id),
          isNot(contains('graphics.newMaterial')),
        );
      },
    );

    test('a model dropped is an entity showing it where it landed', () {
      final scope = _scope([
        BuiltInGraphicsModule(root: Directory.systemTemp.path),
      ]);
      Entity? made;
      final drop = AssetDrop(
        scope: scope,
        path: 'assets/models/old_crate.glb',
        at: Vector3(2, 0, -3),
        place: (components, name) => made = scope.world
            .createEntityWithComponents(components, name: name),
      );
      BuiltInGraphicsModule.dropModel(drop);
      expect(made!.name, 'old_crate');
      expect(
        made!.getComponent<ModelComponent>()!.model,
        'assets/models/old_crate.glb',
      );
      final p = made!.getComponent<TransformComponent>()!.position;
      expect([p.x, p.y, p.z], [2, 0, -3]);
    });
  });

  group('picking by triangles', () {
    late ModelData mannequin;

    setUpAll(() async {
      mannequin = await loadModelData(mannequinGlb(), name: 'mannequin');
    });

    test("a model is hit where it is drawn, and missed beside it", () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 0)),
        ModelComponent(model: 'mannequin.glb'),
      ]);
      final test = ModelRayTest(
        (path) => path == 'mannequin.glb' ? mannequin : null,
      );
      // Chest height: up is -Y in the engine.
      final through = Ray3()..setValues(0, -1.2, -5, 0, 0, 1);
      final beside = Ray3()..setValues(1.5, -1.2, -5, 0, 0, 1);
      expect(
        test.distanceTo(entity, through),
        allOf(greaterThan(4.5), lessThan(5)),
      );
      expect(test.distanceTo(entity, beside), double.infinity);

      // Moved, the hit moves with it.
      entity.getComponent<TransformComponent>()!.position.setValues(0, 0, 3);
      expect(
        test.distanceTo(entity, through),
        allOf(greaterThan(7.5), lessThan(8)),
      );

      // Not loaded: the box decides.
      final other = world.createEntityWithComponents([
        TransformComponent(position: Vector3.zero()),
        ModelComponent(model: 'elsewhere.glb'),
      ]);
      expect(test.distanceTo(other, through), isNull);
    });

    test('the model inspector frames what it knows', () {
      expect(
        mannequin.animations.map((a) => a.name),
        containsAll(['walk', 'idle']),
      );
      final box = Aabb3();
      mannequin.bounds.transformInto(gltfToEngine, box);
      expect(box.min.y, lessThan(-1.5), reason: 'standing up, -Y');
    });
  });

  group('inspector sections', () {
    test('a sky preset is one undo step', () {
      final scope = _scope(const []);
      final environment = EnvironmentComponent();
      final entity = scope.world.createEntityWithComponents([environment]);
      GraphicsInspectors.applySky(scope, entity, 'Night');
      expect(environment.zenith, const Color(0xFF05070F));
      expect(environment.exposure, 0.8);
      scope.history.undo();
      expect(environment.zenith, const Color(0xFF8AB4F0));
      expect(environment.exposure, 1.0);
    });

    test('a light says what it does', () {
      expect(
        GraphicsInspectors.lightNote(
          LightComponent(kind: LightKind.directional),
        ),
        contains('shadows'),
      );
      expect(
        GraphicsInspectors.lightNote(LightComponent(range: 4)),
        contains('4.0 m'),
      );
      expect(
        GraphicsInspectors.lightNote(LightComponent()),
        contains('no limit'),
      );
      expect(
        GraphicsInspectors.lightNote(LightComponent(kind: LightKind.spot)),
        contains('cone'),
      );
    });
  });

  test("a camera's frustum opens ahead of it, its top up (-Y)", () {
    const state = CameraState(
      lens: CameraLens.perspective(fieldOfView: math.pi / 2),
    );
    final corners = CameraFrustumOverlay.frustumCorners(
      state,
      depth: 2,
      aspect: 1,
    );
    for (final c in corners) {
      expect(c.z, closeTo(2, 1e-9));
    }
    expect(corners[0].y, closeTo(-2, 1e-9), reason: 'top-left is up');
    expect(corners[0].x, closeTo(-2, 1e-9));
    expect(corners[2].y, closeTo(2, 1e-9));
  });
}
