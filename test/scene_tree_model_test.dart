// What the tree shows: order, depth, what a search keeps, and what a
// running game adds.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/ui/scene_tree/scene_tree_model.dart';

void main() {
  late World world;

  setUp(() {
    world = World()..initialize();
    addTearDown(world.dispose);
  });

  Entity node(String name, {Entity? under, String? tag}) {
    final entity = world.createEntityWithComponents([
      TransformComponent(),
      ChildrenComponent(),
      if (tag != null) TagComponent(tag),
      if (under != null) ParentComponent(parentId: under.id),
    ], name: name);
    under?.getComponent<ChildrenComponent>()!.addChild(entity.id);
    return entity;
  }

  SceneTree build({
    List<EntityId>? rootOrder,
    Set<EntityId>? expanded,
    TreeFilter filter = TreeFilter.none,
    Set<EntityId>? authored,
    Set<EntityId> withProblems = const {},
  }) => SceneTreeModel.build(
    world: world,
    rootOrder: rootOrder ?? const [],
    expanded: expanded ?? {for (final e in world.entities) e.id},
    filter: filter,
    authored: authored,
    withProblems: withProblems,
  );

  List<String?> names(SceneTree tree) => [
    for (final row in tree.rows) row.entity.name,
  ];

  group('shape', () {
    test('parents come before their children, indented', () {
      final root = node('Root');
      final child = node('Child', under: root);
      node('Grandchild', under: child);

      final tree = build();

      expect(names(tree), ['Root', 'Child', 'Grandchild']);
      expect([for (final r in tree.rows) r.depth], [0, 1, 2]);
      expect(tree.rows.first.hasChildren, isTrue);
      expect(tree.rows.last.hasChildren, isFalse);
    });

    test('a shut row hides what is under it', () {
      final root = node('Root');
      node('Child', under: root);

      final tree = build(expanded: const {});

      expect(names(tree), ['Root']);
      // Still known to have children, which is what draws the chevron.
      expect(tree.rows.single.hasChildren, isTrue);
      expect(tree.rows.single.isExpanded, isFalse);
    });

    test('children are in the order their parent lists them', () {
      final root = node('Root');
      final a = node('A', under: root);
      final b = node('B', under: root);
      // Put B first, the way a reorder does.
      final ids = root.getComponent<ChildrenComponent>()!.childIds
        ..clear()
        ..addAll([b.id, a.id]);
      expect(ids, [b.id, a.id]);

      expect(names(build()), ['Root', 'B', 'A']);
    });

    test('the roots are in the order the editor holds them', () {
      final a = node('A');
      final b = node('B');
      final c = node('C');

      expect(names(build(rootOrder: [c.id, a.id, b.id])), ['C', 'A', 'B']);
    });

    test('a root the order does not mention is still shown, last', () {
      node('A');
      final b = node('B');

      expect(names(build(rootOrder: [b.id])), ['B', 'A']);
      expect(names(build(rootOrder: const [])), ['A', 'B']);
    });

    test('an entity whose parent is gone is a root, not lost', () {
      final ghost = world.createEntityWithComponents([
        TransformComponent(),
        // Names a parent that is not in the world.
        ParentComponent(parentId: 999),
      ], name: 'Orphan');

      expect(names(build()), contains('Orphan'));
      expect(build().rows.single.depth, 0);
      expect(ghost.isActive, isTrue);
    });

    test('a child its parent forgot to list is still shown under it', () {
      final root = node('Root');
      final child = world.createEntityWithComponents([
        TransformComponent(),
        ParentComponent(parentId: root.id),
      ], name: 'Forgotten');
      // The world lists a linked child with its parent; take it off the
      // list by hand, so the parent's list is empty but the child still
      // points at it.
      root.getComponent<ChildrenComponent>()!.removeChild(child.id);
      expect(root.getComponent<ChildrenComponent>()!.childIds, isEmpty);
      expect(child.isActive, isTrue);

      final tree = build();

      expect(names(tree), ['Root', 'Forgotten']);
      expect(tree.rows.last.depth, 1);
    });

    test('an entity turned off is still listed', () {
      final root = node('Root');
      node('Child', under: root).isActive = false;

      // Off is a thing the scene says about an entity and saves, not a
      // reason to hide it from the tree: the row is drawn struck
      // through, and it is the only way to switch it back on.
      expect(names(build(expanded: {root.id})), ['Root', 'Child']);
    });

    test('switching one off leaves it where it was', () {
      node('First');
      final middle = node('Middle');
      node('Last');

      middle.isActive = false;

      // The remembered order is about what the scene holds, not about
      // what is switched on: reading `isActive` there dropped the row
      // out and the fallback pass put it back at the end, so turning a
      // row off sent it to the bottom of the tree.
      expect(names(build()), ['First', 'Middle', 'Last']);
    });

    test('a destroyed entity is gone from the tree', () {
      final root = node('Root');
      final child = node('Child', under: root);
      world.destroyEntity(child);

      expect(names(build(expanded: {root.id})), ['Root']);
    });
  });

  group('searching', () {
    test('a match keeps the parents that show where it is', () {
      final root = node('Root');
      final middle = node('Middle', under: root);
      node('Coin', under: middle);
      node('Elsewhere');

      final tree = build(filter: const TreeFilter(text: 'coin'));

      expect(names(tree), ['Root', 'Middle', 'Coin']);
      // Only the one that was looked for reads as a result.
      expect([for (final r in tree.rows) r.isMatch], [false, false, true]);
    });

    test('a search opens what it finds, whatever was shut', () {
      final root = node('Root');
      node('Coin', under: root);

      final tree = build(
        expanded: const {},
        filter: const TreeFilter(text: 'coin'),
      );

      expect(names(tree), ['Root', 'Coin']);
    });

    test('by component, by tag, and both at once', () {
      node('Plain');
      final tagged = node('Enemy', tag: 'enemy');
      world.createEntityWithComponents([
        TransformComponent(),
        RectangleComponent(width: 8, height: 8),
      ], name: 'Drawn');

      expect(names(build(filter: const TreeFilter(tag: 'enemy'))), ['Enemy']);
      expect(
        names(
          build(filter: const TreeFilter(componentType: 'RectangleComponent')),
        ),
        ['Drawn'],
      );
      expect(
        names(
          build(
            filter: const TreeFilter(tag: 'enemy', text: 'nothing'),
          ),
        ),
        isEmpty,
      );
      expect(tagged.isActive, isTrue);
    });

    test('only what something is wrong with', () {
      node('Fine');
      final broken = node('Broken');

      expect(
        names(
          build(
            filter: const TreeFilter(problems: true),
            withProblems: {broken.id},
          ),
        ),
        ['Broken'],
      );
    });

    test('an empty filter is not a filter', () {
      node('A');
      expect(const TreeFilter().isEmpty, isTrue);
      expect(const TreeFilter(text: '   ').isEmpty, isTrue);
      expect(const TreeFilter(text: 'a').isEmpty, isFalse);
      expect(names(build(filter: const TreeFilter(text: '  '))), ['A']);
    });
  });

  group('while the game is playing', () {
    test('what the game spawned is listed apart, and marked', () {
      final authored = node('Platform');
      final spawned = node('Bullet');

      final tree = build(authored: {authored.id});

      expect(names(tree), ['Platform', 'Bullet']);
      expect(tree.runtimeAt, 1);
      expect(tree.rows[0].isRuntime, isFalse);
      expect(tree.rows[1].isRuntime, isTrue);
      expect(spawned.isActive, isTrue);
    });

    test('a spawned thing brings its own children with it', () {
      final authored = node('Platform');
      final spawned = node('Enemy');
      node('Weapon', under: spawned);

      final tree = build(authored: {authored.id});

      expect(names(tree), ['Platform', 'Enemy', 'Weapon']);
      expect(tree.rows.last.isRuntime, isTrue);
      expect(tree.rows.last.depth, 1);
    });

    test('with nothing spawned there is no section', () {
      final a = node('A');
      expect(build(authored: {a.id}).runtimeAt, isNull);
      // And with no play under way at all.
      expect(build().runtimeAt, isNull);
    });
  });

  test('finding a row by entity', () {
    final root = node('Root');
    final child = node('Child', under: root);

    final tree = build();

    expect(tree.indexOf(child.id), 1);
    expect(tree.indexOf(9999), -1);
    expect(tree.length, 2);
    expect(SceneTree.empty.isEmpty, isTrue);
  });
}
