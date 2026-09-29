import 'package:flutter/painting.dart' show Offset;
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../core/serialization/scene_codec.dart';
import '../../../core/entity/hierarchy_commands.dart';
import '../../../core/state/editor_scene_state.dart';
import 'editor_history.dart';

/// A single entity's transform, captured so it can be restored exactly.
///
/// Stores plain doubles rather than a reference to the live component: the
/// point is to survive the component being mutated afterwards.
class TransformSnapshot {
  const TransformSnapshot({
    required this.x,
    required this.y,
    required this.rotation,
    required this.scaleX,
    required this.scaleY,
  });

  /// Reads the current transform of [entity].
  factory TransformSnapshot.of(jge.Entity entity) {
    final t = entity.getComponent<jge.TransformComponent>()!;
    return TransformSnapshot(
      x: t.position.x,
      y: t.position.y,
      rotation: t.rotation,
      scaleX: t.scale.x,
      scaleY: t.scale.y,
    );
  }

  /// World X.
  final double x;

  /// World Y.
  final double y;

  /// Rotation in radians.
  final double rotation;

  /// Horizontal scale.
  final double scaleX;

  /// Vertical scale.
  final double scaleY;

  /// Writes this snapshot back onto [entity].
  void applyTo(jge.Entity entity) {
    final t = entity.getComponent<jge.TransformComponent>();
    if (t == null) return;
    t
      ..setPositionXY(x, y)
      ..rotation = rotation;
    t.scale.x = scaleX;
    t.scale.y = scaleY;
  }

  /// Whether [other] describes the same transform, within float noise.
  bool matches(TransformSnapshot other) =>
      (x - other.x).abs() < 1e-6 &&
      (y - other.y).abs() < 1e-6 &&
      (rotation - other.rotation).abs() < 1e-9 &&
      (scaleX - other.scaleX).abs() < 1e-9 &&
      (scaleY - other.scaleY).abs() < 1e-9;
}

/// Moves, rotates or scales one or more entities.
///
/// Built from before/after snapshots rather than a delta so undo restores the
/// exact prior transform instead of re-applying an inverse, which would drift
/// as float error accumulated over a long drag.
class TransformCommand extends EditorCommand {
  TransformCommand({
    required this.label,
    required this.entities,
    required this.before,
    required this.after,
    required this.sceneState,
    this.mergeKey,
  });

  @override
  final String label;

  /// Commands with the same non-null key fold into one undo step.
  ///
  /// Null — the default — never merges. Every gesture pushes exactly one
  /// command already, so merging by default only ever did harm: dragging a
  /// platform twice and pressing Ctrl+Z reverted both drags at once. A burst
  /// of arrow-key nudges is the case that wants merging, and it opts in.
  final Object? mergeKey;

  /// Entities affected, aligned index-for-index with [before] and [after].
  final List<jge.Entity> entities;

  /// Transforms as they were before the gesture.
  final List<TransformSnapshot> before;

  /// Transforms as they are after it.
  List<TransformSnapshot> after;

  /// Notified so panels and the canvas refresh.
  final EditorSceneState sceneState;

  @override
  void redo() => _apply(after);

  @override
  void undo() => _apply(before);

  void _apply(List<TransformSnapshot> snapshots) {
    for (var i = 0; i < entities.length; i++) {
      final entity = entities[i];
      if (!entity.isAlive) continue;
      snapshots[i].applyTo(entity);
      sceneState.syncEntityNode(entity);
    }
    sceneState
      ..markDirty()
      ..refresh();
  }

  /// Absorbs a later transform of the same entities with the same
  /// [mergeKey] — one undo step for a run of nudges, say.
  @override
  bool mergeWith(EditorCommand next) {
    if (next is! TransformCommand) return false;
    if (mergeKey == null || next.mergeKey != mergeKey) return false;
    if (next.entities.length != entities.length) return false;
    for (var i = 0; i < entities.length; i++) {
      if (!identical(entities[i], next.entities[i])) return false;
    }
    after = next.after;
    return true;
  }
}

