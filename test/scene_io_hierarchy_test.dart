// Opening a scene in the editor: the hierarchy the file describes is the
// hierarchy the editor gets, whatever the entities are made of.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  late Directory project;
  late EditorScope scope;
  late SceneIO io;

  /// A scene holding a HUD — a canvas with children, none of which has a
  /// transform — beside an ordinary platform.
  Map<String, dynamic> sceneJson() => {
    'version': SceneFormat.current,
    // A scene file carries its own node graph beside the entities.
    ...EditorScene(name: 'level_test').toJson(),
    'entities': [
      {
        'name': 'Platform',
        'parentName': null,
        'components': [
          {
            'type': 'TransformComponent',
            'fields': {
              'position': {'x': 0.0, 'y': 0.0},
            },
          },
        ],
      },
      {
        'name': 'Hud',
        'parentName': null,
        'components': [
          {
            'type': 'UiCanvasComponent',
            'fields': {'designW': 400.0, 'designH': 300.0},
          },
          {
            'type': 'ChildrenComponent',
            'fields': {'childIds': <int>[]},
          },
        ],
      },
      {
        'name': 'Coins',
        'parentName': 'Hud',
        'components': [
          {
            'type': 'TextComponent',
            'fields': {'textValue': 'Coins'},
          },
        ],
      },
    ],
  };

  setUp(() {
    project = Directory.systemTemp.createTempSync('scene_io_test');
    Directory('${project.path}/assets/scenes').createSync(recursive: true);
    File(
      '${project.path}/assets/scenes/level_test.scene.json',
    ).writeAsStringSync(jsonEncode(sceneJson()));
    File('${project.path}/assets/scenes/scenes.json').writeAsStringSync(
      jsonEncode({
        'scenes': ['level_test'],
      }),
    );

    scope = testScope(scenesRoot: '${project.path}/assets/scenes');
    io = SceneIO(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
    );
    addTearDown(() {
      if (project.existsSync()) project.deleteSync(recursive: true);
    });
  });

  test('a child with no transform is still linked to its parent', () async {
    await io.open('level_test');

    final hud = scope.world.findEntityByName('Hud')!;
    final coins = scope.world.findEntityByName('Coins')!;

    // Both ways. Building the name map from a transform query dropped
    // every piece of interface, so a HUD's children read as roots: no
    // chevron, no indent, and a save would have written them as roots
    // too.
    expect(coins.getComponent<ParentComponent>()?.parentId, hud.id);
    expect(hud.getComponent<ChildrenComponent>()!.childIds, contains(coins.id));
  });

  test(
    'opening another scene clears the interface the last one left',
    () async {
      await io.open('level_test');
      expect(scope.world.findEntityByName('Coins'), isNotNull);

      // The same scene again: what was there must go, not pile up.
      await io.open('level_test');

      final named = [
        for (final e in scope.world.entities)
          if (e.isActive && e.name == 'Coins') e,
      ];
      expect(named, hasLength(1), reason: 'one Coins, not two');
    },
  );

  test('the roots are remembered in the order the file lists them', () async {
    await io.open('level_test');

    final order = scope.sceneState.rootOrder(scope.world);
    final names = [for (final id in order) scope.world.getEntity(id)?.name];

    expect(names, ['Platform', 'Hud']);
  });

  test('an entity switched off is saved that way and comes back off', () async {
    await io.open('level_test');
    final coins = scope.world.findEntityByName('Coins')!;
    coins.isActive = false;

    await io.save();

    final saved =
        jsonDecode(
              File(
                '${project.path}/assets/scenes/level_test.scene.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final entities = (saved['entities'] as List).cast<Map<String, dynamic>>();
    final written = entities.firstWhere((e) => e['name'] == 'Coins');
    expect(written['enabled'], isFalse);
    // Everything else says nothing, because on is the ordinary case.
    expect(
      entities.firstWhere((e) => e['name'] == 'Hud').containsKey('enabled'),
      isFalse,
    );

    // And it is still in the scene, still off, after opening it again.
    await io.open('level_test');
    final again = scope.world.findEntityByName('Coins')!;
    expect(again.isAlive, isTrue);
    expect(again.isActive, isFalse);
  });
}
