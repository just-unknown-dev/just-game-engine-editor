/// Undoable edits to the shape of a scene: who is under whom, in what
/// order, and what things are called.
///
/// The scene tree used to make these changes directly on the world, so
/// nothing it did could be undone. Each one is a command now, which is
/// also what makes a drag that re-parents *and* re-orders a single step.
library;

import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../serialization/scene_codec.dart';
import '../state/editor_scene_state.dart';
import '../../ui/level_designer/state/editor_history.dart';

/// Where an entity sat: its parent (by id) and its place among its
/// siblings, or among the roots.
class HierarchySlot {
  const HierarchySlot({required this.parentId, required this.index});

  /// The parent it was under, or null for a root.
  final jge.EntityId? parentId;

  /// Its place in that parent's children, or among the scene's roots.
  final int index;

  /// Where [entity] is now.
  factory HierarchySlot.of(
    jge.Entity entity, {
    required jge.World world,
    required EditorSceneState sceneState,
  }) {
    final parentId = entity.getComponent<jge.ParentComponent>()?.parentId;
    if (parentId == null) {
      return HierarchySlot(
        parentId: null,
        index: sceneState.rootIndexOf(entity.id),
      );
    }
    final children = world
        .getEntity(parentId)
        ?.getComponent<jge.ChildrenComponent>();
    return HierarchySlot(
      parentId: parentId,
      index: children?.childIds.indexOf(entity.id) ?? -1,
    );
  }

  @override
  String toString() => 'HierarchySlot($parentId, $index)';
}

/// Moves [entity] into a slot, detaching it from wherever it is.
///
/// One function so that re-parenting, re-ordering, grouping and the undo
/// of a delete all place an entity the same way — there is only one
/// description of what "being somewhere in the tree" means.
void placeEntity(
  jge.Entity entity, {
  required jge.World world,
  required EditorSceneState sceneState,
  required HierarchySlot slot,
}) {
  detachEntity(entity, world: world, sceneState: sceneState);

  final parentId = slot.parentId;
  if (parentId == null) {
    entity.getComponent<jge.ParentComponent>()?.parentId = null;
    sceneState.moveRoot(
      entity.id,
      slot.index < 0 ? sceneState.rootOrder(world).length : slot.index,
    );
    return;
  }

  final parent = world.getEntity(parentId);
  if (parent == null) return;

  // The child keeps its place on screen: the offset is measured against
  // the new parent, as the scene tree's re-parent has always done.
  final childT = entity.getComponent<jge.TransformComponent>();
  final parentT = parent.getComponent<jge.TransformComponent>();
  final localOffset = (childT != null && parentT != null)
      ? jge.Vector3.fromXY(
          childT.position.x - parentT.position.x,
          childT.position.y - parentT.position.y,
        )
      : jge.Vector3.zero();

  final existing = entity.getComponent<jge.ParentComponent>();
  if (existing != null) {
    existing
      ..parentId = parent.id
      ..localOffset = localOffset;
  } else {
    entity.addComponent(
      jge.ParentComponent(parentId: parent.id, localOffset: localOffset),
    );
  }

  var children = parent.getComponent<jge.ChildrenComponent>();
  if (children == null) {
    children = jge.ChildrenComponent();
    parent.addComponent(children);
  }
  final ids = children.childIds..remove(entity.id);
  ids.insert(
    slot.index < 0 ? ids.length : slot.index.clamp(0, ids.length),
    entity.id,
  );
}

/// Takes [entity] out of whatever holds it, leaving it parentless.
void detachEntity(
  jge.Entity entity, {
  required jge.World world,
  required EditorSceneState sceneState,
}) {
  final parentId = entity.getComponent<jge.ParentComponent>()?.parentId;
  if (parentId != null) {
    world
        .getEntity(parentId)
        ?.getComponent<jge.ChildrenComponent>()
        ?.removeChild(entity.id);
  }
  entity.getComponent<jge.ParentComponent>()?.parentId = null;
}

/// Whether [candidate] is [entity] or somewhere under it.
///
/// What stops a parent being dropped into its own child, which would make
/// a loop nothing could draw or save.
bool isSelfOrDescendant(
  jge.Entity candidate,
  jge.Entity entity, {
  required jge.World world,
}) {
  if (candidate.id == entity.id) return true;
  final children = entity.getComponent<jge.ChildrenComponent>();
  if (children == null) return false;
  for (final id in children.childIds) {
    final child = world.getEntity(id);
    if (child == null) continue;
    if (isSelfOrDescendant(candidate, child, world: world)) return true;
  }
  return false;
}

