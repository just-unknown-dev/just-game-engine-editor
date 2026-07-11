import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/src/core/serialization/scene_file_generator.dart';
import 'package:just_game_engine_editor/src/core/serialization/scene_manager.dart';

// SceneFileGenerator's root is hardcoded to `${Directory.current.path}/lib/game/scenes`
// (not injectable), so these tests write real files under the test-run cwd
// (this package's root) using clearly-marked names and clean up in tearDown
// regardless of pass/fail.

/// Polls [check] briefly before failing — recursive directory deletes can
/// lag a beat on Windows (AV/indexing) when many test files run concurrently.
Future<void> _expectEventually(
  bool Function() check, {
  int attempts = 20,
  Duration delay = const Duration(milliseconds: 25),
}) async {
  for (var i = 0; i < attempts; i++) {
    if (check()) return;
    await Future<void>.delayed(delay);
  }
  expect(check(), isTrue);
}

void main() {
  final gameDir = Directory('${Directory.current.path}/lib/game');
  final scenesDir = Directory('${gameDir.path}/scenes');

  tearDown(() {
    // Remove the whole lib/game scaffold (not just scenes/) — this package
    // has no lib/game of its own, it only exists here as test fixture.
    if (gameDir.existsSync()) {
      gameDir.deleteSync(recursive: true);
    }
  });

  group('SceneFileGenerator delete/rename/duplicate', () {
    test('deleteSceneFiles removes the scene folder', () async {
      await SceneFileGenerator.writeInitialFiles('__test_scene_a__');
      expect(SceneFileGenerator.listSceneNames(), contains('__test_scene_a__'));

      await SceneFileGenerator.deleteSceneFiles('__test_scene_a__');

      await _expectEventually(
        () => !SceneFileGenerator.listSceneNames().contains('__test_scene_a__'),
      );
    });

    test('deleteSceneFiles on a missing scene is a no-op', () async {
      await SceneFileGenerator.deleteSceneFiles('__does_not_exist__');
      // Should not throw.
    });

    test('renameSceneFiles moves files and rewrites class names', () async {
      await SceneFileGenerator.writeInitialFiles('__test_scene_b__');

      await SceneFileGenerator.renameSceneFiles(
        '__test_scene_b__',
        '__test_scene_c__',
      );

      await _expectEventually(() {
        final names = SceneFileGenerator.listSceneNames();
        return !names.contains('__test_scene_b__') &&
            names.contains('__test_scene_c__');
      });

      final levelContent = await File(
        '${scenesDir.path}/__test_scene_c__/__test_scene_c__.level.dart',
      ).readAsString();
      expect(levelContent, contains('class TestSceneCLevel'));
      expect(levelContent, isNot(contains('TestSceneBLevel')));

      final jsonContent = await File(
        '${scenesDir.path}/__test_scene_c__/__test_scene_c__.scene.json',
      ).readAsString();
      expect(jsonContent, contains('"__test_scene_c__"'));
    });

    test('duplicateSceneFiles copies without touching the source', () async {
      await SceneFileGenerator.writeInitialFiles('__test_scene_d__');

      await SceneFileGenerator.duplicateSceneFiles(
        '__test_scene_d__',
        '__test_scene_d_copy__',
      );

      expect(
        SceneFileGenerator.listSceneNames(),
        allOf(
          contains('__test_scene_d__'),
          contains('__test_scene_d_copy__'),
        ),
      );

      final copyLevel = await File(
        '${scenesDir.path}/__test_scene_d_copy__/__test_scene_d_copy__.level.dart',
      ).readAsString();
      expect(copyLevel, contains('class TestSceneDCopyLevel'));
    });
  });

  group('SceneManager', () {
    test('deleteScene refuses a protected scene', () async {
      await SceneFileGenerator.writeInitialFiles('__test_scene_e__');
      final manager = SceneManager(protectedSceneNames: {'__test_scene_e__'});

      expect(
        () => manager.deleteScene('__test_scene_e__'),
        throwsA(isA<SceneManagerException>()),
      );
      // File must still exist — the guard should run before any I/O.
      expect(SceneFileGenerator.listSceneNames(), contains('__test_scene_e__'));
    });

    test('renameScene refuses a protected scene', () async {
      await SceneFileGenerator.writeInitialFiles('__test_scene_f__');
      final manager = SceneManager(protectedSceneNames: {'__test_scene_f__'});

      expect(
        () => manager.renameScene('__test_scene_f__', '__test_scene_g__'),
        throwsA(isA<SceneManagerException>()),
      );
    });

    test('renameScene/duplicateScene refuse an invalid or taken name', () async {
      await SceneFileGenerator.writeInitialFiles('__test_scene_h__');
      await SceneFileGenerator.writeInitialFiles('__test_scene_i__');
      final manager = SceneManager();

      expect(
        () => manager.renameScene('__test_scene_h__', '__test_scene_i__'),
        throwsA(isA<SceneManagerException>()),
      );
      expect(
        () => manager.duplicateScene('__test_scene_h__', 'not a valid name'),
        throwsA(isA<SceneManagerException>()),
      );
    });

    test('renameScene allows renaming a scene to its own current name '
        'validation to exclude itself', () async {
      await SceneFileGenerator.writeInitialFiles('__test_scene_j__');
      final manager = SceneManager();

      // Renaming "j" -> "j" would normally collide with itself in the
      // existing-names check; validateName(ignoring: oldName) should permit it.
      expect(manager.validateName('__test_scene_j__', ignoring: '__test_scene_j__'), isNull);
    });

    test('listScenes and isProtected reflect configuration', () async {
      await SceneFileGenerator.writeInitialFiles('__test_scene_k__');
      final manager = SceneManager(protectedSceneNames: {'__test_scene_k__'});

      expect(manager.listScenes(), contains('__test_scene_k__'));
      expect(manager.isProtected('__test_scene_k__'), isTrue);
      expect(manager.isProtected('__test_scene_unknown__'), isFalse);
    });
  });
}
