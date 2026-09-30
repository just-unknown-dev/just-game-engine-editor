// A v0 scene opened in the editor is saved as v1, and what comes back is what
// went in. The migration is exercised end to end on a temporary store, the
// way a project's old levels will meet the new format.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

final _v0 = {
  'name': 'old',
  'root': Scene(name: 'old').toJson()['root'],
  'entities': [
    {
      'name': 'Block',
      'parentName': null,
      'components': [
        {
          'type': 'TransformComponent',
          'position': {'dx': 96.0, 'dy': 32.0},
          'rotation': 0.5,
          'scale': 2.0,
        },
        {'type': 'RectangleComponent', 'width': 64.0, 'height': 16.0},
        {
          'type': 'TagComponent',
          'customComponentId': 'tag_8a41b7f8',
          'fields': {'tag': 'ground'},
        },
      ],
    },
  ],
};

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('flip_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('v0 opens, saves as v1, and reopens with the same values', () async {
    File('${root.path}/old.scene.json').writeAsStringSync(jsonEncode(_v0));
    final scope = testScope();
    scope.container.registerSingleton<SceneStore>(
      SceneStore(root: root.path, codec: scope.codec),
      override: true,
    );
    final io = SceneIO(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
    );

    expect(await io.open('old'), isTrue);
    final block = scope.world.query([TransformComponent]).single;
    final t = block.getComponent<TransformComponent>()!;
    expect((t.position.x, t.position.y), (96.0, 32.0));
    expect(t.angle, 0.5);
    expect(t.scale.x, 2.0);
    expect(block.getComponent<TagComponent>()!.tags, ['ground']);

    expect(await io.save(), isTrue);
    final saved =
        jsonDecode(File('${root.path}/old.scene.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(SceneFormat.versionOf(saved), SceneFormat.current);
    final components =
        ((saved['entities'] as List).single as Map)['components'] as List;
    for (final c in components.cast<Map>()) {
      expect(c.keys.toSet(), {'type', 'fields'}, reason: '${c['type']}');
    }

    expect(await io.open('old'), isTrue);
    final again = scope.world.query([TransformComponent]).single;
    final t2 = again.getComponent<TransformComponent>()!;
    expect((t2.position.x, t2.position.y), (96.0, 32.0));
    expect(t2.angle, 0.5);
    expect(again.components.whereType<RectangleComponent>().single.width, 64);
    expect(again.getComponent<TagComponent>()!.tags, ['ground']);
  });
}
