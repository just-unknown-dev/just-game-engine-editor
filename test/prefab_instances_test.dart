// Prefabs in the editor's scene: an instance placed and saved as one entry
// of what it changes; made again when its prefab changes, keeping those
// changes; Apply writing them into the prefab (with what the scene put
// inside it), Revert taking them back; a prefab made from a selection; an
// instance unpacked; and a scene with instances opened, saved and played.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/state/play_snapshot.dart';

import 'support/test_scope.dart';

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

PrefabFile _crateFile({double lidY = -10}) => PrefabFile(
  name: 'Crate',
  entities: [
    PrefabEntity(id: 'box', name: 'Box', components: [_transform(0, 0), _tags(['crate'])]),
    PrefabEntity(id: 'lid', name: 'Lid', parent: 'box', components: [_transform(0, lidY)]),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late EditorScope scope;
  late PrefabInstances prefabs;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('jge_prefabs');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/$_crate')
      ..createSync(recursive: true)
      ..writeAsStringSync(_crateFile().encode());
    scope = testScope();
    scope.context.overrideLoaders(
      prefabs: (path) async => PrefabFile.parse(File('${dir.path}/$path').readAsStringSync()),
    );
    scope.sceneState.openScene(EditorScene(name: 'yard'));
    prefabs = PrefabInstances(scope, root: dir.path);
    await prefabs.library.load(_crate);
  });

  Entity named(String name) => scope.world.entities.firstWhere((e) => e.isAlive && e.name == name);
  Vector3 at(Entity e) => e.getComponent<TransformComponent>()!.position;
  List<Map<String, dynamic>> saved() => scope.codec.encodeEntities(PlaySnapshot.authored(scope.world));

  test('placed where asked, saved as one entry of what it changes', () {
    final top = prefabs.place(_crate, at: Vector3(100, 50, 0))!;
    expect(top.name, startsWith('Crate'));
    expect([at(named('Lid')).x, at(named('Lid')).y], [100, 40]);
    expect(scope.history.undoEntries, hasLength(1));

    var entries = saved();
    expect(entries, hasLength(1));
    final block = PrefabInstance.fromJson(entries.single['prefab'] as Map);
    expect(block.overrides.map((o) => '${o.target}.${o.field}'), ['box.position'], reason: 'only where it stands');

    // The lid moved inside it: a change against the top, in the prefab.
    scope.sceneState.setPosition3(named('Lid'), Vector3(103, 40, 0));
    entries = saved();
    final changed = PrefabInstance.fromJson(entries.single['prefab'] as Map);
    final lid = changed.overrides.singleWhere((o) => o.target == 'lid');
    expect(lid.value, {'x': 3.0, 'y': -10.0, 'z': 0.0});

    scope.history.undo();
    expect(scope.world.entities.where((e) => e.isAlive), isEmpty);
  });

  test('made again when its prefab changes, keeping what it changes', () async {
    final top = prefabs.place(_crate, at: Vector3(100, 50, 0))!;
    top.getComponent<TagComponent>()!.tags = {'crate', 'heavy'};
    File('${dir.path}/$_crate').writeAsStringSync(_crateFile(lidY: -30).encode());
    await prefabs.refresh(_crate);
    expect(at(named('Lid')).y, closeTo(20, 1e-6), reason: 'the new lid, 30 px above');
    expect(top.isAlive, isTrue, reason: 'the same entity');
    expect(top.getComponent<TagComponent>()!.tags, contains('heavy'));
  });

  test('Apply writes the changes into the prefab, with what was put inside', () async {
    final top = prefabs.place(_crate, at: Vector3(100, 50, 0))!;
    top.getComponent<TagComponent>()!.tags = {'crate', 'heavy'};
    final coin = scope.world.createEntityWithComponents([TransformComponent(position: Vector3(100, 30, 0))], name: 'Coin');
    scope.sceneState.registerEntity(coin);
    placeEntity(coin, world: scope.world, sceneState: scope.sceneState, slot: HierarchySlot(parentId: named('Lid').id, index: -1));

    expect(await prefabs.apply(top), isTrue);
    final file = PrefabFile.parse(File('${dir.path}/$_crate').readAsStringSync());
    expect((file.byId('box')!.components.firstWhere((c) => c['type'] == 'TagComponent')['fields'] as Map)['tags'], contains('heavy'));
    final added = file.entities.singleWhere((e) => e.name == 'Coin');
    expect(added.parent, 'lid');
    expect((added.components.first['fields'] as Map)['position'], {'x': 0.0, 'y': -20.0, 'z': 0.0}, reason: 'in the prefab\'s space');
    expect(file.byId('box')!.components.first['fields'], isNot(contains('nothing')));
    // The coin is now the instance's own, and the instance changes nothing.
    final coinNow = named('Coin');
    expect(coinNow.getComponent<PrefabLink>()?.instance, top.id);
    expect([at(coinNow).x, at(coinNow).y], [100, 30]);
    final block = PrefabInstance.fromJson(saved().single['prefab'] as Map);
    expect(block.overrides.map((o) => o.field), ['position']);
  });

  test('Revert takes the changes back but where it stands, as one undo step', () {
    final top = prefabs.place(_crate, at: Vector3(100, 50, 0))!;
    top.getComponent<TagComponent>()!.tags = {'crate', 'heavy'};
    scope.sceneState.setPosition3(named('Lid'), Vector3(103, 40, 0));
    prefabs.revertAll(top);
    expect(top.getComponent<TagComponent>()!.tags, {'crate'});
    expect([at(named('Lid')).x, at(named('Lid')).y], [100, 40]);
    expect([at(top).x, at(top).y], [100, 50]);
    scope.history.undo();
    expect(top.getComponent<TagComponent>()!.tags, contains('heavy'));
  });

  test('a prefab made from a selection, an instance where it was', () async {
    final post = scope.world.createEntityWithComponents([TransformComponent(position: Vector3(40, 20, 0))], name: 'Post');
    final sign = scope.world.createEntityWithComponents([TransformComponent(position: Vector3(40, 0, 0))], name: 'Sign');
    scope.sceneState
      ..registerEntity(post)
      ..registerEntity(sign);
    placeEntity(sign, world: scope.world, sceneState: scope.sceneState, slot: HierarchySlot(parentId: post.id, index: -1));
    final path = await prefabs.makePrefab(post);
    expect(path, 'assets/prefabs/post.prefab.json');
    final file = PrefabFile.parse(File('${dir.path}/$path').readAsStringSync());
    expect(file.entities.map((e) => e.name), ['Post', 'Sign']);
    expect((file.root.components.first['fields'] as Map)['position'], {'x': 0.0, 'y': 0.0, 'z': 0.0});
    expect((file.entities.last.components.first['fields'] as Map)['position'], {'x': 0.0, 'y': -20.0, 'z': 0.0});
    final top = named('Post');
    expect(top.hasComponent<PrefabInstanceComponent>(), isTrue);
    expect([at(named('Sign')).x, at(named('Sign')).y], [40, 0]);
    scope.history.undo();
    expect(named('Post').hasComponent<PrefabInstanceComponent>(), isFalse);
    expect(named('Sign').getComponent<ParentComponent>()?.parentId, named('Post').id);
  });

  test('unpacked: plain entities of the scene; undone, an instance again', () {
    final top = prefabs.place(_crate)!;
    prefabs.unpack(top);
    expect(top.hasComponent<PrefabInstanceComponent>(), isFalse);
    expect(saved().every((e) => e['prefab'] == null), isTrue);
    scope.history.undo();
    expect(saved(), hasLength(1));
  });

  test('a scene with an instance opens as the game would, and saves back', () async {
    final scenes = Directory('${dir.path}/assets/scenes')..createSync(recursive: true);
    final scope2 = testScope(scenesRoot: scenes.path);
    scope2.context.overrideLoaders(
      prefabs: (path) async => PrefabFile.parse(File('${dir.path}/$path').readAsStringSync()),
    );
    File('${scenes.path}/yard.scene.json').writeAsStringSync(jsonEncode({
      'version': SceneFormat.current,
      'name': 'yard',
      'mode': '2d',
      'entities': [
        {
          'name': 'Crate 1',
          'prefab': {
            'path': _crate,
            'overrides': [
              {'target': 'box', 'component': 'TransformComponent', 'field': 'position', 'value': {'x': 100.0, 'y': 50.0, 'z': 0.0}},
            ],
          },
        },
      ],
    }));
    final io = SceneIO(scope: scope2, world: () => scope2.world, sceneState: scope2.sceneState);
    await io.open('yard');
    final lid = scope2.world.entities.firstWhere((e) => e.name == 'Lid');
    expect([lid.getComponent<TransformComponent>()!.position.x, lid.getComponent<TransformComponent>()!.position.y], [100, 40]);
    final again = scope2.codec.encodeEntities(PlaySnapshot.authored(scope2.world));
    expect(again.single['name'], 'Crate 1');
    expect(PrefabInstance.fromJson(again.single['prefab'] as Map).overrides, hasLength(1));

    // Played and stopped: put back, and a save meanwhile writes the instance.
    final snapshot = PlaySnapshot.capture(scope2.world, scope2.codec);
    expect(snapshot.entities.single['prefab'], isNotNull);
    lid.getComponent<TransformComponent>()!.position.setValues(0, 0, 0);
    snapshot.restoreInto(scope2.world);
    final restored = scope2.world.entities.firstWhere((e) => e.name == 'Lid');
    expect(restored.getComponent<TransformComponent>()!.position.y, closeTo(40, 1e-6));
    expect(restored.getComponent<PrefabLink>(), isNotNull, reason: 'still part of it');
  });
}
