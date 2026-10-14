// The starter scenes New Scene writes come from just_game_engine_formats as
// plain JSON, shared with `just game scene new`. This keeps them honest: encoding
// the live components through the scene codec must still give exactly that
// JSON. When a component gains a field or changes a default, this fails, and
// the starters in just_game_engine_formats' scene_starters.dart are updated
// to match.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/scene/editor_scene.dart';
import 'package:just_game_engine_editor/src/core/serialization/scene_codec.dart';
import 'package:just_game_engine_editor/src/core/serialization/scene_store.dart';

void main() {
  final codec = SceneCodec(ComponentDefinitionRegistry.core());
  List<Map<String, dynamic>> encode(List<Component> components) =>
      components.map(codec.encode).whereType<Map<String, dynamic>>().toList();
  Map<String, dynamic> entity(String name, List<Component> components) => {
    'name': name,
    'parentName': null,
    'components': encode(components),
  };

  test('the 2-D starter is the live components, encoded', () {
    final live = {
      'version': SceneFormat.current,
      ...EditorScene(name: 'level_01').toJson(),
      'entities': [
        entity('MainCamera', [
          TransformComponent(position: Vector3(2000, 400, 0)),
          VirtualCameraComponent(follow: const EntityTarget.tag('player')),
          CameraFramingComponent(),
          CameraConfinerComponent(boundsName: 'LevelBounds'),
        ]),
        entity('LevelBounds', [
          TransformComponent(position: Vector3(2000, 400, 0)),
          CameraBoundsComponent(width: 4000, height: 800),
        ]),
        entity('PlayerSpawn', [
          TransformComponent(position: Vector3(200, 400, 0)),
          SpawnComponent(spawner: 'player'),
        ]),
      ],
    };
    expect(
      SceneStarters.encode(SceneStarters.twoD('level_01')),
      const JsonEncoder.withIndent('  ').convert(live),
    );
  });

  test('the 3-D starter is the live components, encoded', () {
    const back = 8.0, up = 3.0;
    final live = {
      'version': SceneFormat.current,
      ...EditorScene(name: 'world', mode: SceneMode.threeD).toJson(),
      'entities': [
        entity('MainCamera', [
          TransformComponent(
            position: Vector3(0, -up, -back),
            euler: Vector3(-math.atan2(up, back), 0, 0),
          ),
          VirtualCameraComponent(
            projection: CameraProjection.perspective,
            nearClip: 0.1,
            farClip: 500,
          ),
        ]),
        entity('PlayerSpawn', [
          TransformComponent(),
          SpawnComponent(spawner: 'player'),
        ]),
      ],
    };
    expect(
      SceneStarters.encode(SceneStarters.threeD('world')),
      const JsonEncoder.withIndent('  ').convert(live),
    );
  });

  test('New Scene writes the starter and lists it', () async {
    final root = Directory.systemTemp.createTempSync('starters_');
    addTearDown(() => root.deleteSync(recursive: true));
    final store = SceneStore(root: root.path, codec: codec);
    await store.writeInitialFiles('level_01');
    expect(
      File('${root.path}/level_01.scene.json').readAsStringSync(),
      SceneStarters.encode(SceneStarters.twoD('level_01')),
    );
    expect(
      File('${root.path}/scenes.json').readAsStringSync(),
      SceneManifest.encode(['level_01']),
    );
  });
}
