import 'package:flutter/painting.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';

/// Creates, deletes, groups, re-parents and copies entities in the world
/// being edited, keeping [sceneState] in step.
///
/// The selection operations take the designer's [EditorHistory] so each is
/// one undo step; the rest edit the world directly, as the scene tree always
/// has.
class EntityOps {
  EntityOps({
    required this.scope,
    required World Function() world,
    required this.sceneState,
    required EditorView Function() camera,
    this.onChanged,
  }) : _worldOf = world,
       cameraOf = camera;

  final EditorScope scope;
  final World Function() _worldOf;

  /// The world being edited. Read on use: an engine's world does not exist
  /// until it initialises, and the overlay builds before that.
  World get world => _worldOf();
  final EditorSceneState sceneState;

  /// The editor's view: a new entity is placed where it looks.
  final EditorView Function() cameraOf;

  /// Called after an edit the scene state does not itself announce.
  final VoidCallback? onChanged;

  /// Generates a `prefix_N` name that doesn't collide with any currently
  /// live entity.
  ///
  /// Using the live entity count as `N` (the old approach) collides as soon
  /// as an entity is deleted and a new one created afterwards — e.g. delete
  /// `entity_1` out of `entity_0`/`entity_1`/`entity_2` and the next create
  /// (count now 2) is named `entity_2`, duplicating the survivor. Duplicate
  /// names silently corrupt [openScene]'s name-keyed parent/child relinking
  /// on the next scene load.
  late final UniqueNamer uniqueName = UniqueNamer(
    () => world
        .query([TransformComponent])
        .map((e) => e.name)
        .whereType<String>(),
  );

  /// Creates a new entity at the camera centre, adds a visible
  /// [RectangleComponent] so it immediately appears on canvas, selects it,
  /// and registers it in the authoring scene graph.
  /// Makes an empty entity, at [at] in world coordinates when given — a
  /// right click on the level means "one of these, here".
  ///
  /// [point] places it in space (a 3-D scene's ground under the pointer)
  /// and wins over [at]; with neither it goes where the view is looking.
  void createEntity({Offset? at, Vector3? point}) {
    if (!sceneState.hasScene) return;

    final spawnPos =
        point ??
        (at != null ? Vector3.fromOffset(at) : cameraOf().focus);

    final entity = world.createEntityWithComponents([
      TransformComponent(position: Vector3.copy(spawnPos)),
    ], name: uniqueName('entity'));

    sceneState.registerEntity(entity);
    sceneState.selectEntity(entity);
    scope.log.log(
      'Created entity ${entity.name ?? entity.id}.',
      source: 'editor',
      category: 'entity',
    );
  }

  /// Renames [entity], refusing a name something else already has.
  ///
  /// Returns false when the name is taken, so the row can say so and keep
  /// the box open. Names are how a scene file records who a child's parent
  /// is, and two entities sharing one quietly breaks the hierarchy the
  /// next time the scene is loaded.
  bool renameEntity(Entity entity, String name) {
    final trimmed = name.trim();
    if (trimmed == entity.name) return true;
    if (!RenameCommand.isAvailable(trimmed, entity, world: world)) {
      return false;
    }
    scope.history.push(
      RenameCommand(sceneState: sceneState, entity: entity, name: trimmed),
    );
    onChanged?.call();
    return true;
  }

  /// Turns everything selected into one group, as an undoable step.
  Entity? groupSelection() {
    final targets = selectionEntities;
    if (targets.isEmpty || !sceneState.hasScene) return null;

    // Where the group goes: the middle of what it holds, so moving it
    // afterwards turns them about something sensible.
    final sum = Vector3.zero();
    var counted = 0;
    for (final entity in targets) {
      final t = entity.getComponent<TransformComponent>();
      if (t == null) continue;
      sum.add(t.position);
      counted++;
    }
    final centre = counted == 0
        ? cameraOf().focus
        : (sum..scale(1 / counted));

    final command = GroupCommand(
      world: world,
      sceneState: sceneState,
      entities: targets,
      name: uniqueName('group'),
      position: centre,
    );
    scope.history.push(command);

    final group = command.group;
    sceneState.clearMultiSelection();
    if (group != null) sceneState.selectEntity(group);
    sceneState.refresh();
    onChanged?.call();
    return group;
  }

