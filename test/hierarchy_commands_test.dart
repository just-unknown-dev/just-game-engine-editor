// Changing the shape of a scene: every move, rename, group and delete is
// one undoable step that puts things back exactly where they were.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/entity/entity_ops.dart';

void main() {
  late EditorScope scope;
  late EntityOps ops;

  setUp(() {
    scope = testScope();
    ops = EntityOps(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
      camera: () => GameCameraEditorView.of(Camera()),
    );
    scope.sceneState.openScene(EditorScene(name: 'level_test'));
  });

  World world() => scope.world;

  List<EntityId> childrenOf(Entity entity) =>
      entity.getComponent<ChildrenComponent>()?.childIds ?? const [];

  EntityId? parentOf(Entity entity) =>
      entity.getComponent<ParentComponent>()?.parentId;

  Entity node(String name, {Entity? under, double x = 0}) {
    final entity = world().createEntityWithComponents([
      TransformComponent(position: Vector3(x, 0, 0)),
      ChildrenComponent(),
    ], name: name);
    scope.sceneState.registerEntity(entity);
    if (under != null) ops.reparentEntity(entity, under);
    return entity;
  }

  group('moving things about', () {
    test('a move is undoable, back to the same parent and place', () {
      final a = node('A');
      final b = node('B');
      final first = node('First', under: a);
      final second = node('Second', under: a);
      final third = node('Third', under: a);
      expect(childrenOf(a), [first.id, second.id, third.id]);

      ops.reparentEntity(second, b);
      expect(parentOf(second), b.id);
      expect(childrenOf(a), [first.id, third.id]);

      scope.history.undo();

      expect(parentOf(second), a.id);
      expect(childrenOf(a), [
        first.id,
        second.id,
        third.id,
      ], reason: 'back in the middle, where it was');
      expect(childrenOf(b), isEmpty);
    });

    test('a move into a given place lands there', () {
      final a = node('A');
      final first = node('First', under: a);
      final last = node('Last', under: a);
      final moved = node('Moved');

      ops.reparentEntity(moved, a, index: 1);

      expect(childrenOf(a), [first.id, moved.id, last.id]);
    });

    test('a parent cannot be moved into its own child', () {
      final parent = node('Parent');
      final child = node('Child', under: parent);
      final before = scope.history.canUndo.value;

      ops.reparentEntity(parent, child);

      expect(parentOf(parent), isNull);
      expect(childrenOf(child), isEmpty);
      expect(
        scope.history.canUndo.value,
        before,
        reason: 'nothing happened, so nothing to undo',
      );
    });

    test('moving a selection is one step, and children come along', () {
      final from = node('From');
      final to = node('To');
      final one = node('One', under: from);
      final two = node('Two', under: from);
      // Two's own child is not named in the move, but goes with it.
      final grandchild = node('Grandchild', under: two);

      ops.reparentAll([one, two], to);

      expect(parentOf(one), to.id);
      expect(parentOf(two), to.id);
      expect(parentOf(grandchild), two.id);
      expect(childrenOf(to), [one.id, two.id]);

      scope.history.undo();

      expect(childrenOf(from), [one.id, two.id]);
      expect(parentOf(grandchild), two.id);
    });

    test('naming both a parent and its child moves the parent only', () {
      final from = node('From');
      final to = node('To');
      final parent = node('Parent', under: from);
      final child = node('Child', under: parent);

      // What dragging a selection that happens to include both means.
      ops.reparentAll([parent, child], to);

      expect(childrenOf(to), [parent.id]);
      expect(childrenOf(parent), [
        child.id,
      ], reason: 'the child stayed inside its parent');
    });
  });

  group('order', () {
    test('a child moves among its siblings, and undo puts it back', () {
      final parent = node('Parent');
      final a = node('A', under: parent);
      final b = node('B', under: parent);
      final c = node('C', under: parent);

      ops.reorderEntity(c, a, before: true);
      expect(childrenOf(parent), [c.id, a.id, b.id]);

      scope.history.undo();
      expect(childrenOf(parent), [a.id, b.id, c.id]);
    });

    test('a root moves among the roots', () {
      final a = node('A');
      final b = node('B');
      final c = node('C');
      expect(scope.sceneState.rootOrder(world()), [a.id, b.id, c.id]);

      ops.reorderEntity(c, a, before: true);

      expect(scope.sceneState.rootOrder(world()), [c.id, a.id, b.id]);

      scope.history.undo();
      expect(scope.sceneState.rootOrder(world()), [a.id, b.id, c.id]);
    });

    test('nudging moves one place and stops at the ends', () {
      final parent = node('Parent');
      final a = node('A', under: parent);
      final b = node('B', under: parent);

      ops.nudgeOrder(b, up: true);
      expect(childrenOf(parent), [b.id, a.id]);

      // Already first: nothing to do, and nothing pushed.
      final steps = scope.history.canUndo.value;
      ops.nudgeOrder(b, up: true);
      expect(childrenOf(parent), [b.id, a.id]);
      expect(scope.history.canUndo.value, steps);
    });

    test('the order the roots are in is the order they are saved in', () {
      final a = node('A');
      final b = node('B');
      node('C');

      ops.reorderEntity(b, a, before: true);

      final saved = scope.codec.encodeEntities(
        world().entities.toList(),
        rootOrder: scope.sceneState.rootOrder(world()),
      );
      expect([for (final e in saved) e['name']], ['B', 'A', 'C']);
    });
  });

  group('names', () {
    test('a name something else has is refused', () {
      final a = node('Platform_0');
      node('Platform_1');

      expect(ops.renameEntity(a, 'Platform_1'), isFalse);
      expect(a.name, 'Platform_0');
    });

    test('a free name is taken, and undone', () {
      final a = node('Platform_0');

      expect(ops.renameEntity(a, 'Ledge'), isTrue);
      expect(a.name, 'Ledge');

      scope.history.undo();
      expect(a.name, 'Platform_0');
    });

    test('renaming something to what it is already called is fine', () {
      final a = node('Platform_0');
      expect(ops.renameEntity(a, 'Platform_0'), isTrue);
      expect(ops.renameEntity(a, '  '), isFalse);
    });
  });

  group('deleting', () {
    test('the whole subtree goes, and comes back where it was', () {
      final root = node('Root');
      final card = node('Card', under: root);
      node('Title', under: card);
      node('Button', under: card);
      final sibling = node('Sibling', under: root);
      expect(childrenOf(root), [card.id, sibling.id]);

      scope.sceneState.selectEntity(card);
      ops.deleteSelection(scope.history);

      for (final name in ['Card', 'Title', 'Button']) {
        expect(world().findEntityByName(name), isNull, reason: name);
      }
      expect(world().findEntityByName('Sibling'), isNotNull);

      scope.history.undo();

      final backCard = world().findEntityByName('Card')!;
      final backTitle = world().findEntityByName('Title')!;
      final backButton = world().findEntityByName('Button')!;
      // Back under the same parent, in the same place, with its own
      // children under it in their own order.
      expect(parentOf(backCard), root.id);
      expect(childrenOf(root), [backCard.id, sibling.id]);
      expect(childrenOf(backCard), [backTitle.id, backButton.id]);
      expect(parentOf(backTitle), backCard.id);
    });

    test('deleting a root puts it back in its place among the roots', () {
      final a = node('A');
      final b = node('B');
      final c = node('C');

      scope.sceneState.selectEntity(b);
      ops.deleteSelection(scope.history);
      expect(scope.sceneState.rootOrder(world()), [a.id, c.id]);

      scope.history.undo();

      final back = world().findEntityByName('B')!;
      expect(scope.sceneState.rootOrder(world()), [a.id, back.id, c.id]);
    });
  });

  group('groups', () {
    test('grouping takes the selection in, and undo lets it out', () {
      final a = node('A', x: 0);
      final b = node('B', x: 100);
      scope.sceneState
        ..toggleMultiSelect(a)
        ..toggleMultiSelect(b);

      final group = ops.groupSelection()!;

      expect(childrenOf(group), [a.id, b.id]);
      // At the middle of what it holds.
      expect(
        group.getComponent<TransformComponent>()!.position.x,
        closeTo(50, 0.001),
      );

      scope.history.undo();

      expect(parentOf(a), isNull);
      expect(parentOf(b), isNull);
      expect(world().findEntityByName(group.name!), isNull);
    });

    test('ungrouping moves the children up and drops the group', () {
      final root = node('Root');
      final a = node('A', under: root);
      final group = node('Group', under: root);
      final inside = node('Inside', under: group);
      expect(childrenOf(root), [a.id, group.id]);

      ops.ungroup(group);

      expect(parentOf(inside), root.id);
      expect(childrenOf(root), [
        a.id,
        inside.id,
      ], reason: 'in the place the group had');
      expect(world().findEntityByName('Group'), isNull);

      scope.history.undo();

      final backGroup = world().findEntityByName('Group')!;
      expect(parentOf(inside), backGroup.id);
      expect(childrenOf(root), [a.id, backGroup.id]);
    });
  });

  group('enabled', () {
    test('turning an entity off is undoable', () {
      final a = node('A');

      scope.history.push(
        SetEnabledCommand(
          sceneState: scope.sceneState,
          entity: a,
          enabled: false,
        ),
      );
      expect(a.isActive, isFalse);

      scope.history.undo();
      expect(a.isActive, isTrue);
    });
  });
}
