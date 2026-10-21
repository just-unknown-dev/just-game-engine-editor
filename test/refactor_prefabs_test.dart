// A tag renamed or deleted, or a collision layer deleted, everywhere: the
// prefab files too (backed up first), what instances of them change in the
// closed scenes, and the open scene's instances made again from the
// rewritten prefab; a layer some file still uses is kept.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/physics/layer_refactor.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/core/tags/tag_refactor.dart';

const _goblin = 'assets/prefabs/goblin.prefab.json';

Map<String, dynamic> _transform() => {
  'type': 'TransformComponent',
  'fields': {
    'position': {'x': 0.0, 'y': 0.0, 'z': 0.0},
  },
};

Map<String, dynamic> _tags(List<String> tags) => {
  'type': 'TagComponent',
  'fields': {'tags': tags},
};

Map<String, dynamic> _body(int layer) => {
  'type': 'RigidBody2D',
  'fields': {'layer': layer},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late EditorScope scope;

  String scenesRoot() => '${root.path}/assets/scenes';
  File prefabFile() => File('${root.path}/$_goblin');

  void writePrefab({List<String> tags = const ['enemy'], int layer = 0}) =>
      prefabFile()
        ..createSync(recursive: true)
        ..writeAsStringSync(
          PrefabFile(
            name: 'Goblin',
            entities: [
              PrefabEntity(
                id: 'body',
                name: 'Body',
                components: [_transform(), _tags(tags), _body(layer)],
              ),
            ],
          ).encode(),
        );

  /// A closed scene with an instance of the goblin that changes its tags
  /// and its layer.
  void writeScene(String name, {List<String>? tags, int? layer}) =>
      File('${scenesRoot()}/$name.scene.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'version': SceneFormat.current,
            'name': name,
            'entities': [
              {
                'name': 'Goblin',
                'prefab': {
                  'path': _goblin,
                  'overrides': [
                    if (tags != null)
                      {
                        'target': 'body',
                        'component': 'TagComponent',
                        'field': 'tags',
                        'value': tags,
                      },
                    if (layer != null)
                      {
                        'target': 'body',
                        'component': 'RigidBody2D',
                        'field': 'layer',
                        'value': layer,
                      },
                  ],
                },
              },
            ],
          }),
        );

  Map<String, dynamic> readScene(String name) =>
      jsonDecode(File('${scenesRoot()}/$name.scene.json').readAsStringSync())
          as Map<String, dynamic>;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('refactor_prefabs_');
    Directory(scenesRoot()).createSync(recursive: true);
    scope = testScope(scenesRoot: scenesRoot());
    scope.context.overrideLoaders(
      prefabs: (path) async =>
          PrefabFile.parse(File('${root.path}/$path').readAsStringSync()),
    );
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may hold it for a moment; it is a temporary one.
    }
  });

  group('a tag renamed everywhere', () {
    test('reaches prefab files, after a backup, and instance changes in '
        'closed scenes', () async {
      writePrefab();
      writeScene('level_02', tags: ['enemy', 'boss']);
      final refactor = TagRefactor(scope, projectRoot: root.path);
      final plan = refactor.plan('enemy', renameTo: 'foe');
      expect(plan.prefabs.keys, [_goblin]);
      expect(plan.scenes.keys, ['level_02']);

      final result = await refactor.apply(plan);
      expect(result.failures, isEmpty);
      final prefab = PrefabFile.parse(prefabFile().readAsStringSync());
      expect(
        (prefab
                .byId('body')!
                .components
                .firstWhere((c) => c['type'] == 'TagComponent')['fields']
            as Map)['tags'],
        ['foe'],
      );
      final backups = Directory(
        '${scope.scenes.backupsRoot}/.prefabs/assets/prefabs/goblin',
      ).listSync();
      expect(backups, hasLength(1));
      expect(File(backups.single.path).readAsStringSync(), contains('"enemy"'));

      final override =
          ((readScene('level_02')['entities'] as List).single['prefab']
                  as Map)['overrides']
              as List;
      expect(override.single['value'], ['foe', 'boss']);
      expect(scope.tags.names, contains('foe'));
      expect(scope.tags.names, isNot(contains('enemy')));
    });

    test('the open scene\'s instances follow the prefab, with no change of '
        'their own', () async {
      writePrefab();
      scope.sceneState.openScene(EditorScene(name: 'yard'));
      final instances = scope.prefabInstances;
      await instances.library.load(_goblin);
      final top = instances.place(_goblin, at: Vector3(10, 0, 0))!;
      expect(top.tags, ['enemy']);

      final refactor = TagRefactor(scope, projectRoot: root.path);
      await refactor.apply(refactor.plan('enemy', renameTo: 'foe'));
      final now = scope.world.entities.firstWhere(
        (e) => e.isAlive && e.hasComponent<PrefabInstanceComponent>(),
      );
      expect(now.tags, ['foe']);
      final block = instances.changesOf(now).block;
      expect(
        block.overrides.where((o) => o.component == 'TagComponent'),
        isEmpty,
        reason: 'the new name comes from the prefab',
      );
    });

    test('a tag file that cannot be read stops it, before any file is '
        'touched', () async {
      writePrefab();
      File(scope.tags.path)
        ..createSync(recursive: true)
        ..writeAsStringSync('{ broken');
      scope.tags.load();
      final before = prefabFile().readAsStringSync();
      final refactor = TagRefactor(scope, projectRoot: root.path);
      final result = await refactor.apply(
        refactor.plan('enemy', renameTo: 'foe'),
      );
      expect(result.failures, isNotEmpty);
      expect(result.filesWritten, isEmpty);
      expect(prefabFile().readAsStringSync(), before);
    });
  });

  group('a layer deleted everywhere', () {
    test('moves what prefabs and instance changes put on it', () async {
      final layers = scope.physicsLayers;
      final pickups = layers.create('Pickups')!;
      writePrefab(layer: pickups);
      writeScene('level_02', layer: pickups);
      final refactor = LayerRefactor(scope, projectRoot: root.path);
      final plan = refactor.plan(pickups);
      expect(plan.prefabs.keys, [_goblin]);
      expect(plan.scenes.keys, ['level_02']);

      final result = await refactor.apply(plan);
      expect(result.failures, isEmpty);
      expect(prefabFile().readAsStringSync(), isNot(contains('"layer": 1')));
      final override =
          ((readScene('level_02')['entities'] as List).single['prefab']
                  as Map)['overrides']
              as List;
      expect(override.single['value'], 0);
      expect(layers.value.isNamed(pickups), isFalse);
    });

    test('is kept when a file could not be changed', () async {
      final layers = scope.physicsLayers;
      final pickups = layers.create('Pickups')!;
      writePrefab(layer: pickups);
      final refactor = LayerRefactor(scope, projectRoot: root.path);
      final plan = refactor.plan(pickups);
      // Gone between the plan and the change: it cannot be rewritten.
      prefabFile().deleteSync();
      final result = await refactor.apply(plan);
      expect(result.failures.keys, [_goblin]);
      expect(layers.value.isNamed(pickups), isTrue);
    });
  });
}