/// Moves entities to a new place in the tree, as one undoable step.
///
/// Takes a list so that dragging a selection is one command rather than
/// one per entity, and so undo puts every one of them back at once.
class ReparentCommand extends EditorCommand {
  ReparentCommand({
    required this.label,
    required this.world,
    required this.sceneState,
    required List<jge.Entity> entities,
    required this.parent,
    this.index,
  }) : _entities = [
         // An entity whose own parent is also moving comes along with it;
         // moving both would take it out of its parent on the way.
         for (final e in entities)
           if (!entities.any(
             (other) =>
                 other.id != e.id && isSelfOrDescendant(e, other, world: world),
           ))
             e,
       ] {
    _before = [
      for (final e in _entities)
        HierarchySlot.of(e, world: world, sceneState: sceneState),
    ];
  }

  @override
  final String label;

  final jge.World world;
  final EditorSceneState sceneState;
  final List<jge.Entity> _entities;

  /// Where they are going; null moves them to the top level.
  final jge.Entity? parent;

  /// Where among that parent's children; null puts them last.
  final int? index;

  late final List<HierarchySlot> _before;

  /// Whether this would make a loop, or move something into itself.
  bool get isValid {
    if (_entities.isEmpty) return false;
    final target = parent;
    if (target == null) return true;
    return !_entities.any((e) => isSelfOrDescendant(target, e, world: world));
  }

  @override
  void redo() {
    if (!isValid) return;
    var at = index;
    for (final entity in _entities) {
      placeEntity(
        entity,
        world: world,
        sceneState: sceneState,
        slot: HierarchySlot(parentId: parent?.id, index: at ?? -1),
      );
      if (at != null) at++;
    }
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  void undo() {
    // Backwards, so each one lands on the index it had while the ones
    // after it are still to be put back.
    for (var i = _entities.length - 1; i >= 0; i--) {
      placeEntity(
        _entities[i],
        world: world,
        sceneState: sceneState,
        slot: _before[i],
      );
    }
    sceneState
      ..markDirty()
      ..refresh();
  }
}

/// Moves one entity among its siblings, or among the roots.
class ReorderCommand extends EditorCommand {
  ReorderCommand({
    required this.label,
    required this.world,
    required this.sceneState,
    required this.entity,
    required this.index,
  }) : _before = HierarchySlot.of(entity, world: world, sceneState: sceneState);

  @override
  final String label;

  final jge.World world;
  final EditorSceneState sceneState;
  final jge.Entity entity;

  /// Where it is going among its siblings.
  final int index;

  final HierarchySlot _before;

  @override
  void redo() => _move(index);

  @override
  void undo() => _move(_before.index);

  void _move(int to) {
    placeEntity(
      entity,
      world: world,
      sceneState: sceneState,
      slot: HierarchySlot(parentId: _before.parentId, index: to),
    );
    sceneState
      ..markDirty()
      ..refresh();
  }
}

/// Renames an entity.
///
/// Names are how a scene file records who a child's parent is, so two
/// entities sharing one silently breaks the hierarchy on the next load.
/// [RenameCommand.isAvailable] is what the tree asks before it commits.
class RenameCommand extends EditorCommand {
  RenameCommand({
    required this.sceneState,
    required this.entity,
    required this.name,
  }) : _before = entity.name ?? '';

  @override
  String get label => 'Rename to $name';

  final EditorSceneState sceneState;
  final jge.Entity entity;
  final String name;
  final String _before;

  /// Whether [name] is free for [entity] in [world].
  static bool isAvailable(
    String name,
    jge.Entity entity, {
    required jge.World world,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    for (final other in world.entities) {
      if (other.id == entity.id) continue;
      if (other.name == trimmed) return false;
    }
    return true;
  }

  @override
  void redo() => _apply(name.trim());

  @override
  void undo() => _apply(_before);

  void _apply(String value) {
    sceneState.renameEntity(entity, value);
    sceneState
      ..markDirty()
      ..refresh();
  }
}

/// Whether an entity is on or off in the game.
///
/// Editor-only hiding is a different thing entirely — this one is saved
/// and the game honours it.
class SetEnabledCommand extends EditorCommand {
  SetEnabledCommand({
    required this.sceneState,
    required this.entity,
    required this.enabled,
  }) : _before = entity.isActive;

  @override
  String get label => enabled
      ? 'Enable ${entity.name ?? 'entity'}'
      : 'Disable ${entity.name ?? 'entity'}';

  final EditorSceneState sceneState;
  final jge.Entity entity;
  final bool enabled;
  final bool _before;

