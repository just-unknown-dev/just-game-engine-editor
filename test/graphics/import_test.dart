// Importing models in the editor: settings beside the file, cooking and
// telling when a cooked copy is stale, a model expanded into entities with
// its lights and sockets, and the model workspace's own undo.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine_editor/src/graphics/graphics.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_graphics_engine/testing.dart';

/// A box with a sun pointing down, a red point light 2 m up, and a socket.
GlbWriter _lamp() {
  final w = GlbWriter();
  final mesh = w.addMesh([
    {
      'attributes': {
        'POSITION': w.addFloats(
          [0, 0, 0, 1, 0, 0, 1, 1, 0],
          'VEC3',
          withBounds: true,
        ),
      },
      'material': w.addMaterial({'name': 'shade'}),
    },
  ]);
  w.json['extensionsUsed'] = ['KHR_lights_punctual'];
  w.json['extensions'] = {
    'KHR_lights_punctual': {
      'lights': [
        {
          'type': 'point',
          'name': 'bulb',
          'color': [1, 0, 0],
          'intensity': 5,
          'range': 3,
        },
        {'type': 'directional', 'name': 'sun'},
      ],
    },
  };
  final bulb = w.addNode({
    'name': 'bulb_node',
    'translation': [0, 2, 0],
    'extensions': {
      'KHR_lights_punctual': {'light': 0},
    },
  });
  // glTF lights shine down their node's -Z; turned -90° about X, down -Y.
  final s = math.sqrt(0.5);
  final sun = w.addNode({
    'name': 'sun_node',
    'rotation': [-s, 0, 0, s],
    'extensions': {
      'KHR_lights_punctual': {'light': 1},
    },
  });
  final socket = w.addNode({
    'name': 'socket_top',
    'translation': [0, 1, 0],
  });
  final root = w.addNode({
    'name': 'lamp',
    'mesh': mesh,
    'children': [bulb, sun, socket],
  });
  w.setScene([root]);
  return w;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ModelCooking cooking;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_import');
    addTearDown(() => dir.deleteSync(recursive: true));
    cooking = ModelCooking(root: dir.path);
    Directory('${dir.path}/assets/models').createSync(recursive: true);
    File(
      '${dir.path}/assets/models/lamp.glb',
    ).writeAsBytesSync(_lamp().toGlb());
  });

  group('cooking', () {
    const path = 'assets/models/lamp.glb';

    test(
      'a model with neither settings nor a cooked copy is left alone',
      () async {
        expect(cooking.isStale(path), isFalse);
        expect(cooking.settingsOf(path).isDefault, isTrue);
        final (cooked, failed) = await cooking.cookStale([path]);
        expect(cooked, isEmpty);
        expect(failed, isEmpty);
      },
    );

    test(
      'settings saved make it stale; a cook makes it fresh; a change, stale again',
      () async {
        await cooking.saveSettings(path, const ModelImportSettings(scale: 2));
        expect(
          jsonDecode(
            File('${dir.path}/$path.import.json').readAsStringSync(),
          )['scale'],
          2,
        );
        expect(cooking.isStale(path), isTrue);
        final (cooked, _) = await cooking.cookStale(
          cooking.modelsUnder('assets'),
        );
        expect(cooked, [path]);
        expect(cooking.isCooked(path), isTrue);
        expect(cooking.isStale(path), isFalse);
        final back = CookedModel.read(
          File('${dir.path}/$path.jmodel').readAsBytesSync(),
        );
        expect(back.bounds.max.x, closeTo(2, 1e-6), reason: 'scaled by 2');

        await cooking.saveSettings(path, const ModelImportSettings(scale: 3));
        expect(cooking.isStale(path), isTrue, reason: 'other settings');
        await cooking.cook(path);
        expect(cooking.isStale(path), isFalse);
        File('${dir.path}/$path').writeAsBytesSync([
          ...File('${dir.path}/$path').readAsBytesSync(),
          0,
          0,
          0,
          0,
        ]);
        expect(cooking.isStale(path), isTrue, reason: 'the file changed');

        await cooking.uncook(path);
        expect(cooking.isCooked(path), isFalse);
        expect(cooking.hasSettings(path), isTrue, reason: 'settings stay');
      },
    );

    test('the game reads the project file while the editor runs', () async {
      final module = BuiltInGraphicsModule(root: dir.path);
      expect(await module.readProjectFile(path), isNotNull);
      expect(await module.readProjectFile('packages/x/missing.glb'), isNull);
    });
  });

  group('a model made into entities', () {
    test('its lights and sockets become children, placed and turned', () async {
      final data = await loadModelData(_lamp().toGlb(), name: 'lamp');
      final parts = ModelExpansion.partsOf(
        data,
        'assets/models/lamp.glb',
        Vector3(10, 0, 0),
      );
      expect(parts.map((p) => p.name), ['lamp', 'bulb', 'sun', 'socket_top']);
      expect(parts.first.isRoot, isTrue);
      expect(
        parts.first.components.whereType<ModelComponent>().single.model,
        'assets/models/lamp.glb',
      );

      final bulb = parts[1].components;
      final light = bulb.whereType<LightComponent>().single;
      expect(light.kind, LightKind.point);
      expect(light.range, 3);
      expect(light.color, const Color(0xFFFF0000));
      final p = bulb.whereType<TransformComponent>().single.position;
      expect([p.x, p.y, p.z], [10, -2, 0], reason: 'up is -Y in the engine');

      // The sun points down: its forward (+Z) is the engine's +Y.
      final q = Quaternion.identity();
      parts[2].components.whereType<TransformComponent>().single.rotationInto(
        q,
      );
      final f = Vector3(0, 0, 1);
      q.rotate(f);
      expect(f.y, closeTo(1, 1e-6));

      expect(
        parts[3].components.whereType<SocketComponent>().single.node,
        'socket_top',
      );
    });

    test('placed, they are one undo step, the parts under the model', () async {
      final world = World()..initialize();
      Graphics3D.registerSchemas(world.context);
      final scope = EditorScope(world: world, modules: const []);
      addTearDown(scope.dispose);
      scope.sceneState.openScene(
        EditorScene(name: 'deep', mode: SceneMode.threeD),
      );
      final data = await loadModelData(_lamp().toGlb(), name: 'lamp');
      final root = ModelExpansion.place(
        scope,
        ModelExpansion.partsOf(data, 'lamp.glb', Vector3.zero()),
      );
      expect(scope.sceneState.selectedEntity.value, root);
      final children = scope.world.entities.where(
        (e) => e.getComponent<ParentComponent>()?.parentId == root.id,
      );
      expect(children, hasLength(3));
      scope.history.undo();
      expect(scope.world.entities.where((e) => e.isAlive), isEmpty);
      scope.history.redo();
      expect(
        scope.world.entities.where((e) => e.hasComponent<LightComponent>()),
        hasLength(2),
      );
    });
  });

  group('the model workspace', () {
    test('colours read and write as sRGB hex', () {
      final linear = ModelWorkspaceState.linearOfHex('#FF8000')!;
      expect(linear.$1, closeTo(1, 1e-9));
      expect(linear.$2, closeTo(0.2158, 1e-3));
      expect(linear.$4, 1);
      expect(ModelWorkspaceState.srgbHexOf(linear), '#FF8000FF');
      expect(ModelWorkspaceState.linearOfHex('nope'), isNull);
    });

    testWidgets('edits undo and redo, and Save writes the settings and cooks', (
      tester,
    ) async {
      const path = 'assets/models/lamp.glb';
      final scope = EditorScope(
        world: World()..initialize(),
        modules: const [],
      );
      addTearDown(scope.dispose);
      final cooked = <String>[];
      final key = GlobalKey<ModelWorkspaceState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelWorkspace(
              key: key,
              path: path,
              cooking: cooking,
              thumbnails: ModelThumbnails(root: dir.path),
              workspace: WorkspaceContext(
                scope: scope,
                onClose: () {},
                path: path,
              ),
              onCooked: cooked.add,
              loadOnStart: false,
            ),
          ),
        ),
      );
      final state = key.currentState!;
      await tester.runAsync(state.load);
      await tester.pump();
      expect(state.loaded, isTrue);
      expect(find.text('shade'), findsOneWidget, reason: 'its material listed');

      state.edit(state.settings.copyWith(scale: 0.5));
      state.edit(
        state.settings.copyWith(
          materials: {'shade': const MaterialOverride(roughness: 0.1)},
        ),
      );
      expect(state.settings.materials['shade']!.roughness, 0.1);
      state.undo();
      expect(state.settings.materials, isEmpty);
      expect(state.settings.scale, 0.5);
      state.redo();
      expect(state.settings.materials['shade']!.roughness, 0.1);
      expect(state.dirty, isTrue);

      await tester.runAsync(state.save);
      expect(cooked, [path]);
      expect(cooking.settingsOf(path).scale, 0.5);
      expect(cooking.isStale(path), isFalse);
      expect(state.dirty, isFalse);
    });
  });
}
