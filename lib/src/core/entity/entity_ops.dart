import 'package:flutter/painting.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../ui/level_designer/state/editor_commands.dart';
import '../../ui/level_designer/state/editor_history.dart';
import '../scope/editor_scope.dart';
import '../state/editor_scene_state.dart';
import '../state/unique_namer.dart';

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
    required Camera Function() camera,
    this.onChanged,
  }) : _worldOf = world,
       cameraOf = camera;

  final EditorScope scope;
  final World Function() _worldOf;

  /// The world being edited. Read on use: an engine's world does not exist
  /// until it initialises, and the overlay builds before that.
  World get world => _worldOf();
  final EditorSceneState sceneState;

  /// The viewport camera: where a new entity is placed.
  final Camera Function() cameraOf;

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
  void createEntity() {
    if (!sceneState.hasScene) return;

    final camera = cameraOf();
    final spawnPos = camera.position;

    final entity = world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromOffset(spawnPos)),
    ], name: uniqueName('entity'));

    sceneState.registerEntity(entity);
    sceneState.selectEntity(entity);
    scope.log.log(
      'Created entity ${entity.name ?? entity.id}.',
      source: 'editor',
      category: 'entity',
    );
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

  /// Deletes everything selected, as one undoable action.
  void deleteSelection(EditorHistory history) {
    final targets = selectionEntities;
    if (targets.isEmpty) return;

    history.push(
      DeleteEntitiesCommand(
        label: targets.length == 1
            ? 'Delete ${targets.first.name ?? 'entity'}'
            : 'Delete ${targets.length} entities',
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

    final offset = Offset(gridSize, gridSize);
    final specs = targets
        .map(
          (entity) => EntitySpec.of(
            entity,
            scope.codec,
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
          EntitySpec.of(entity, scope.codec).translated(
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

    final camera = cameraOf();
    final spawnPos = camera.position;

    final groupEntity = world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromOffset(spawnPos)),
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

  /// Makes [child] a child of [newParent], auto-computing localOffset.
  void reparentEntity(Entity child, Entity newParent) {
    if (child.id == newParent.id) return;

    // Prevent circular parenting: newParent must not be a descendant of child.
    if (_isDescendantOf(newParent, child)) return;

    // Detach from existing parent first.
    final existing = child.getComponent<ParentComponent>();
    if (existing?.parentId != null) {
      final oldParent = world.getEntity(existing!.parentId!);
      oldParent?.getComponent<ChildrenComponent>()?.removeChild(child.id);
    }

    // Compute localOffset so the child keeps its world position.
    final childT = child.getComponent<TransformComponent>();
    final parentT = newParent.getComponent<TransformComponent>();
    final localOffset = (childT != null && parentT != null)
        ? Vector3.fromXY(
            childT.position.x - parentT.position.x,
            childT.position.y - parentT.position.y,
          )
        : Vector3.zero();

    // Set ParentComponent on child.
    if (existing != null) {
      existing.parentId = newParent.id;
      existing.localOffset = localOffset;
    } else {
      child.addComponent(
        ParentComponent(parentId: newParent.id, localOffset: localOffset),
      );
    }

    // Ensure parent has ChildrenComponent.
    if (!newParent.hasComponent<ChildrenComponent>()) {
      newParent.addComponent(ChildrenComponent());
    }
    newParent.getComponent<ChildrenComponent>()!.addChild(child.id);

    sceneState.markDirty();
    sceneState.refresh();
    scope.log.log(
      'Reparented ${child.name ?? child.id} under ${newParent.name ?? newParent.id}.',
      source: 'editor',
      category: 'hierarchy',
      mirrorToDebugger: false,
    );
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

  bool _isDescendantOf(Entity candidate, Entity ancestor) {
    final pc = candidate.getComponent<ParentComponent>();
    if (pc?.parentId == null) return false;
    if (pc!.parentId == ancestor.id) return true;
    final parent = world.getEntity(pc.parentId!);
    if (parent == null) return false;
    return _isDescendantOf(parent, ancestor);
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

  /// Spawns a new entity from the clipboard, offset from the camera centre.
  void pasteEntity() {
    if (!sceneState.hasClipboard) return;

    final components = (sceneState.clipboard.value ?? [])
        .map(scope.codec.decode)
        .whereType<Component>()
        .toList();

    final pastePosOffset = cameraOf().position + const Offset(30, 30);
    final pastePos = Vector3.fromOffset(pastePosOffset);

    final transform = components.whereType<TransformComponent>().firstOrNull;
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
