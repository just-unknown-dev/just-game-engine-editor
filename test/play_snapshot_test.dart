// Play runs the real systems on the authored entities. Stopping has to put
// every one of them back, or the next save writes play-mode state into the
// level — which is how a spawned player once ended up saved into level_01.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/state/play_snapshot.dart';

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
    scope = EditorScope(world: world);
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
}
