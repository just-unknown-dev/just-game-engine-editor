// Saving a scene tells every module first — a kit writing the files the
// scene refers to (a terrain's heights) — and a module that fails is
// reported without losing the save.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/scene/scene_io.dart';

/// Notes each save, and whether the scene file was there yet.
class _Recorder extends EditorModule {
  _Recorder(this.file);

  final File file;
  final List<(String, bool)> saves = [];

  @override
  String get id => 'test.recorder';

  @override
  String get name => 'Recorder';

  @override
  Future<void> onSceneSaving(String sceneName) async => saves.add((sceneName, file.existsSync()));
}

class _Failing extends EditorModule {
  @override
  String get id => 'test.failing';

  @override
  String get name => 'Failing';

  @override
  Future<void> onSceneSaving(String sceneName) async => throw StateError('disk full');
}

void main() {
  late Directory project;
  late File sceneFile;

  setUp(() {
    project = Directory.systemTemp.createTempSync('scene_saving_test');
    Directory('${project.path}/assets/scenes').createSync(recursive: true);
    sceneFile = File('${project.path}/assets/scenes/level_test.scene.json');
    File('${project.path}/assets/scenes/scenes.json').writeAsStringSync(
      jsonEncode({
        'scenes': ['level_test'],
      }),
    );
    addTearDown(() {
      if (project.existsSync()) project.deleteSync(recursive: true);
    });
  });

  test('modules hear of a save before the scene file is written', () async {
    final recorder = _Recorder(sceneFile);
    final scope = testScope(scenesRoot: '${project.path}/assets/scenes', modules: [recorder]);
    scope.sceneState.openScene(EditorScene(name: 'level_test'));
    final io = SceneIO(scope: scope, world: () => scope.world, sceneState: scope.sceneState);

    expect(await io.save(), isTrue);
    expect(recorder.saves, [('level_test', false)]);
    expect(sceneFile.existsSync(), isTrue);
  });

  test('a module that fails is reported; the scene is saved all the same', () async {
    final scope = testScope(scenesRoot: '${project.path}/assets/scenes', modules: [_Failing()]);
    scope.sceneState.openScene(EditorScene(name: 'level_test'));
    final io = SceneIO(scope: scope, world: () => scope.world, sceneState: scope.sceneState);

    expect(await io.save(), isTrue);
    expect(sceneFile.existsSync(), isTrue);
    expect(
      scope.log.entries.value.map((e) => e.message),
      contains(contains('test.failing could not write its files: Bad state: disk full')),
    );
  });
}
