// Play runs the real systems on the authored entities. Stopping has to put
// every one of them back, or the next save writes play-mode state into the
// level — which is how a spawned player once ended up saved into level_01.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/play/play_snapshot.dart';
import 'package:just_game_engine_editor/src/scenes/scene_io.dart';

Entity _block(World world, String name, double x) =>
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, 100, 0)),
      LayerComponent(layerId: 'main', layer: 5),
      HealthComponent(maxHealth: 3),
    ], name: name);

void main() {
  late World world;
  late EditorScope scope;
  setUp(() {
    world = World()..initialize();
    scope = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      world: world,
    );
  });
  tearDown(() {
    scope.dispose();
    world.dispose();
  });

  test('moved entities go back, keeping their ids', () {
    final a = _block(world, 'A', 10);
    final snapshot = PlaySnapshot.capture(world, scope.codec);

    a.getComponent<TransformComponent>()!.setPositionXY(999, -50);
    snapshot.restoreInto(world);

    expect(world.getEntity(a.id), same(a), reason: 'id must survive');
    final p = a.getComponent<TransformComponent>()!.position;
    expect((p.x, p.y), (10.0, 100.0));
  });

  test('component state play changed is reset', () {
    final a = _block(world, 'A', 10);
    final snapshot = PlaySnapshot.capture(world, scope.codec);

    a.getComponent<HealthComponent>()!.health = 1;
    a.getComponent<LayerComponent>()!.layer = 40;
    snapshot.restoreInto(world);

    expect(a.getComponent<HealthComponent>()!.health, 3);
    expect(a.getComponent<LayerComponent>()!.layer, 5);
  });

  test('deactivated entities come back active', () {
    final a = _block(world, 'A', 10);
    final snapshot = PlaySnapshot.capture(world, scope.codec);

    a.isActive = false; // a crumbled platform, a collected pickup
    snapshot.restoreInto(world);

    expect(a.isActive, isTrue);
  });

  test('entities play destroyed are recreated', () {
    final a = _block(world, 'A', 10);
    final snapshot = PlaySnapshot.capture(world, scope.codec);

    world.destroyEntity(a);
    snapshot.restoreInto(world);

    final back = world.query([TransformComponent]).single;
    expect(back.name, 'A');
    expect(back.getComponent<TransformComponent>()!.position.x, 10);
  });

  test('entities play created are removed; ones that existed are not', () {
    _block(world, 'A', 10);
    final snapshot = PlaySnapshot.capture(world, scope.codec);

    world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, 0, 0)),
    ], name: 'Player');
    snapshot.restoreInto(world);

    expect(world.query([TransformComponent]).map((e) => e.name), ['A']);
  });

  test('components play added are removed', () {
    final a = _block(world, 'A', 10);
    final snapshot = PlaySnapshot.capture(world, scope.codec);

    a.addComponent(VelocityComponent());
    snapshot.restoreInto(world);

    expect(a.hasComponent<VelocityComponent>(), isFalse);
  });

  test('a save during play writes the level as authored', () {
    final a = _block(world, 'A', 10);
    final beforePlay = scope.codec.encodeEntities(PlaySnapshot.authored(world));
    final snapshot = PlaySnapshot.capture(world, scope.codec);

    a.getComponent<TransformComponent>()!.setPositionXY(500, 500);
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, 0, 0)),
    ], name: 'Player');

    // What _saveScene writes while playing.
    expect(snapshot.entities, beforePlay);
  });

  group('the tree comes back as it was', () {
    /// Hangs [child] under [parent], both ends, where it already is.
    void link(Entity child, Entity parent) {
      child.addComponent(ParentComponent(parentId: parent.id));
      if (!parent.hasComponent<ChildrenComponent>()) {
        parent.addComponent(ChildrenComponent());
      }
      parent.getComponent<ChildrenComponent>()!.addChild(child.id);
    }

    String? parentOf(Entity e) =>
        switch (e.getComponent<ParentComponent>()?.parentId) {
          final id? => world.getEntity(id)?.name,
          null => null,
        };

    Map<String?, String?> tree() => {
      for (final e in world.entities) e.name: parentOf(e),
    };

    test('an entity made last but filed early does not shift the rest', () {
      // Made in one order, filed in another: the snapshot once took ids in
      // the first and records in the second, so stopping play gave every
      // entity after the late one its neighbour's name, components and
      // place in the tree. level_01's menus were scrambled exactly so.
      final map = _block(world, 'Map', 0);
      final early = _block(world, 'Early', 0);
      link(early, map);
      final hud = world.createEntityWithComponents([
        HealthComponent(maxHealth: 1),
      ], name: 'Hud');
      final coins = world.createEntityWithComponents([
        HealthComponent(maxHealth: 2),
      ], name: 'Coins');
      link(coins, hud);
      final late = _block(world, 'Late', -144);
      link(late, map);

      final snapshot = PlaySnapshot.capture(world, scope.codec);
      snapshot.restoreInto(world);

      expect(tree(), {
        'Map': null,
        'Early': 'Map',
        'Hud': null,
        'Coins': 'Hud',
        'Late': 'Map',
      });
      // Every id kept its own record.
      expect([hud.name, coins.name, late.name], ['Hud', 'Coins', 'Late']);
      expect(coins.getComponent<HealthComponent>()!.maxHealth, 2);
      expect(map.getComponent<ChildrenComponent>()!.childIds, [
        early.id,
        late.id,
      ]);
      expect(hud.getComponent<ChildrenComponent>()!.childIds, [coins.id]);
      // The link comes back fresh; its local offset follows from where
      // things are.
      world.transformHierarchy.propagate();
      expect(late.getComponent<ParentComponent>()!.localPosition.x, -144);
      expect(late.getComponent<TransformComponent>()!.position.x, -144);
    });

    test('links play changed are put back', () {
      final a = _block(world, 'A', 0);
      final b = _block(world, 'B', 8);
      link(b, a);
      final c = _block(world, 'C', 0);
      final snapshot = PlaySnapshot.capture(world, scope.codec);

      // Play cuts B loose and hangs C under A.
      b.removeComponentByType(ParentComponent);
      a.getComponent<ChildrenComponent>()!.removeChild(b.id);
      link(c, a);
      snapshot.restoreInto(world);

      expect(tree(), {'A': null, 'B': 'A', 'C': null});
      expect(a.getComponent<ChildrenComponent>()!.childIds, [b.id]);
      world.transformHierarchy.propagate();
      expect(b.getComponent<ParentComponent>()!.localPosition.x, 8);
      expect(c.hasComponent<ChildrenComponent>(), isFalse);
    });

    test('a child play destroyed comes back under its parent', () {
      final a = _block(world, 'A', 0);
      final b = _block(world, 'B', 0);
      link(b, a);
      final snapshot = PlaySnapshot.capture(world, scope.codec);

      world.destroyEntity(b);
      snapshot.restoreInto(world);

      final back = world.findEntityByName('B')!;
      expect(parentOf(back), 'A');
      expect(a.getComponent<ChildrenComponent>()!.childIds, [back.id]);
    });

    test('an id handed out again during play does not keep what play made', () {
      final a = _block(world, 'A', 0);
      final b = _block(world, 'B', 0);
      link(b, a);
      final snapshot = PlaySnapshot.capture(world, scope.codec);

      // Everything goes, and an entity made at runtime takes its place.
      world.destroyAllEntities();
      _block(world, 'Runtime', 0);
      snapshot.restoreInto(world);

      expect(world.findEntityByName('Runtime'), isNull);
      expect(tree(), {'A': null, 'B': 'A'});
    });
  });

  group('a prefab instance', () {
    const crate = 'assets/prefabs/crate.prefab.json';
    Map<String, dynamic> transform(double x, double y) => {
      'type': 'TransformComponent',
      'fields': {
        'position': {'x': x, 'y': y, 'z': 0.0},
      },
    };

    late EditorScope yard;

    setUp(() async {
      final dir = Directory.systemTemp.createTempSync('play_snapshot_prefab');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/$crate')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          PrefabFile(
            name: 'Crate',
            entities: [
              PrefabEntity(
                id: 'box',
                name: 'Box',
                components: [transform(0, 0)],
              ),
              PrefabEntity(
                id: 'lid',
                name: 'Lid',
                parent: 'box',
                components: [transform(0, -10)],
              ),
            ],
          ).encode(),
        );
      final scenes = Directory('${dir.path}/assets/scenes')
        ..createSync(recursive: true);
      yard = EditorScope(
        builtIns: const [BuiltInEditorModule.new],
        world: World()..initialize(),
        scenesRoot: scenes.path,
      );
      addTearDown(yard.dispose);
      yard.context.overrideLoaders(
        prefabs: (path) async =>
            PrefabFile.parse(File('${dir.path}/$path').readAsStringSync()),
      );
      File('${scenes.path}/yard.scene.json').writeAsStringSync(
        jsonEncode({
          'version': SceneFormat.current,
          'name': 'yard',
          'mode': '2d',
          'entities': [
            {
              'name': 'Crate 1',
              'prefab': {'path': crate},
            },
          ],
        }),
      );
      final io = SceneIO(
        scope: yard,
        world: () => yard.world,
        sceneState: yard.sceneState,
      );
      await io.open('yard');
    });

    List<Map<String, dynamic>> saved() =>
        yard.codec.encodeEntities(PlaySnapshot.authored(yard.world));

    test('destroyed in play is saved as an instance after Stop', () {
      expect(saved().single['prefab'], isNotNull, reason: 'opens as one');
      final snapshot = PlaySnapshot.capture(yard.world, yard.codec);
      // Play breaks the crate: every part of it destroyed.
      for (final e in yard.world.entities.where((e) => e.isAlive).toList()) {
        yard.world.destroyEntity(e, withChildren: false);
      }
      snapshot.restoreInto(yard.world);

      final after = saved();
      expect(after, hasLength(1), reason: 'one prefab entry, as before Play');
      expect(after.single['prefab'], isNotNull);
    });

    test('a part that survived links to its top made again', () {
      final snapshot = PlaySnapshot.capture(yard.world, yard.codec);
      final lid = yard.world.findEntityByName('Lid')!;
      final top = yard.world.findEntityByName('Crate 1')!;
      yard.world.destroyEntity(top, withChildren: false);
      snapshot.restoreInto(yard.world);

      final back = yard.world.findEntityByName('Crate 1')!;
      expect(back.id, isNot(top.id), reason: 'made again under a new id');
      expect(back.hasComponent<PrefabInstanceComponent>(), isTrue);
      expect(lid.getComponent<PrefabLinkComponent>()!.instance, back.id);
      expect(saved().single['prefab'], isNotNull);
    });
  });
}
