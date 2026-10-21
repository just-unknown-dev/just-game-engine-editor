// What the selection operations act on: every selected entity that is
// there, switched off or not (Enabled is a saved setting, not existence);
// whole copies of groups; names unique against everything; and making an
// entity — Create Empty, Paste — is a step Ctrl+Z takes back.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/state/selection_ops.dart';

void main() {
  late EditorScope scope;
  World world() => scope.world;

  setUp(() {
    scope = testScope();
    scope.sceneState.openScene(EditorScene(name: 'level'));
  });

  Entity block(String name, {bool enabled = true}) {
    final e = world().createEntityWithComponents([
      TransformComponent(),
    ], name: name);
    e.isActive = enabled;
    scope.sceneState.registerEntity(e);
    return e;
  }

  void select(List<Entity> entities) =>
      scope.sceneState.selectRange(entities, anchor: entities.first);

  List<String?> live() => [
    for (final e in world().entities)
      if (e.isAlive) e.name,
  ];

  group('a switched-off entity in a multi-selection (EC-17, TD-18, LD-30)', () {
    test('is deleted with the rest', () {
      final a = block('A'), b = block('B', enabled: false), c = block('C');
      select([a, b, c]);
      expect(scope.entities.selectionEntities, hasLength(3));
      scope.entities.deleteSelection(scope.history);
      expect(live(), isEmpty);
      scope.history.undo();
      expect(live(), containsAll(['A', 'B', 'C']));
    });

    test('is grouped with the rest', () {
      final a = block('A'), b = block('B', enabled: false);
      select([a, b]);
      final group = scope.entities.groupSelection()!;
      final children = group.getComponent<ChildrenComponent>()!.childIds;
      expect(children, containsAll([a.id, b.id]));
    });

    test('is moved by the designer\'s tools; one with no transform is not', () {
      final a = block('A'), b = block('B', enabled: false);
      final label = world().createEntityWithComponents([
        HealthComponent(maxHealth: 3),
      ], name: 'Label');
      select([a, b, label]);
      expect(SelectionOps.selectedIn(scope.sceneState, world()), [a, b]);
      scope.sceneState.selectEntity(label);
      expect(SelectionOps.selectedIn(scope.sceneState, world()), isEmpty);
    });
  });

  group('Array (EC-20)', () {
    test('copies a group whole, and a selected child only with it', () {
      final stairs = block('Stairs');
      final steps = [for (var i = 0; i < 2; i++) block('Step_$i')];
      scope.entities.reparentAll(steps, stairs);
      select([stairs, steps.first]);
      scope.entities.arraySelection(
        scope.history,
        count: 2,
        step: const Offset(100, 0),
      );
      final groups = [
        for (final e in world().entities)
          if (e.isAlive &&
              e.name != 'Stairs' &&
              (e.name ?? '').startsWith('Stairs'))
            e,
      ];
      expect(groups, hasLength(2));
      for (final g in groups) {
        expect(
          g.getComponent<ChildrenComponent>()!.childIds,
          hasLength(2),
          reason: 'each copy holds its steps',
        );
      }
      final xs = [
        for (final g in groups)
          g.getComponent<TransformComponent>()!.position.x,
      ]..sort();
      expect(xs, [100, 200]);
      expect(
        live().where((n) => (n ?? '').startsWith('Step')),
        hasLength(6),
        reason: 'the selected step is copied once per group, not again',
      );
    });
  });

  group('names (EC-47)', () {
    test('a new name never repeats one without a transform', () {
      world().createEntityWithComponents([
        HealthComponent(maxHealth: 3),
      ], name: 'entity_0');
      expect(scope.entities.uniqueName('entity'), isNot('entity_0'));
    });

    test('grouping a parent with its child keeps the child in its parent', () {
      final parent = block('Parent');
      final child = block('Child');
      scope.entities.reparentAll([child], parent);
      select([parent, child]);
      final group = scope.entities.groupSelection()!;
      expect(group.getComponent<ChildrenComponent>()!.childIds, [parent.id]);
      expect(child.getComponent<ParentComponent>()!.parentId, parent.id);
    });
  });

  group('Create Empty and Paste are undoable (EC-16)', () {
    test('Create Empty', () {
      scope.entities.createEntity(at: const Offset(5, 5));
      expect(live(), hasLength(1));
      expect(scope.sceneState.isDirty.value, isTrue);
      scope.history.undo();
      expect(live(), isEmpty);
      scope.history.redo();
      expect(live(), hasLength(1));
    });

    test('Paste is undone before an earlier move', () {
      final a = block('A');
      scope.entities.copyEntity(a);
      scope.history.push(
        CallbackCommand(label: 'Move A', onRedo: () {}, onUndo: () {}),
      );
      scope.entities.pasteEntity(at: const Offset(40, 40));
      expect(live(), hasLength(2));
      expect(scope.history.nextUndoLabel.value, startsWith('Paste'));
      scope.history.undo();
      expect(live(), ['A']);
      expect(scope.history.nextUndoLabel.value, 'Move A');
    });
  });
}
