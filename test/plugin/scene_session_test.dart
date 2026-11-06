// The open scene's session, where the editor and the game share one world:
// the editor hidden runs the game on the level and puts it back when shown,
// a save marks clean only what it wrote, autosave waits while an open is
// asking its questions, a declined backup is not offered again, and closing
// the window asks about unsaved changes.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/level_map/scope_level_maps.dart';
import 'package:just_game_engine_editor/src/plugin/just_game_editor_plugin.dart';

import '../support/memory_settings_store.dart';

/// Marks the scene unsaved while it is being saved: an edit made while the
/// files are written.
class _EditsDuringSave extends EditorModule {
  _EditsDuringSave(this.scope);

  final EditorScope scope;

  @override
  String get id => 'test.editsDuringSave';

  @override
  String get name => 'Edits during save';

  @override
  Future<void> onSceneSaving(String sceneName) async {
    await Future<void>.delayed(Duration.zero);
    scope.sceneState.markDirty();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Engine engine;
  late EditorScope scope;
  late JustGameEditorPlugin plugin;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('scene_session_');
    final store = SceneStore(
      root: root.path,
      codec: SceneCodec(BuiltInComponents.registry()),
    );
    for (final name in ['level_01', 'level_02']) {
      await store.writeInitialFiles(name);
    }
    engine = Engine();
    await engine.initialize();
    scope = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      engine: engine,
      scenesRoot: root.path,
      // Map files are written here, not in the package's folder.
      projectRoot: root.path,
      settingsStore: MemorySettingsStore(),
    );
    plugin = JustGameEditorPlugin(engine: engine, scope: scope);
    await plugin.attach(plugin.engine);
    await plugin.openScene('level_01');
  });

  tearDown(() {
    plugin.playController.stop();
    plugin.dispose();
    scope.dispose();
    engine.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Map<String, Map<String, dynamic>> savedIn(String scene) {
    final json =
        jsonDecode(File('${root.path}/$scene.scene.json').readAsStringSync())
            as Map<String, dynamic>;
    return {
      for (final e in (json['entities'] as List).cast<Map<String, dynamic>>())
        e['name'] as String: e,
    };
  }

  double? savedX(Map<String, dynamic> entity) {
    for (final c
        in (entity['components'] as List).cast<Map<String, dynamic>>()) {
      if (c['type'] != 'TransformComponent') continue;
      final position = (c['fields'] as Map)['position'] as Map;
      return (position['x'] as num).toDouble();
    }
    return null;
  }

  Entity block(String name, double x) {
    final e = engine.world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, 0, 0)),
    ], name: name);
    plugin.sceneState.registerEntity(e);
    return e;
  }

  Entity? named(String name) => engine.world.entities
      .where((e) => e.isAlive && e.name == name)
      .firstOrNull;

  group('the editor hidden over a scene', () {
    test('the game runs on the level; a save writes it as authored, and '
        'showing the editor puts it back', () async {
      if (!kDebugMode) return;
      final crate = block('Crate', 10);
      block('Coin', 20);
      expect(await plugin.saveScene(), isTrue);
      expect(plugin.sceneState.isDirty.value, isFalse);

      plugin.setVisible(false);
      // The game: the crate falls aside, the coin is taken, a spark is made.
      crate.getComponent<TransformComponent>()!.setPositionXY(500, 90);
      engine.world.destroyEntity(named('Coin')!);
      engine.world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Spark');
      // Something to save, as an edit made before hiding would leave.
      plugin.sceneState.markDirty();
      expect(await plugin.saveScene(), isTrue);

      final saved = savedIn('level_01');
      expect(saved.keys, containsAll(['Crate', 'Coin']));
      expect(saved.keys, isNot(contains('Spark')));
      expect(savedX(saved['Crate']!), 10, reason: 'where it was authored');

      plugin.setVisible(true);
      expect(
        named('Crate')!.getComponent<TransformComponent>()!.position.x,
        10,
      );
      expect(named('Coin'), isNotNull, reason: 'made again');
      expect(named('Spark'), isNull, reason: 'what the game made goes');
    });

    test('a scene opened meanwhile is not put back over', () async {
      if (!kDebugMode) return;
      block('Crate', 10);
      await plugin.saveScene();
      plugin.setVisible(false);
      await plugin.openScene('level_02');
      plugin.setVisible(true);
      expect(plugin.sceneState.activeScene.value!.name, 'level_02');
      expect(named('Crate'), isNull);
    });
  });

  test('an edit made while a save writes keeps the scene unsaved', () async {
    if (!kDebugMode) return;
    scope.modules.register(_EditsDuringSave(scope));
    block('Crate', 10);
    expect(plugin.sceneState.isDirty.value, isTrue);
    expect(await plugin.saveScene(), isTrue);
    expect(
      plugin.sceneState.isDirty.value,
      isTrue,
      reason: 'the file holds the scene from before the edit',
    );
  });

  test('a second save while the first writes the map files waits its turn: '
      'it is refused, and the maps are written once', () async {
    if (!kDebugMode) return;
    const path = 'assets/maps/cave.map.json';
    scope.mapDocs.tiles.putMap(path, BuiltInPrefabs.newLevelMap());
    scope.mapDocs.dirtyPaths.value = {path};
    block('Crate', 10);

    final first = plugin.saveScene();
    // Ctrl+S while the first is writing the map: it gets false at once,
    // rather than writing the same file through the same temporary file.
    final second = await plugin.saveScene();
    expect(second, isFalse);
    expect(await first, isTrue);
    expect(scope.mapDocs.hasDirty, isFalse);
    expect(
      jsonDecode(File('${root.path}/$path').readAsStringSync()),
      isA<Map<String, dynamic>>(),
    );
    expect(plugin.sceneState.isDirty.value, isFalse);
  });

  test('a save that fails leaves the scene unsaved', () async {
    if (!kDebugMode) return;
    block('Crate', 10);
    // The scene file is a folder now: it cannot be written.
    final file = File('${root.path}/level_01.scene.json')..deleteSync();
    Directory(file.path).createSync();
    await expectLater(plugin.saveScene(), throwsA(anything));
    expect(plugin.sceneState.isDirty.value, isTrue);
    Directory(file.path).deleteSync();
  });

  test('autosave waits while an open asks whether to recover a backup, '
      'after the changes were discarded', () async {
    if (!kDebugMode) return;
    scope.prefs.settings.value = scope.prefs.settings.value.copyWith(
      autosaveMode: AutosaveMode.save,
    );
    final before = File('${root.path}/level_01.scene.json').readAsStringSync();
    block('Discarded', 1);
    await scope.scenes.writeBackup(
      'level_02',
      '{"name":"level_02","entities":[{"name":"Kept"}]}',
      keep: 5,
    );
    plugin.askToLeaveScene = (_, _) async => UnsavedChoice.discard;
    bool? autosaved;
    plugin.askToRecover = (_, _) async {
      autosaved = await plugin.autosave();
      return false;
    };
    await plugin.openScene('level_02');
    expect(autosaved, isFalse);
    expect(
      File('${root.path}/level_01.scene.json').readAsStringSync(),
      before,
      reason: 'the discarded change is not saved',
    );
    expect(plugin.sceneState.activeScene.value!.name, 'level_02');
  });

  test('declining a recovered backup sets aside every unsaved one, not only '
      'the newest', () async {
    if (!kDebugMode) return;
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await scope.scenes.writeBackup(
        'level_02',
        '{"name":"level_02","entities":[{"name":"Draft $i"}]}',
        keep: 10,
      );
    }
    var asked = 0;
    plugin.askToRecover = (_, _) async {
      asked++;
      return false;
    };
    await plugin.openScene('level_02');
    expect(asked, 1);
    expect(scope.scenes.unsavedBackupOf('level_02'), isNull);

    await plugin.openScene('level_01');
    await plugin.openScene('level_02');
    expect(asked, 1, reason: 'nothing is offered again');
  });

  group('closing the window', () {
    test('with unsaved changes asks; Cancel stays', () async {
      if (!kDebugMode) return;
      block('Crate', 10);
      final asked = <String>[];
      plugin.askToSaveBeforeExit = (scene) async {
        asked.add(scene);
        return null;
      };
      expect(
        await WidgetsBinding.instance.handleRequestAppExit(),
        AppExitResponse.cancel,
      );
      expect(asked, ['level_01']);
    });

    test('Save writes the scene, then closes', () async {
      if (!kDebugMode) return;
      block('Crate', 10);
      plugin.askToSaveBeforeExit = (_) async => UnsavedChoice.save;
      expect(await plugin.confirmExit(), AppExitResponse.exit);
      expect(savedIn('level_01').keys, contains('Crate'));
      expect(plugin.sceneState.isDirty.value, isFalse);
    });

    test('Discard closes without saving', () async {
      if (!kDebugMode) return;
      block('Crate', 10);
      plugin.askToSaveBeforeExit = (_) async => UnsavedChoice.discard;
      expect(await plugin.confirmExit(), AppExitResponse.exit);
      expect(savedIn('level_01').keys, isNot(contains('Crate')));
    });

    test('with nobody to ask, a backup is kept', () async {
      if (!kDebugMode) return;
      block('Crate', 10);
      expect(await plugin.confirmExit(), AppExitResponse.exit);
      expect(scope.scenes.backupsOf('level_01'), hasLength(1));
    });

    test('with nothing unsaved, closes at once', () async {
      if (!kDebugMode) return;
      var asked = false;
      plugin.askToSaveBeforeExit = (_) async {
        asked = true;
        return null;
      };
      expect(await plugin.confirmExit(), AppExitResponse.exit);
      expect(asked, isFalse);
    });
  });
}