  /// Takes a group apart: its children move up to where it was, and the
  /// empty group goes.
  void ungroup(Entity group) {
    final children = group.getComponent<ChildrenComponent>()?.childIds;
    if (children == null || children.isEmpty) return;
    scope.history.push(
      UngroupCommand(
        world: world,
        sceneState: sceneState,
        group: group,
        codec: scope.codec,
      ),
    );
    sceneState.refresh();
    onChanged?.call();
  }

  /// Entities covered by the current selection: the multi-selection when there
  /// is one, otherwise just the primary selection.
  List<Entity> get selectionEntities {
    final ids = sceneState.multiSelectedIds.value;
    if (ids.isNotEmpty) {
      return ids
          .map(world.getEntity)
          .whereType<Entity>()
          .where((e) => e.isActive)
          .toList();
    }
    final selected = sceneState.selectedEntity.value;
    return selected == null ? const [] : [selected];
  }

  static String _describe(List<Entity> entities) => entities.length == 1
      ? entities.single.name ?? 'entity'
      : '${entities.length} entities';

  /// Asks whether to delete what [what] names — `'Player'`, `'3 entities'`
  /// — when the settings want deletes confirmed. Set by the overlay, which
  /// has somewhere to ask; without it nothing is asked.
  Future<bool> Function(String what)? confirmDelete;

  /// Deletes everything selected as one undoable action — once confirmed,
  /// when the settings ask for that.
  void deleteSelection(EditorHistory history) {
    final targets = selectionEntities;
    if (targets.isEmpty) return;
    final ask = confirmDelete;
    if (ask == null || !scope.prefs.settings.value.confirmDelete) {
      _delete(history, targets);
      return;
    }
    ask(_describe(targets)).then((yes) {
      final alive = [
        for (final e in targets)
          if (e.isAlive) e,
      ];
      if (yes && alive.isNotEmpty) _delete(history, alive);
    });
  }

  void _delete(EditorHistory history, List<Entity> targets) {
    history.push(
      DeleteEntitiesCommand(
        label: 'Delete ${_describe(targets)}',
        world: world,
        sceneState: sceneState,
        entities: targets,
        codec: scope.codec,
      ),
    );
  }

  /// Duplicates everything selected, offset by one grid cell so the copies are
  /// visible rather than hidden exactly behind the originals.
  void duplicateSelection(EditorHistory history, {required double gridSize}) {
    final targets = selectionEntities;
    if (targets.isEmpty) return;

    // In space a metre along X: a grid cell of pixels would be far away.
    final offset = cameraOf().isPlanar
        ? Offset(gridSize, gridSize)
        : const Offset(1, 0);
    final specs = targets
        .map(
          (entity) => EntitySpec.of(
            entity,
            scope.codec,
            world: world,
          ).translated(offset, newName: uniqueName(_baseName(entity.name))),
        )
        .toList();

    history.push(
      CreateEntitiesCommand(
        label:
            'Duplicate ${targets.length} entit'
            '${targets.length == 1 ? 'y' : 'ies'}',
        world: world,
        sceneState: sceneState,
        specs: specs,
        onCreated: (created) {
          sceneState.clearMultiSelection();
          for (final entity in created) {
            sceneState.toggleMultiSelect(entity);
          }
          if (created.isNotEmpty) sceneState.selectEntity(created.first);
        },
      ),
    );
  }

  /// Repeats the selection [count] times, each copy [step] further along.
  ///
  /// Blocking out a staircase or a row of pillars by hand is the kind of
  /// repetitive work a level editor should be doing for you.
  void arraySelection(
    EditorHistory history, {
    required int count,
    required Offset step,
  }) {
    final targets = selectionEntities;
    if (targets.isEmpty || count < 1) return;

    final specs = <EntitySpec>[];
    for (var i = 1; i <= count; i++) {
      for (final entity in targets) {
        specs.add(
          EntitySpec.of(entity, scope.codec, world: world).translated(
            step * i.toDouble(),
            newName: uniqueName(_baseName(entity.name)),
          ),
        );
      }
    }

    history.push(
      CreateEntitiesCommand(
        label: 'Array x$count',
        world: world,
        sceneState: sceneState,
        specs: specs,
      ),
    );
  }

  /// Strips any trailing `_12` from a generated name, so duplicating
  /// `Platform_3` yields `Platform_4` rather than `Platform_3_1`.
  String _baseName(String? name) {
    if (name == null || name.isEmpty) return 'entity';
    final match = RegExp(r'^(.*?)_\d+$').firstMatch(name);
    return match?.group(1) ?? name;
  }