  @override
  void redo() => _apply(enabled);

  @override
  void undo() => _apply(_before);

  void _apply(bool value) {
    entity.isActive = value;
    sceneState
      ..markDirty()
      ..refresh();
  }
}

/// Puts entities inside a new group entity.
///
/// One command rather than a create and a move stitched together: those
/// capture what they need when they are *built*, and a group's children
/// move after the group exists. Undo takes the children back out and
/// destroys the group; redo makes a fresh one, so the command survives
/// being undone and redone even though ids are handed out again.
class GroupCommand extends EditorCommand {
  GroupCommand({
    required this.world,
    required this.sceneState,
    required List<jge.Entity> entities,
    required this.name,
    required this.position,
  }) : _entities = List.of(entities) {
    _before = [
      for (final e in _entities)
        HierarchySlot.of(e, world: world, sceneState: sceneState),
    ];
  }

  @override
  String get label =>
      'Group ${_entities.length} entit${_entities.length == 1 ? 'y' : 'ies'}';

  final jge.World world;
  final EditorSceneState sceneState;
  final List<jge.Entity> _entities;

  /// What the group is called; the same name on a redo, so anything that
  /// refers to it by name still does.
  final String name;

  /// Where the group sits — the middle of what it holds.
  final jge.Vector3 position;

  late final List<HierarchySlot> _before;

  /// The group as it stands, or null while undone.
  jge.Entity? group;

  @override
  void redo() {
    final made = world.createEntityWithComponents([
      jge.TransformComponent(
        position: jge.Vector3(position.x, position.y, position.z),
      ),
      jge.ChildrenComponent(),
    ], name: name);
    sceneState.registerEntity(made);
    group = made;
    for (final entity in _entities) {
      placeEntity(
        entity,
        world: world,
        sceneState: sceneState,
        slot: HierarchySlot(parentId: made.id, index: -1),
      );
    }
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  void undo() {
    for (var i = _entities.length - 1; i >= 0; i--) {
      placeEntity(
        _entities[i],
        world: world,
        sceneState: sceneState,
        slot: _before[i],
      );
    }
    final made = group;
    if (made != null) {
      detachEntity(made, world: world, sceneState: sceneState);
      sceneState.removeEntityNode(made.id);
      world.destroyEntity(made);
      group = null;
    }
    sceneState
      ..markDirty()
      ..refresh();
  }
}

/// Takes a group apart: its children move up into its place, and the
/// empty group goes.
class UngroupCommand extends EditorCommand {
  UngroupCommand({
    required this.world,
    required this.sceneState,
    required jge.Entity group,
    required this.codec,
  }) : _name = group.name ?? 'group',
       _components = [for (final c in group.components) ?codec.encode(c)],
       _slot = HierarchySlot.of(group, world: world, sceneState: sceneState),
       _children = [
         for (final id in List.of(
           group.getComponent<jge.ChildrenComponent>()?.childIds ??
               const <jge.EntityId>[],
         ))
           ?world.getEntity(id),
       ] {
    _group = group;
  }

  @override
  String get label => 'Ungroup $_name';

  final jge.World world;
  final EditorSceneState sceneState;
  final SceneCodec codec;

  final String _name;
  final List<Map<String, dynamic>> _components;
  final HierarchySlot _slot;
  final List<jge.Entity> _children;
  jge.Entity? _group;

  @override
  void redo() {
    // The children take the group's place, in their own order.
    var at = _slot.index;
    for (final child in _children) {
      placeEntity(
        child,
        world: world,
        sceneState: sceneState,
        slot: HierarchySlot(parentId: _slot.parentId, index: at),
      );
      if (at >= 0) at++;
    }
    final group = _group;
    if (group != null) {
      // Out of its parent's list before it goes, or the list keeps an id
      // that no longer belongs to anything.
      detachEntity(group, world: world, sceneState: sceneState);
      sceneState.removeEntityNode(group.id);
      world.destroyEntity(group);
      _group = null;
    }
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  void undo() {
    final components = <jge.Component>[];
    for (final json in _components) {
      final component = codec.decode(json);
      if (component != null) components.add(component);
    }
    final group = world.createEntityWithComponents(components, name: _name);
    sceneState.registerEntity(group);
    _group = group;
    placeEntity(group, world: world, sceneState: sceneState, slot: _slot);
    for (final child in _children) {
      placeEntity(
        child,
        world: world,
        sceneState: sceneState,
        slot: HierarchySlot(parentId: group.id, index: -1),
      );
    }
    sceneState
      ..markDirty()
      ..refresh();
  }
}