/// Creates entities from component JSON, and destroys them again on undo.
///
/// Holds JSON rather than live entities because undo destroys them: on redo
/// there is nothing left to re-add, so the command has to be able to rebuild
/// them from scratch. An entity whose spec names a parent goes back under
/// it — found by name, as a scene file does, since ids are new each time.
class CreateEntitiesCommand extends EditorCommand {
  CreateEntitiesCommand({
    required this.label,
    required this.world,
    required this.sceneState,
    required this.specs,
    this.onCreated,
  });

  @override
  final String label;

  /// World the entities live in.
  final jge.World world;

  /// Notified so the scene tree and inspector refresh.
  final EditorSceneState sceneState;

  /// One entry per entity: its name and its serialized components.
  final List<EntitySpec> specs;

  /// Called with the freshly created entities, e.g. to select them.
  final void Function(List<jge.Entity> created)? onCreated;

  final List<jge.EntityId> _createdIds = [];

  /// Records entities that already exist as having been created by this
  /// command, for [EditorHistory.pushApplied].
  ///
  /// For gestures that create entities up front and keep editing them until
  /// release — Alt+drag duplicate — so the whole gesture is one undo step
  /// whose redo rebuilds the entities as they ended up, not as they started.
  factory CreateEntitiesCommand.adopting({
    required String label,
    required jge.World world,
    required EditorSceneState sceneState,
    required List<jge.Entity> entities,
    required SceneCodec codec,
    void Function(List<jge.Entity> created)? onCreated,
  }) {
    final command = CreateEntitiesCommand(
      label: label,
      world: world,
      sceneState: sceneState,
      specs: entities
          .map((e) => EntitySpec.of(e, codec, world: world))
          .toList(growable: false),
      onCreated: onCreated,
    );
    command._createdIds.addAll(entities.map((e) => e.id));
    return command;
  }

  @override
  void redo() {
    _createdIds.clear();
    final created = <jge.Entity>[];

    for (final spec in specs) {
      final components = spec.decode();
      if (components.isEmpty) continue;

      final entity = world.createEntityWithComponents(
        components,
        name: spec.name,
      );
      sceneState.registerEntity(entity);
      final parentName = spec.parentName;
      final parent = parentName == null
          ? null
          : world.findEntityByName(parentName);
      if (parent != null) {
        placeEntity(
          entity,
          world: world,
          sceneState: sceneState,
          slot: HierarchySlot(parentId: parent.id, index: spec.siblingIndex),
        );
      }
      _createdIds.add(entity.id);
      created.add(entity);
    }

    sceneState
      ..markDirty()
      ..refresh();
    onCreated?.call(created);
  }

  @override
  void undo() {
    // Last made first, so a child leaves its parent before the parent goes.
    for (final id in _createdIds.reversed) {
      final entity = world.getEntity(id);
      if (entity == null) continue;
      detachEntity(entity, world: world, sceneState: sceneState);
      sceneState.removeEntityNode(id);
      world.destroyEntity(entity);
    }
    _createdIds.clear();
    sceneState
      ..clearSelection()
      ..markDirty()
      ..refresh();
  }
}

/// Name plus serialized components — enough to rebuild one entity — and
/// where it goes in the tree.
class EntitySpec {
  const EntitySpec({
    required this.name,
    required this.componentsJson,
    required this.codec,
    this.parentName,
    this.siblingIndex = -1,
  });

  /// Captures [entity] as it currently stands, through [codec]. With
  /// [world], where it sits in the tree too: its parent, by name, and its
  /// place among that parent's children.
  factory EntitySpec.of(
    jge.Entity entity,
    SceneCodec codec, {
    jge.World? world,
  }) {
    final json = codec.encodeAll(entity.components);
    final parentId = entity.getComponent<jge.ParentComponent>()?.parentId;
    final parent = parentId == null ? null : world?.getEntity(parentId);
    return EntitySpec(
      name: entity.name,
      componentsJson: json,
      codec: codec,
      parentName: parent?.name,
      siblingIndex:
          parent?.getComponent<jge.ChildrenComponent>()?.childIds.indexOf(
            entity.id,
          ) ??
          -1,
    );
  }

  /// Entity name, or null for an unnamed entity.
  final String? name;

  /// The name of the entity it goes under, or null for a root. By name,
  /// because ids are handed out again when entities are rebuilt.
  final String? parentName;

