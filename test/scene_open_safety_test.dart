// Opening a scene must never put the author's files at risk: a file that
// cannot be read does not open (as an empty scene a save would write over
// it), a malformed entry is mended rather than stopping the open, and what
// the editor held about the last scene by entity id — hidden, locked,
// prefab mode — or its unsaved map edits do not leak into the next one.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/level_map/tile_commands.dart';
import 'package:just_game_engine_editor/src/core/scene/scene_io.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';

void main() {
  late Directory project;
  late EditorScope scope;
  late SceneIO io;

  String scenes() => '${project.path}/assets/scenes';

  void write(String name, String text) =>
      File('${scenes()}/$name.scene.json').writeAsStringSync(text);

  Map<String, dynamic> sceneJson(
    String name,
    List<Map<String, dynamic>> entities,
  ) => {
    'version': SceneFormat.current,
    'name': name,
    'mode': 'twoD',
    'entities': entities,
  };

  Map<String, dynamic> entity(String name, {bool enabled = true}) => {
    'name': name,
    'parentName': null,
    if (!enabled) 'enabled': false,
    'components': [
      {
        'type': 'TransformComponent',
        'fields': {
          'position': {'x': 0.0, 'y': 0.0},
        },
      },
    ],
  };

  setUp(() {
    project = Directory.systemTemp.createTempSync('scene_open_safety');
    Directory(scenes()).createSync(recursive: true);
    write(
      'good',
      jsonEncode(sceneJson('good', [entity('Background'), entity('Player')])),
    );
    scope = testScope(scenesRoot: scenes());
    io = SceneIO(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
    );
  });

  tearDown(() {
    try {
      project.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may hold it a moment longer.
    }
  });

  List<String?> names() => [
    for (final e in scope.world.entities)
      if (e.isAlive) e.name,
  ];

  group('a file that cannot be read (EC-2)', () {
    test(
      'does not open, and the scene that was open stays as it was',
      () async {
        expect(await io.open('good'), isTrue);
        const broken = '{"name": "broken", "entities": [],}';
        write('broken', broken);

        expect(await io.open('broken'), isFalse);

        expect(scope.sceneState.activeScene.value?.name, 'good');
        expect(names(), containsAll(['Background', 'Player']));
        expect(
          scope.log.entries.value.map((e) => e.message),
          contains(contains('Could not open scene broken')),
        );
        // Nothing can save over it: the file is as the author left it.
        expect(
          File('${scenes()}/broken.scene.json').readAsStringSync(),
          broken,
        );
      },
    );

    test('nor does a file that is JSON but not a scene', () async {
      write('list', '[1, 2, 3]');
      expect(await io.open('list'), isFalse);
      expect(scope.sceneState.hasScene, isFalse);
    });

    test('a missing file still opens as a new, empty scene', () async {
      expect(await io.open('new_level'), isTrue);
      expect(scope.sceneState.activeScene.value?.name, 'new_level');
    });
  });

  group('one malformed value (EC-23)', () {
    test('is mended with a warning; the rest of the scene opens', () async {
      write(
        'odd',
        jsonEncode({
          'version': SceneFormat.current,
          'mode': 'twoD',
          // No "name": the file's own name is used.
          'entities': [
            entity('Ok'),
            {'name': 42, 'components': []},
            {'name': 'NoList', 'components': 'oops'},
            'not an entity',
          ],
        }),
      );
      expect(await io.open('odd'), isTrue);
      expect(scope.sceneState.activeScene.value?.name, 'odd');
      expect(names(), contains('Ok'));
      expect(
        scope.log.entries.value.map((e) => e.message),
        contains(contains('not text')),
      );
    });

    test('a file naming itself another scene is opened and saved as its '
        'own file', () async {
      write('copy', jsonEncode(sceneJson('good', [entity('Copied')])));
      expect(await io.open('copy'), isTrue);
      expect(scope.sceneState.activeScene.value?.name, 'copy');
      await io.save();
      final good = jsonDecode(
        File('${scenes()}/good.scene.json').readAsStringSync(),
      );
      expect(
        [for (final e in good['entities'] as List) e['name']],
        ['Background', 'Player'],
        reason: 'the scene it was copied from is not written over',
      );
    });
  });

  group('what the last scene left behind (EC-15, EC-14)', () {
    test('hidden, locked and pinned ids are forgotten', () async {
      expect(await io.open('good'), isTrue);
      final player = scope.world.entities.firstWhere((e) => e.name == 'Player');
      scope.view
        ..setHidden([player.id], hidden: true)
        ..setLocked([player.id], locked: true)
        ..togglePinned(player.id);
      write('other', jsonEncode(sceneJson('other', [entity('A')])));

      expect(await io.open('other'), isTrue);

      expect(scope.view.hidden.value, isEmpty);
      expect(scope.view.locked.value, isEmpty);
      expect(scope.view.pinned.value, isNull);
    });

    test('prefab mode is dropped, nothing applied', () async {
      expect(await io.open('good'), isTrue);
      final player = scope.world.entities.firstWhere((e) => e.name == 'Player');
      player.addComponent(
        PrefabInstanceComponent(
          block: PrefabInstance(path: 'assets/prefabs/p.prefab.json'),
        ),
      );
      scope.prefabInstances.edit(player);
      expect(scope.prefabInstances.editing.value, player.id);

      expect(await io.open('good'), isTrue);

      expect(scope.prefabInstances.editing.value, isNull);
      expect(
        await scope.prefabInstances.leave(apply: true),
        isTrue,
        reason: 'nothing left to apply to another scene\'s entity',
      );
    });
  });

  group('root order (EC-18)', () {
    test('a switched-off root keeps its place through open and save', () async {
      write(
        'menu',
        jsonEncode(
          sceneJson('menu', [
            entity('Background'),
            entity('Menu', enabled: false),
            entity('Player'),
          ]),
        ),
      );
      expect(await io.open('menu'), isTrue);
      await io.save();
      final saved = jsonDecode(
        File('${scenes()}/menu.scene.json').readAsStringSync(),
      );
      expect(
        [for (final e in saved['entities'] as List) e['name']],
        ['Background', 'Menu', 'Player'],
      );
    });
  });

  group('map files edited and not saved (EC-4)', () {
    test('are read again from disk when another scene opens', () async {
      final tiles = scope.context.tiles;
      const path = 'assets/maps/shared.map.json';
      final edited = LevelMapData()..addLayer(name: 'Painted');
      tiles.putMap(path, edited);
      scope.mapDocs.markEdited(LevelMapRef(entityId: 0, path: path));
      expect(scope.mapDocs.hasDirty, isTrue);

      expect(await io.open('good'), isTrue);

      expect(
        scope.mapDocs.hasDirty,
        isFalse,
        reason: 'the next save does not write them',
      );
      expect(
        tiles.loadedMap(path),
        isNull,
        reason: 'read again from the file when next drawn',
      );
    });
  });
}
