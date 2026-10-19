// A module's protection rule is kept: what it protects is not deleted, and
// the log says why.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/entity/entity_ops.dart';

import 'support/test_scope.dart';

class _KeepsPlayer extends EditorModule {
  @override
  String get id => 'test.keepsPlayer';

  @override
  String get name => 'Keeps the player';

  @override
  EntityProtectionRule get protectionRule => EntityProtectionRule(
    id: 'test.player',
    isProtected: (entity) => entity.name == 'Player',
  );
}

void main() {
  test('a protected entity, and what holds it, are not deleted; the rest '
      'are, in one undo step', () {
    final scope = testScope(modules: [_KeepsPlayer()]);
    final ops = EntityOps(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
      camera: () => GameCameraEditorView.of(Camera()),
    );
    scope.sceneState.openScene(EditorScene(name: 'level'));
    Entity make(String name) {
      final e = scope.world.createEntityWithComponents([
        TransformComponent(),
        ChildrenComponent(),
      ], name: name);
      scope.sceneState.registerEntity(e);
      return e;
    }

    final player = make('Player');
    final crate = make('Crate');
    final group = make('Group');
    final inside = make('Player');
    ops.reparentEntity(inside, group);
    scope.sceneState.multiSelectedIds.value = {player.id, crate.id, group.id};

    ops.deleteSelection(scope.history);

    expect(player.isAlive, isTrue);
    expect(group.isAlive, isTrue, reason: 'it holds a protected entity');
    expect(inside.isAlive, isTrue);
    expect(crate.isAlive, isFalse);
    final said = scope.log.entries.value.map((e) => e.message).join('\n');
    expect(said, contains('Player is protected by a module'));
    expect(said, contains('so Group was not deleted'));

    scope.history.undo();
    expect(
      scope.world.entities.where((e) => e.isAlive && e.name == 'Crate'),
      hasLength(1),
      reason: 'the delete that happened is one undo step',
    );
  });

  test('with no rule, everything selected goes', () {
    final scope = testScope();
    final e = scope.world.createEntityWithComponents([
      TransformComponent(),
    ], name: 'Player');
    expect(scope.deletable([e]), [e]);
    expect(scope.protectedIn(e), isNull);
  });
}