  /// Destroys [entity] from the ECS world and removes its authoring node.
  void deleteEntity(Entity entity) {
    // Clean up parent link before destroying.
    detachFromParent(entity);
    // Detach all children so they become root entities.
    final children = entity.getComponent<ChildrenComponent>();
    if (children != null) {
      for (final childId in List.of(children.childIds)) {
        final child = world.getEntity(childId);
        if (child != null) detachFromParent(child);
      }
    }
    sceneState.removeEntityNode(entity.id);
    world.destroyEntity(entity);
    scope.log.log(
      'Deleted entity ${entity.name ?? entity.id}.',
      source: 'editor',
      category: 'entity',
      level: DebuggerLogLevel.warning,
    );
    onChanged?.call();
  }

  // ── Group operations ──────────────────────────────────────────────────────

  /// Creates an empty group entity and optionally adds [children] to it.
  ///
  /// When [children] is null and a multi-selection is active, all
  /// multi-selected entities are grouped automatically.
  void createGroup({List<Entity>? children}) {
    if (!sceneState.hasScene) return;

    final spawnPos = cameraOf().focus;

    final groupEntity = world.createEntityWithComponents([
      TransformComponent(position: spawnPos),
      ChildrenComponent(),
    ], name: uniqueName('group'));

    sceneState.registerEntity(groupEntity);

    final targets =
        children ??
        (sceneState.hasMultiSelection
            ? sceneState.multiSelectedIds.value
                  .map(world.getEntity)
                  .whereType<Entity>()
                  .toList()
            : null);

    if (targets != null) {
      for (final child in targets) {
        reparentEntity(child, groupEntity);
      }
    }

    sceneState.clearMultiSelection();
    sceneState.selectEntity(groupEntity);
    sceneState.refresh();
    scope.log.log(
      'Created group ${groupEntity.name ?? groupEntity.id}.',
      source: 'editor',
      category: 'group',
    );
  }

  /// Moves [moved] to just before or after [anchor] among its siblings.
  ///
  /// Sibling order is what a row or a column lays its children out in, and
  /// it is kept by the order the scene file is written in — so this is a
  /// real edit, not a view.
  ///
  /// Only within a parent: the entities at the root of a scene have no
  /// list to be ordered in.
  void reorderEntity(Entity moved, Entity anchor, {required bool before}) {
    if (moved.id == anchor.id) return;
    final parentId = anchor.getComponent<ParentComponent>()?.parentId;
    final parent = parentId == null ? null : world.getEntity(parentId);

    // Where the anchor sits among the things it shares a level with.
    final siblings = parent == null
        ? sceneState.rootOrder(world)
        : parent.getComponent<ChildrenComponent>()?.childIds ??
              const <EntityId>[];
    var at = siblings.indexOf(anchor.id);
    if (at < 0) return;
    if (!before) at++;
    // Moving something that is already above the anchor shifts the target
    // down by the gap it leaves behind.
    final from = siblings.indexOf(moved.id);
    if (from >= 0 && from < at) at--;

    final sameLevel =
        moved.getComponent<ParentComponent>()?.parentId == parentId;
    if (sameLevel) {
      scope.history.push(
        ReorderCommand(
          label:
              'Move ${moved.name ?? moved.id} '
              '${before ? 'before' : 'after'} ${anchor.name ?? anchor.id}',
          world: world,
          sceneState: sceneState,
          entity: moved,
          index: at,
        ),
      );
    } else {
      reparentAll([moved], parent, index: at);
    }
    onChanged?.call();
  }

  /// Moves [entity] one place up or down among the things it sits with.
  void nudgeOrder(Entity entity, {required bool up}) {
    final parentId = entity.getComponent<ParentComponent>()?.parentId;
    final parent = parentId == null ? null : world.getEntity(parentId);
    final siblings = parent == null
        ? sceneState.rootOrder(world)
        : parent.getComponent<ChildrenComponent>()?.childIds ??
              const <EntityId>[];
    final at = siblings.indexOf(entity.id);
    if (at < 0) return;
    final to = up ? at - 1 : at + 1;
    if (to < 0 || to >= siblings.length) return;
    scope.history.push(
      ReorderCommand(
        label: 'Move ${entity.name ?? entity.id} ${up ? 'up' : 'down'}',
        world: world,
        sceneState: sceneState,
        entity: entity,
        index: to,
      ),
    );
    onChanged?.call();
  }

