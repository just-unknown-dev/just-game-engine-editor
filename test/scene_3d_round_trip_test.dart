// Scene format 6 through the editor: a scene holding 3-D values — depth,
// tilts, a z scale, a turned and scaled parent — opens and saves without
// losing any of them, and saving twice writes the same bytes.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/scene/scene_io.dart';

Map<String, dynamic> _transform(
  List<double> p,
  List<double> r,
  List<double> s,
) => {
  'type': 'TransformComponent',
  'fields': {
    'position': {'x': p[0], 'y': p[1], 'z': p[2]},
    'rotation': {'x': r[0], 'y': r[1], 'z': r[2]},
    'scale': {'x': s[0], 'y': s[1], 'z': s[2]},
  },
};

final _v6 = <String, dynamic>{
  'version': 6,
  'name': 'deep',
  'mode': '3d',
  'entities': [
    {
      'name': 'Turret',
      'parentName': null,
      'components': [
        _transform([100, 50, 20], [0.2, -0.4, 1.1], [2, 2, 2]),
      ],
    },
    {
      'name': 'Barrel',
      'parentName': 'Turret',
      'components': [
        _transform([130, 70, 25], [0.5, 0.25, -0.75], [1, 3, 0.5]),
        {
          'type': 'ParentComponent',
          'fields': {'parentId': 0},
        },
      ],
    },
  ],
};

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('deep_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('3-D values survive open and save, and saves are stable', () async {
    final file = File('${root.path}/deep.scene.json')
      ..writeAsStringSync(jsonEncode(_v6));
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

    expect(await io.open('deep'), isTrue);
    expect(scope.sceneState.sceneMode.value, SceneMode.threeD);
    final barrel = scope.world.entities.firstWhere((e) => e.name == 'Barrel');
    final t = barrel.getComponent<TransformComponent>()!;
    expect([t.position.x, t.position.y, t.position.z], [130, 70, 25]);
    expect([t.eulerX, t.eulerY, t.angle], [0.5, 0.25, -0.75]);
    expect(t.scale.z, 0.5);

    expect(await io.save(), isTrue);
    final first = file.readAsStringSync();
    final saved = jsonDecode(first) as Map<String, dynamic>;
    expect(saved['version'], SceneFormat.current);
    expect(saved['mode'], '3d', reason: 'a 3-D scene stays 3-D');
    expect(saved.containsKey('root'), isFalse);
    final entities = (saved['entities'] as List).cast<Map>();
    Map fieldsOf(String name) =>
        (entities.firstWhere((e) => e['name'] == name)['components'] as List)
                .cast<Map>()
                .firstWhere((c) => c['type'] == 'TransformComponent')['fields']
            as Map;
    expect(
      fieldsOf('Barrel'),
      (_v6['entities'] as List)[1]['components'][0]['fields'],
    );
    expect(
      fieldsOf('Turret'),
      (_v6['entities'] as List)[0]['components'][0]['fields'],
    );

    // A link saves live entity ids (a child's parentId, a parent's
    // childIds), which the loader ignores — it re-links by name — and which
    // count on across opens; they are the only thing allowed to differ.
    // Everything else is the same text.
    String withoutIds(String text) => text
        .replaceAll(RegExp(r'"parentId": \d+'), '"parentId": _')
        .replaceAll(RegExp(r'"childIds": \[[\s\d,]*\]'), '"childIds": _');
    expect(await io.open('deep'), isTrue);
    expect(await io.save(), isTrue);
    expect(
      withoutIds(file.readAsStringSync()),
      withoutIds(first),
      reason: 'byte for byte',
    );
  });
}
