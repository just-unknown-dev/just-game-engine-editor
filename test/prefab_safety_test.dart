// A prefab file is shared by every scene that places it, so the editor
// treats it with care: Apply keeps the version it replaces and writes whole
// or not at all, never outside the project; Unpack is an unsaved change; a
// prefab that changed on disk makes again only its own instances, and one
// caught half-written leaves them as they were.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/prefabs/prefab_instances.dart';

Map<String, dynamic> _transform(double x, double y) => {
  'type': 'TransformComponent',
  'fields': {
    'position': {'x': x, 'y': y, 'z': 0.0},
  },
};

Map<String, dynamic> _tags(List<String> tags) => {
  'type': 'TagComponent',
  'fields': {'tags': tags},
};

const _crate = 'assets/prefabs/crate.prefab.json';
const _barrel = 'assets/prefabs/barrel.prefab.json';

PrefabFile _file(String name, {double lidY = -10}) => PrefabFile(
  name: name,
  entities: [
    PrefabEntity(
      id: 'box',
      name: 'Box',
      components: [
        _transform(0, 0),
        _tags([name.toLowerCase()]),
      ],
    ),
    PrefabEntity(
      id: 'lid',
      name: 'Lid',
      parent: 'box',
      components: [_transform(0, lidY)],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late EditorScope scope;
  late PrefabInstances prefabs;

  File file(String path) => File('${dir.path}/$path');

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('prefab_safety');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may hold it a moment longer.
      }
    });
    file(_crate)
      ..createSync(recursive: true)
      ..writeAsStringSync(_file('Crate').encode());
    file(_barrel).writeAsStringSync(_file('Barrel').encode());
    scope = testScope();
    scope.context.overrideLoaders(
      prefabs: (path) async => PrefabFile.parse(file(path).readAsStringSync()),
    );
    scope.sceneState.openScene(EditorScene(name: 'yard'));
    prefabs = PrefabInstances(scope, root: dir.path);
    await prefabs.library.load(_crate);
    await prefabs.library.load(_barrel);
  });

  group('Apply (EC-30)', () {
    test('keeps the version it replaces, and leaves no half file', () async {
      final before = file(_crate).readAsStringSync();
      final top = prefabs.place(_crate, at: Vector3(100, 50, 0))!;
      top.getComponent<TagComponent>()!.tags = {'crate', 'heavy'};

      expect(await prefabs.apply(top), isTrue);

      final backups = Directory(
        '${dir.path}/${PrefabInstances.backupFolder}',
      ).listSync().whereType<File>().toList();
      expect(backups, hasLength(1));
      expect(backups.single.path, endsWith('crate.prefab.json'));
      expect(backups.single.readAsStringSync(), before);
      expect(file(_crate).readAsStringSync(), contains('heavy'));
      expect(
        Directory(
          '${dir.path}/assets/prefabs',
        ).listSync().where((e) => e.path.endsWith('.saving')),
        isEmpty,
      );
    });

    test(
      'a prefab path from the scene that leaves the project is refused',
      () async {
        // Beside the project's folder, which a scene's `../` reaches.
        const outside = '../outside.prefab.json';
        file(outside).writeAsStringSync(_file('Outside').encode());
        addTearDown(() {
          if (file(outside).existsSync()) file(outside).deleteSync();
        });
        await prefabs.library.load(outside);
        final top = prefabs.place(outside, at: Vector3.zero())!;
        top.getComponent<TagComponent>()!.tags = {'outside', 'changed'};

        expect(await prefabs.apply(top), isFalse);
        expect(file(outside).readAsStringSync(), isNot(contains('changed')));
      },
    );
  });

  group('Unpack (EC-29)', () {
    test('is an unsaved change, undone or redone', () {
      final top = prefabs.place(_crate, at: Vector3.zero())!;
      scope.sceneState.markClean();
      prefabs.unpack(top);
      expect(scope.sceneState.isDirty.value, isTrue);
      scope.sceneState.markClean();
      scope.history.undo();
      expect(scope.sceneState.isDirty.value, isTrue);
    });
  });

  group('a prefab changed on disk (EC-31)', () {
    test('makes again only the instances made from it', () async {
      final crate = prefabs.place(_crate, at: Vector3(100, 50, 0))!;
      final barrel = prefabs.place(_barrel, at: Vector3(300, 50, 0))!;
      final barrelLid = prefabs.membersOf(barrel)['lid']!;
      barrel.getComponent<TagComponent>()!.tags = {'barrel', 'dented'};
      final barrelTags = barrel.getComponent<TagComponent>();

      file(_crate).writeAsStringSync(_file('Crate', lidY: -30).encode());
      await prefabs.refresh(_crate);

      final crateLid = prefabs.membersOf(crate)['lid']!;
      expect(
        crateLid.getComponent<TransformComponent>()!.position.y,
        closeTo(20, 1e-6),
      );
      expect(
        barrel.getComponent<TagComponent>(),
        same(barrelTags),
        reason: 'the barrel was not made again',
      );
      expect(prefabs.membersOf(barrel)['lid'], same(barrelLid));
    });

    test('caught half-written, it leaves its instances as they were', () async {
      final crate = prefabs.place(_crate, at: Vector3(100, 50, 0))!;
      crate.getComponent<TagComponent>()!.tags = {'crate', 'heavy'};
      file(_crate).writeAsStringSync('{"name": "Crate", "entit');

      await prefabs.refresh(_crate);

      expect(
        prefabs.library.loaded(_crate),
        isNotNull,
        reason: 'the version it had is kept',
      );
      expect(crate.getComponent<TagComponent>()!.tags, contains('heavy'));
      expect(
        prefabs.changesOf(crate).block.overrides,
        isNotEmpty,
        reason: 'what it changes is still worked out against its prefab',
      );
    });
  });
}
