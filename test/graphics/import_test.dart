// Importing models in the editor: settings beside the file, cooking and
// telling when a cooked copy is stale, a model expanded into entities with
// its lights and sockets, and the model workspace's own undo. Writes are
// whole or not at all, a package's models are read where the package is
// and never written, and a cooked copy that is not one is cooked again.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine_editor/src/graphics/graphics.dart';
import 'package:just_game_engine_editor/src/graphics/graphics_3d/cooked_head.dart';

import '../support/real_io.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_graphics_engine/testing.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show CookedModel;

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
        expect(await cooking.isStale(path), isFalse);
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
        expect(await cooking.isStale(path), isTrue);
        final (cooked, _) = await cooking.cookStale(
          cooking.modelsUnder('assets'),
        );
        expect(cooked, [path]);
        expect(cooking.isCooked(path), isTrue);
        expect(await cooking.isStale(path), isFalse);
        final back = CookedModel.read(
          File('${dir.path}/$path.jmodel').readAsBytesSync(),
        );
        expect(back.bounds.max.x, closeTo(2, 1e-6), reason: 'scaled by 2');

        await cooking.saveSettings(path, const ModelImportSettings(scale: 3));
        expect(await cooking.isStale(path), isTrue, reason: 'other settings');
        await cooking.cook(path);
        expect(await cooking.isStale(path), isFalse);
        File('${dir.path}/$path').writeAsBytesSync([
          ...File('${dir.path}/$path').readAsBytesSync(),
          0,
          0,
          0,
          0,
        ]);
        expect(await cooking.isStale(path), isTrue, reason: 'the file changed');

        await cooking.uncook(path);
        expect(cooking.isCooked(path), isFalse);
        expect(cooking.hasSettings(path), isTrue, reason: 'settings stay');
      },
    );

    test('a .gltf is stale when a file it refers to changes', () async {
      const gltf = 'assets/models/lamp.gltf';
      final (json, bin) = _lamp().toGltf(bufferUri: 'lamp.bin');
      File('${dir.path}/$gltf').writeAsStringSync(json);
      final buffer = File('${dir.path}/assets/models/lamp.bin')
        ..writeAsBytesSync(bin);
      await cooking.saveSettings(gltf, const ModelImportSettings(scale: 2));
      await cooking.cook(gltf);
      expect(await cooking.isStale(gltf), isFalse);

      // The same length, other bytes: only the buffer changed.
      buffer.writeAsBytesSync([for (final b in bin) b ^ 0xFF]);
      expect(await cooking.isStale(gltf), isTrue, reason: 'its buffer changed');
      buffer.writeAsBytesSync(bin);
      expect(
        await cooking.isStale(gltf),
        isFalse,
        reason: 'the bytes it was cooked from',
      );

      buffer.deleteSync();
      expect(await cooking.isStale(gltf), isTrue, reason: 'its buffer is gone');
    });

    test('the game reads the project file while the editor runs', () async {
      final module = BuiltInGraphics3DModule(root: dir.path);
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
      final light = bulb.whereType<Light3DComponent>().single;
      expect(light.kind, Light3DKind.point);
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
      Graphics3D.registerDefinitions(world.context);
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
        scope.world.entities.where((e) => e.hasComponent<Light3DComponent>()),
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
          materials: {'shade': const Material3DOverride(roughness: 0.1)},
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
      expect(await tester.runAsync(() => cooking.isStale(path)), isFalse);
      expect(state.dirty, isFalse);
    });

    Future<ModelWorkspaceState> open(
      WidgetTester tester,
      String path, {
      ModelCooking? using,
    }) async {
      final scope = EditorScope(
        world: World()..initialize(),
        modules: const [],
      );
      addTearDown(scope.dispose);
      final key = GlobalKey<ModelWorkspaceState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelWorkspace(
              key: key,
              path: path,
              cooking: using ?? cooking,
              thumbnails: ModelThumbnails(root: dir.path),
              workspace: WorkspaceContext(
                scope: scope,
                onClose: () {},
                path: path,
              ),
              loadOnStart: false,
            ),
          ),
        ),
      );
      final state = key.currentState!;
      await tester.runAsync(state.load);
      await tester.pump();
      return state;
    }

    testWidgets('a model only looked at is not unsaved; it can still be '
        'cooked', (tester) async {
      const path = 'assets/models/lamp.glb';
      final state = await open(tester, path);
      expect(cooking.hasSettings(path), isFalse);
      expect(state.dirty, isFalse, reason: 'nothing was changed');
      expect(find.byTooltip('Cook with these settings'), findsOneWidget);
      state.edit(state.settings.copyWith(scale: 2));
      expect(state.dirty, isTrue);
      state.undo();
      expect(state.dirty, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a Save the window is closed during still cooks', (
      tester,
    ) async {
      const path = 'assets/models/lamp.glb';
      final state = await open(tester, path);
      state.edit(state.settings.copyWith(scale: 2));
      // The settings are being written — a step of real I/O per pump —
      // when the window goes.
      bool? saved;
      unawaited(state.save().then((ok) => saved = ok));
      await tester.pumpWidget(const SizedBox());
      await pumpUntil(tester, () => saved != null, what: 'the save');
      expect(saved, isTrue);
      expect(cooking.isCooked(path), isTrue, reason: 'not skipped unmounted');
      expect(cooking.settingsOf(path).scale, 2);
    });

    testWidgets("a package's model opens where the package is, read-only", (
      tester,
    ) async {
      final kit = _kit(dir);
      final state = await open(tester, kit);
      expect(state.loaded, isTrue);
      expect(find.text('shade'), findsOneWidget, reason: 'read from the kit');
      expect(state.isWritable, isFalse);
      state.edit(state.settings.copyWith(scale: 2));
      expect(state.dirty, isFalse, reason: 'never saved here');
      expect(find.byTooltip('Save'), findsNothing);
      expect(await tester.runAsync(state.save), isFalse);
      expect(
        Directory('${dir.path}/packages').existsSync(),
        isFalse,
        reason: 'nothing made in the project for it',
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group("a package's models", () {
    test('are read where the package is, never written', () async {
      final kit = _kit(dir);
      final module = BuiltInGraphics3DModule(root: dir.path);
      expect(
        await module.readProjectFile(kit),
        isNotNull,
        reason: 'the game in the editor reads it from the kit',
      );
      expect(cooking.isWritable(kit), isFalse);
      expect(cooking.isWritable('assets/models/lamp.glb'), isTrue);
      await expectLater(
        cooking.saveSettings(kit, const ModelImportSettings(scale: 2)),
        throwsUnsupportedError,
      );
      await expectLater(cooking.cook(kit), throwsUnsupportedError);
      await expectLater(cooking.uncook(kit), throwsUnsupportedError);
      final (cooked, failed) = await cooking.cookStale([kit]);
      expect(cooked, isEmpty);
      expect(failed, isEmpty);
      expect(Directory('${dir.path}/packages').existsSync(), isFalse);
    });
  });

  group('a cook or a save cut short', () {
    const path = 'assets/models/lamp.glb';

    test('leaves the cooked copy and the settings that were there', () async {
      await cooking.saveSettings(path, const ModelImportSettings(scale: 2));
      await cooking.cook(path);
      final jmodel = File('${dir.path}/$path.jmodel');
      final sidecar = File('${dir.path}/$path.import.json');
      final (cookedBefore, settingsBefore) = (
        jmodel.readAsBytesSync(),
        sidecar.readAsStringSync(),
      );
      // Where each is written first can't be: the write fails there.
      Directory('${jmodel.path}.saving').createSync();
      Directory('${sidecar.path}.saving').createSync();
      await expectLater(
        cooking.saveSettings(path, const ModelImportSettings(scale: 5)),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        cooking.cook(path),
        throwsA(isA<FileSystemException>()),
      );
      expect(sidecar.readAsStringSync(), settingsBefore);
      expect(jmodel.readAsBytesSync(), cookedBefore);
    });
  });

  group('a cooked copy that is not one', () {
    const path = 'assets/models/lamp.glb';

    test('is read no further than its first bytes, and is stale', () async {
      await cooking.saveSettings(path, const ModelImportSettings(scale: 2));
      // Not a cooked model: what would be its header's length is any number.
      final stray = File('${dir.path}/$path.jmodel')
        ..writeAsBytesSync([
          ...'NOPE'.codeUnits,
          1, 0, 0, 0, // version
          50, 0, 0, 0, // "header" length
          for (var i = 0; i < 88; i++) 0x20,
        ]);
      expect(await readCookedHead(stray.path), hasLength(12));
      expect(await cooking.isStale(path), isTrue);
    });

    test('one another program holds is stale, not an error', () async {
      await cooking.saveSettings(path, const ModelImportSettings(scale: 2));
      await cooking.cook(path);
      final held = File(
        '${dir.path}/$path.jmodel',
      ).openSync(mode: FileMode.append);
      held.lockSync();
      addTearDown(held.closeSync);
      expect(await cooking.isStale(path), isTrue);
      final (cooked, failed) = await cooking.cookStale([path]);
      expect(cooked, isEmpty);
      expect(failed.keys, [path], reason: 'said, not thrown');
    }, skip: Platform.isWindows ? null : 'locks bind only on Windows');
  });
}

/// A kit's model, `packages/kit/…`, in a package outside the project's own
/// folders — as an Asset Store item or a path dependency is — found through
/// pub's package config.
String _kit(Directory project) {
  final kit = Directory('${project.path}/vendor/kit')
    ..createSync(recursive: true);
  File(
    '${kit.path}/pubspec.yaml',
  ).writeAsStringSync('name: kit\nflutter:\n  assets:\n    - models/\n');
  File('${kit.path}/models/crate.glb')
    ..createSync(recursive: true)
    ..writeAsBytesSync(_lamp().toGlb());
  File('${project.path}/.dart_tool/package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'kit', 'rootUri': '../vendor/kit/', 'packageUri': 'lib/'},
        ],
      }),
    );
  PackageAssetPaths.of(project.path).invalidate();
  return 'packages/kit/models/crate.glb';
}