  /// Its place among [parentName]'s children; -1 for after them all.
  final int siblingIndex;

  /// Serialized components, in attachment order.
  final List<Map<String, dynamic>> componentsJson;

  /// Turns [componentsJson] back into components: the scope's codec.
  final SceneCodec codec;

  /// Decodes the components. Anything with no definition is kept as it
  /// was saved (`UnknownComponents`), exactly as a scene load does.
  List<jge.Component> decode() => codec.decodeAll(componentsJson);

  /// Makes [entity] match this spec, in place.
  ///
  /// The entity keeps its id, so selection, the physics body bound to it and
  /// any history entry that refers to it all stay valid. Components the spec
  /// lacks are removed if they are part of the level format; runtime-only
  /// ones (the physics handle) are left to the systems that own them, which
  /// re-sync from what is written here.
  ///
  /// Where it is in the tree is not part of this: the entity's parent link
  /// and its list of children are left as they are. Decoded, they would be
  /// empty — they name entities by id — and a resize would cut a child
  /// loose, or an edit to a parent drop all of its children.
  void applyTo(jge.Entity entity) {
    final components = [
      for (final c in decode())
        if (!_isLink(c)) c,
    ];
    final kept = {for (final c in components) c.componentType};
    for (final c in entity.components.toList()) {
      if (_isLink(c)) continue;
      if (!kept.contains(c.componentType) && codec.canEncode(c)) {
        entity.removeComponentByType(c.componentType);
      }
    }
    for (final c in components) {
      entity.addComponent(c); // replaces the same component type
    }
    entity.name = name;
  }

  static bool _isLink(jge.Component c) =>
      c is jge.ParentComponent || c is jge.ChildrenComponent;

  /// A copy with a different name, for duplicate and array operations.
  EntitySpec renamed(String? newName) => EntitySpec(
    name: newName,
    componentsJson: componentsJson,
    codec: codec,
    parentName: parentName,
    siblingIndex: siblingIndex,
  );

  /// A copy that goes under [parent] — by name — at [index], or at the end.
  EntitySpec under(String? parent, {int index = -1}) => EntitySpec(
    name: name,
    componentsJson: componentsJson,
    codec: codec,
    parentName: parent,
    siblingIndex: index,
  );

  /// A copy shifted by [delta], for duplicate and array operations: under
  /// the same parent, just after the original.
  ///
  /// Decodes, moves the transform and re-encodes, so this knows nothing
  /// about how a position is spelled on disk — the codec does.
  EntitySpec translated(Offset delta, {String? newName}) {
    final shifted = <Map<String, dynamic>>[];
    for (final json in componentsJson) {
      final component = codec.decode(json);
      if (component is! jge.TransformComponent) {
        shifted.add(json);
        continue;
      }
      component.position = jge.Vector3(
        component.position.x + delta.dx,
        component.position.y + delta.dy,
        component.position.z,
      );
      shifted.add(codec.encode(component) ?? json);
    }
    return EntitySpec(
      name: newName ?? name,
      componentsJson: shifted,
      codec: codec,
      parentName: parentName,
      siblingIndex: siblingIndex < 0 ? -1 : siblingIndex + 1,
    );
  }
}

/// Destroys entities, and rebuilds them from their captured state on undo.
///
/// The capture has to happen before the entities are destroyed, so the command
/// snapshots in its constructor rather than in [redo].
class DeleteEntitiesCommand extends EditorCommand {
  DeleteEntitiesCommand({
    required this.label,
    required this.world,
    required this.sceneState,
    required List<jge.Entity> entities,
    required SceneCodec codec,
  }) {
    // The whole subtree: deleting a card and leaving its labels behind as
    // roots is not what anyone means by deleting the card. Captured
    // parent-first so undo can rebuild it from the top down.
    final ordered = <jge.Entity>[];
    void collect(jge.Entity entity) {
      if (ordered.any((e) => e.id == entity.id)) return;
      ordered.add(entity);
      final children = entity.getComponent<jge.ChildrenComponent>();
      if (children == null) return;
      for (final id in List.of(children.childIds)) {
        final child = world.getEntity(id);
        if (child != null) collect(child);
      }
    }

    for (final entity in entities) {
      collect(entity);
    }
    for (final entity in ordered) {
      _specs.add(EntitySpec.of(entity, codec));
      _ids.add(entity.id);
      // By name and index, because ids are handed out again when the
      // entities come back: what the file uses to say the same thing.
      _slots.add(
        _DeletedSlot(
          parentName: _parentNameOf(entity, world),
          index: HierarchySlot.of(
            entity,
            world: world,
            sceneState: sceneState,
          ).index,
        ),
      );
    }
  }