  /// Makes [child] a child of [newParent], as one undoable step. It keeps
  /// its place in the world; its local transform is worked out from it.
  ///
  /// [index] puts it at a place among the new parent's children; without
  /// one it goes last.
  void reparentEntity(Entity child, Entity newParent, {int? index}) {
    final command = ReparentCommand(
      label:
          'Move ${child.name ?? child.id} into '
          '${newParent.name ?? newParent.id}',
      world: world,
      sceneState: sceneState,
      entities: [child],
      parent: newParent,
      index: index,
    );
    if (!command.isValid) return;
    scope.history.push(command);
    onChanged?.call();
    scope.log.log(
      'Reparented ${child.name ?? child.id} under '
      '${newParent.name ?? newParent.id}.',
      source: 'editor',
      category: 'hierarchy',
      mirrorToDebugger: false,
    );
  }

  /// Moves [entities] under [parent] — or to the top level when it is
  /// null — as one undoable step. Into a level map with [mapLayer], onto
  /// that layer of it.
  void reparentAll(
    List<Entity> entities,
    Entity? parent, {
    int? index,
    int? mapLayer,
  }) {
    if (entities.isEmpty) return;
    final command = ReparentCommand(
      label: entities.length == 1
          ? 'Move ${entities.single.name ?? 'entity'}'
          : 'Move ${entities.length} entities',
      world: world,
      sceneState: sceneState,
      entities: entities,
      parent: parent,
      index: index,
      mapLayer: mapLayer,
    );
    if (!command.isValid) return;
    scope.history.push(command);
    onChanged?.call();
  }

  /// Removes [child] from its parent, making it a root entity.
  void detachFromParent(Entity child) {
    final pc = child.getComponent<ParentComponent>();
    if (pc?.parentId == null) return;

    final parentEntity = world.getEntity(pc!.parentId!);
    parentEntity?.getComponent<ChildrenComponent>()?.removeChild(child.id);

    child.removeComponent<ParentComponent>();

    sceneState.markDirty();
    sceneState.refresh();
    scope.log.log(
      'Detached ${child.name ?? child.id} from parent.',
      source: 'editor',
      category: 'hierarchy',
      mirrorToDebugger: false,
    );
  }

  /// Copies [entity]'s components to the clipboard as serialised JSON.
  void copyEntity(Entity entity) {
    final components = entity.components
        .map(scope.codec.encode)
        .whereType<Map<String, dynamic>>()
        .toList();
    sceneState.setClipboard(components);
    scope.log.log(
      'Copied entity ${entity.name ?? entity.id} to clipboard.',
      source: 'editor',
      category: 'clipboard',
      mirrorToDebugger: false,
    );
  }

  /// Spawns a new entity from the clipboard, offset from the camera centre —
  /// at [point] in space when given (a 3-D scene's ground under the
  /// pointer), else at [at]. A copied depth (z) is kept in 2-D.
  void pasteEntity({Offset? at, Vector3? point}) {
    if (!sceneState.hasClipboard) return;

    final components = (sceneState.clipboard.value ?? [])
        .map(scope.codec.decode)
        .whereType<Component>()
        .toList();

    final view = cameraOf();
    final copied = components.whereType<TransformComponent>().firstOrNull;
    final Vector3 pastePos;
    if (point != null) {
      pastePos = Vector3.copy(point);
    } else if (view.isPlanar || at != null) {
      final xy = at ?? view.position + const Offset(30, 30);
      pastePos = Vector3(xy.dx, xy.dy, copied?.position.z ?? 0);
    } else {
      pastePos = view.focus;
    }

    final transform = copied;
    if (transform != null) {
      transform.position.setFrom(pastePos);
    } else {
      components.insert(0, TransformComponent(position: pastePos));
    }

    final entity = world.createEntityWithComponents(
      components,
      name: uniqueName('entity'),
    );

    sceneState.registerEntity(entity);
    sceneState.selectEntity(entity);
    scope.log.log(
      'Pasted entity ${entity.name ?? entity.id} from clipboard.',
      source: 'editor',
      category: 'clipboard',
    );
    onChanged?.call();
  }
}
