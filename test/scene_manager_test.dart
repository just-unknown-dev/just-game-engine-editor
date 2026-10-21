// Scenes are written to a temporary directory per test, so this file no
// longer races other test files for a shared folder on disk.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine_editor/src/core/serialization/scene_manager.dart';

void main() {
  late Directory root;
  late SceneStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('scenes_');
    store = SceneStore(
      root: root.path,
      codec: SceneCodec(ComponentDefinitionRegistry.core()),
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  List<String> manifest() =>
      ((jsonDecode(File('${root.path}/scenes.json').readAsStringSync())
                  as Map<String, dynamic>)['scenes']
              as List)
          .cast<String>();

  group('SceneStore', () {
    test('a new scene is one flat JSON file, listed in the manifest', () async {
      await store.writeInitialFiles('level_a');

      expect(File('${root.path}/level_a.scene.json').existsSync(), isTrue);
      // No per-scene folder and no generated Dart: the game loads the JSON.
      expect(root.listSync().whereType<Directory>(), isEmpty);
      expect(
        root.listSync().map((e) => e.uri.pathSegments.last),
        isNot(contains(endsWith('.dart'))),
      );
      expect(manifest(), ['level_a']);
    });

    test('creating a scene never overwrites one that exists', () async {
      await store.writeInitialFiles('level_a');
      final file = File('${root.path}/level_a.scene.json');
      file.writeAsStringSync('{"name":"level_a","entities":[]}');

      await store.writeInitialFiles('level_a');

      expect(file.readAsStringSync(), '{"name":"level_a","entities":[]}');
      expect(manifest(), ['level_a']);
    });

    test('scenes list in manifest order, not alphabetically', () async {
      await store.writeInitialFiles('zeta');
      await store.writeInitialFiles('alpha');
      expect(store.listSceneNames(), ['zeta', 'alpha']);
    });

    test('a scene file missing from the manifest is still listed', () async {
      await store.writeInitialFiles('level_a');
      File('${root.path}/copied_in.scene.json').writeAsStringSync('{}');
      expect(store.listSceneNames(), ['level_a', 'copied_in']);
    });

    test('deleteSceneFiles removes the file and its manifest entry', () async {
      await store.writeInitialFiles('level_a');
      await store.deleteSceneFiles('level_a');

      expect(store.listSceneNames(), isEmpty);
      expect(manifest(), isEmpty);
    });

    test('deleteSceneFiles on a missing scene is a no-op', () async {
      await store.deleteSceneFiles('does_not_exist');
    });

    test('rename keeps the manifest position and rewrites the name', () async {
      await store.writeInitialFiles('first');
      await store.writeInitialFiles('middle');
      await store.writeInitialFiles('last');

      await store.renameSceneFiles('middle', 'renamed');

      expect(manifest(), ['first', 'renamed', 'last']);
      expect(File('${root.path}/middle.scene.json').existsSync(), isFalse);
      final json =
          jsonDecode(File('${root.path}/renamed.scene.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(json['name'], 'renamed');
    });

    test('duplicate is listed right after its source', () async {
      await store.writeInitialFiles('first');
      await store.writeInitialFiles('last');

      await store.duplicateSceneFiles('first', 'first_copy');

      expect(manifest(), ['first', 'first_copy', 'last']);
      final copy =
          jsonDecode(
                File('${root.path}/first_copy.scene.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(copy['name'], 'first_copy');
      expect(File('${root.path}/first.scene.json').existsSync(), isTrue);
    });
  });

  group('SceneManager', () {
    test('deleteScene refuses a protected scene', () async {
      await store.writeInitialFiles('__test_scene_e__');
      final manager = SceneManager(
        store: store,
        protectedSceneNames: {'__test_scene_e__'},
      );

      expect(
        () => manager.deleteScene('__test_scene_e__'),
        throwsA(isA<SceneManagerException>()),
      );
      // File must still exist — the guard should run before any I/O.
      expect(store.listSceneNames(), contains('__test_scene_e__'));
    });

    test('renameScene refuses a protected scene', () async {
      await store.writeInitialFiles('__test_scene_f__');
      final manager = SceneManager(
        store: store,
        protectedSceneNames: {'__test_scene_f__'},
      );

      expect(
        () => manager.renameScene('__test_scene_f__', '__test_scene_g__'),
        throwsA(isA<SceneManagerException>()),
      );
    });

    test(
      'renameScene/duplicateScene refuse an invalid or taken name',
      () async {
        await store.writeInitialFiles('__test_scene_h__');
        await store.writeInitialFiles('__test_scene_i__');
        final manager = SceneManager(store: store);

        expect(
          () => manager.renameScene('__test_scene_h__', '__test_scene_i__'),
          throwsA(isA<SceneManagerException>()),
        );
        expect(
          () => manager.duplicateScene('__test_scene_h__', 'not a valid name'),
          throwsA(isA<SceneManagerException>()),
        );
      },
    );

    test('renameScene allows renaming a scene to its own current name '
        'validation to exclude itself', () async {
      await store.writeInitialFiles('__test_scene_j__');
      final manager = SceneManager(store: store);

      // Renaming "j" -> "j" would normally collide with itself in the
      // existing-names check; validateName(ignoring: oldName) should permit it.
      expect(
        manager.validateName('__test_scene_j__', ignoring: '__test_scene_j__'),
        isNull,
      );
    });

    test('listScenes and isProtected reflect configuration', () async {
      await store.writeInitialFiles('__test_scene_k__');
      final manager = SceneManager(
        store: store,
        protectedSceneNames: {'__test_scene_k__'},
      );

      expect(manager.listScenes(), contains('__test_scene_k__'));
      expect(manager.isProtected('__test_scene_k__'), isTrue);
      expect(manager.isProtected('__test_scene_unknown__'), isFalse);
    });
  });
}