  static String? _parentNameOf(jge.Entity entity, jge.World world) {
    final parentId = entity.getComponent<jge.ParentComponent>()?.parentId;
    return parentId == null ? null : world.getEntity(parentId)?.name;
  }

  @override
  final String label;

  /// World the entities belong to.
  final jge.World world;

  /// Notified so panels refresh.
  final EditorSceneState sceneState;

  final List<EntitySpec> _specs = [];
  final List<jge.EntityId> _ids = [];
  final List<_DeletedSlot> _slots = [];

  @override
  void redo() {
    for (final id in _ids) {
      final entity = world.getEntity(id);
      if (entity == null) continue;
      detachEntity(entity, world: world, sceneState: sceneState);
      sceneState.removeEntityNode(id);
      world.destroyEntity(entity);
    }
    sceneState
      ..clearSelection()
      ..markDirty()
      ..refresh();
  }

  @override
  void undo() {
    final restored = <jge.Entity>[];
    for (final spec in _specs) {
      final components = spec.decode();
      if (components.isEmpty) {
        restored.add(jge.Entity(-1));
        continue;
      }
      final entity = world.createEntityWithComponents(
        components,
        name: spec.name,
      );
      sceneState.registerEntity(entity);
      restored.add(entity);
    }

    // Parents first, so a child is put back into a parent that exists.
    // Ids are new, so the link is made from the names that were saved —
    // the same thing a scene file records.
    for (var i = 0; i < restored.length; i++) {
      final entity = restored[i];
      if (entity.id < 0) continue;
      final slot = _slots[i];
      final parentName = slot.parentName;
      final parent = parentName == null
          ? null
          : world.findEntityByName(parentName);
      placeEntity(
        entity,
        world: world,
        sceneState: sceneState,
        slot: HierarchySlot(parentId: parent?.id, index: slot.index),
      );
    }

    sceneState
      ..markDirty()
      ..refresh();
  }
}

/// Where a deleted entity was, in terms that survive it being destroyed.
class _DeletedSlot {
  const _DeletedSlot({required this.parentName, required this.index});

  final String? parentName;
  final int index;
}

/// Changes one field of one component, using the editor descriptor's own
/// read/write closures.
///
/// Because every registered field already exposes a generic getter and setter,
/// this single command gives undo to every field of every component in the
/// inspector without a line of per-field work.
class ComponentFieldCommand extends EditorCommand {
  ComponentFieldCommand({
    required this.label,
    required this.component,
    required this.write,
    required this.before,
    required this.after,
    required this.sceneState,
  });

  @override
  final String label;

  /// The component being edited.
  final jge.Component component;

  /// The descriptor field's setter.
  final void Function(jge.Component component, Object? value) write;

  /// Value before the edit.
  final Object? before;

  /// Value after it.
  Object? after;

  /// Notified so the canvas and panels refresh.
  final EditorSceneState sceneState;

  @override
  void redo() => _apply(after);

  @override
  void undo() => _apply(before);

  void _apply(Object? value) {
    write(component, value);
    sceneState
      ..markDirty()
      ..refresh();
  }

  /// Collapses consecutive edits to the same field.
  ///
  /// Scrubbing a number field emits a value per pixel of drag; without this,
  /// nudging a width would fill the entire history.
  @override
  bool mergeWith(EditorCommand next) {
    if (next is! ComponentFieldCommand) return false;
    if (!identical(next.component, component)) return false;
    if (next.label != label) return false;
    after = next.after;
    return true;
  }
}

/// Adds a component to an entity.
class AddComponentCommand extends EditorCommand {
  AddComponentCommand({
    required this.entity,
    required this.component,
    required this.sceneState,
  });

  @override
  String get label => 'Add ${component.runtimeType}';

  /// The entity gaining the component.
  final jge.Entity entity;

  /// The component instance. Reused across undo/redo so any values the user
  /// has since typed into it survive an undo/redo round trip.
  final jge.Component component;

  /// Notified so the inspector refreshes.
  final EditorSceneState sceneState;

  @override
  void redo() {
    entity.addComponent(component);
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  void undo() {
    entity.removeComponentByType(component.componentType);
    sceneState
      ..markDirty()
      ..refresh();
  }
}

/// Removes a component from an entity.
class RemoveComponentCommand extends EditorCommand {
  RemoveComponentCommand({
    required this.entity,
    required this.component,
    required this.sceneState,
  });

  @override
  String get label => 'Remove ${component.runtimeType}';

  /// The entity losing the component.
  final jge.Entity entity;

  /// The removed component, kept so undo can put the same instance back with
  /// all of its configured values intact.
  final jge.Component component;

  /// Notified so the inspector refreshes.
  final EditorSceneState sceneState;

  @override
  void redo() {
    entity.removeComponentByType(component.componentType);
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  void undo() {
    entity.addComponent(component);
    sceneState
      ..markDirty()
      ..refresh();
  }
}

/// Rewrites entities in place between two captured states.
///
/// For edits that change more than a transform — a resize, a flip, a
/// replaced component — while keeping each entity itself: capture
/// [EntitySpec]s before, make the change, capture after, push this applied.
class EntityStateCommand extends EditorCommand {
  EntityStateCommand({
    required this.label,
    required this.world,
    required this.sceneState,
    required this.ids,
    required this.before,
    required this.after,
    this.mergeKey,
  }) : assert(ids.length == before.length && ids.length == after.length);

  /// Commands with the same non-null key fold into one undo step — a scrub
  /// of a number field, say, which commits on every pixel of drag.
  final Object? mergeKey;

  @override
  final String label;

  /// World the entities live in.
  final jge.World world;

  /// Notified so panels and the canvas refresh.
  final EditorSceneState sceneState;

  /// Entities affected, aligned with [before] and [after].
  final List<jge.EntityId> ids;

  /// State before the edit.
  final List<EntitySpec> before;

  /// State after it.
  List<EntitySpec> after;

  @override
  bool mergeWith(EditorCommand next) {
    if (mergeKey == null || next is! EntityStateCommand) return false;
    if (next.mergeKey != mergeKey || next.ids.length != ids.length) {
      return false;
    }
    for (var i = 0; i < ids.length; i++) {
      if (next.ids[i] != ids[i]) return false;
    }
    after = next.after;
    return true;
  }

  /// Whether anything actually changed — a command that changes nothing
  /// would make Ctrl+Z appear to do nothing.
  bool get changesAnything {
    for (var i = 0; i < ids.length; i++) {
      if (!_sameJson(before[i].componentsJson, after[i].componentsJson) ||
          before[i].name != after[i].name) {
        return true;
      }
    }
    return false;
  }

  @override
  void redo() => _apply(after);

  @override
  void undo() => _apply(before);

  void _apply(List<EntitySpec> specs) {
    for (var i = 0; i < ids.length; i++) {
      final entity = world.getEntity(ids[i]);
      if (entity == null || !entity.isAlive) continue;
      specs[i].applyTo(entity);
      sceneState.syncEntityNode(entity);
    }
    sceneState
      ..markDirty()
      ..refresh();
  }

  static bool _sameJson(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_sameJson(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameJson(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is num && b is num) return (a - b).abs() < 1e-9;
    return a == b;
  }
}

/// Several commands performed as one undo step.
///
/// Redone in order and undone in reverse, so each part sees the state the
/// previous one left — replacing an entity is a delete then a create.
class CompositeCommand extends EditorCommand {
  CompositeCommand({required this.label, required this.commands});

  @override
  final String label;

  /// The parts, in the order they are performed.
  final List<EditorCommand> commands;

  @override
  void redo() {
    for (final command in commands) {
      command.redo();
    }
  }

  @override
  void undo() {
    for (final command in commands.reversed) {
      command.undo();
    }
  }
}
