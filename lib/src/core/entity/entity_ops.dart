import 'package:flutter/painting.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';

import '../input/selection_pivot.dart';
import '../scope/editor_scope_services.dart';

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

  /// Places [prefab] at [at] in space — standing on the surface there when
  /// it knows how ([PrefabDefinition.buildAt]) — selected, as one undo
  /// step. What the 3-D designer's Place tool and the viewport menu's Add
  /// make.
  ///
  /// [align], [spin] and [size] set it down as [spawnPrefab] does.
  Entity placePrefab(
    PrefabDefinition prefab,
    SurfacePoint at, {
    bool align = false,
    double spin = 0,
    double size = 1,
  }) {
    final entity = spawnPrefab(prefab, at, align: align, spin: spin, size: size);
    recordPlaced([entity], 'Place ${prefab.name}');
    return entity;
  }

  /// Makes [prefab]'s entity on [at] without recording it — [recordPlaced]
  /// does, for one or a whole stroke of them.
  ///
  /// The prefab builds it upright (on a level surface where [align] is
  /// on); then, about the point, it is sized by [size] and turned — stood
  /// on the surface, its up along the surface's facing, when [align] is
  /// on — and spun [spin] degrees about its up.
  Entity spawnPrefab(
    PrefabDefinition prefab,
    SurfacePoint at, {
    bool align = false,
    double spin = 0,
    double size = 1,
  }) {
    // An instance of a prefab file: its entities, its top standing on the
    // surface as a shape would.
    if (prefab.instanceOf case final path?) {
      final top = scope.prefabInstances.library.loaded(path) == null
          ? null
          : scope.prefabInstances.build([
              scope.prefabInstances.entryFor(
                path,
                name: uniqueName(prefab.namePrefix ?? prefab.name),
                at: at.position,
                turn: Placement3D.turnFor(at, align: align, spinDegrees: spin),
                size: size,
              ),
            ]).firstOrNull;
      if (top != null) return top;
    }
    final components = Placement3D.posed(
      prefab,
      at,
      align: align,
      spin: spin,
      size: size,
    );
    final entity = world.createEntityWithComponents(
      components,
      name: uniqueName(prefab.namePrefix ?? prefab.id),
    );
    sceneState.syncEntityNode(entity);
    return entity;
  }

  /// Records [entities], made by [spawnPrefab], as one undo step named
  /// [label], and selects them.
  void recordPlaced(List<Entity> entities, String label) {
    if (entities.isEmpty) return;
    // Instances of prefab files are made again from their entries on redo;
    // everything else from what it is now.
    final tops = [
      for (final e in entities)
        if (e.hasComponent<PrefabInstanceComponent>()) e,
    ];
    if (tops.isNotEmpty) {
      final instances = scope.prefabInstances;
      final entries = [
        for (final top in tops)
          {
            'name': top.name,
            'prefab': instances.changesOf(top).block.toJson(),
          },
      ];
      final plain = [
        for (final e in entities)
          if (!e.hasComponent<PrefabInstanceComponent>()) e,
      ];
      var made = [for (final top in tops) ...instances.subtreeOf(top)];
      final plainCommand = plain.isEmpty
          ? null
          : CreateEntitiesCommand.adopting(
              label: label,
              world: world,
              sceneState: sceneState,
              entities: plain,
              codec: scope.codec,
            );
      scope.history.pushApplied(
        CallbackCommand(
          label: label,
          onRedo: () {
            plainCommand?.redo();
            made = instances.build(entries);
          },
          onUndo: () {
            for (final e in made.reversed) {
              if (!e.isAlive) continue;
              detachEntity(e, world: world, sceneState: sceneState);
              sceneState.removeEntityNode(e.id);
              world.destroyEntity(e);
            }
            plainCommand?.undo();
            sceneState
              ..markDirty()
              ..refresh();
          },
        ),
      );
      sceneState
        ..markDirty()
        ..refresh()
        ..selectEntity(entities.last);
      return;
    }
    sceneState
      ..markDirty()
      ..refresh()
      ..clearMultiSelection();
    if (entities.length > 1) {
      for (final e in entities) {
        sceneState.toggleMultiSelect(e);
      }
    }
    sceneState.selectEntity(entities.last);
    scope.history.pushApplied(
      CreateEntitiesCommand.adopting(
        label: label,
        world: world,
        sceneState: sceneState,
        entities: entities,
        codec: scope.codec,
      ),
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
    // afterwards turns them about something sensible — in space, the
    // middle of their base, so it stands where they stand.
    final sum = Vector3.zero();
    var counted = 0;
    for (final entity in targets) {
      final t = entity.getComponent<TransformComponent>();
      if (t == null) continue;
      sum.add(t.position);
      counted++;
    }
    var centre = counted == 0
        ? cameraOf().focus
        : (sum..scale(1 / counted));
    if (!cameraOf().isPlanar && counted > 0) {
      centre = SelectionPivot.of(targets, PivotMode3D.base);
    }

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
    final targets = _outermost(selectionEntities);
    if (targets.isEmpty) return;

    // In space a metre along X: a grid cell of pixels would be far away.
    // A duplicate of the last copies repeats how far they have been moved
    // from what they copied: duplicate, move it, duplicate again for a row.
    final offset =
        _repeatedOffset(targets) ??
        (cameraOf().isPlanar
            ? Vector3(gridSize, gridSize, 0)
            : Vector3(1, 0, 0));
    final from = [
      for (final e in targets)
        Vector3.copy(e.getComponent<TransformComponent>()?.position ?? Vector3.zero()),
    ];
    final specs = [
      for (final entity in targets)
        ..._copiesOf(entity, (t) => t.position.add(offset)),
    ];

    history.push(
      CreateEntitiesCommand(
        label:
            'Duplicate ${targets.length} entit'
            '${targets.length == 1 ? 'y' : 'ies'}',
        world: world,
        sceneState: sceneState,
        specs: specs,
        onCreated: (created) {
          // The copies of what was selected, not what is inside them.
          final copies = _outermost(created);
          _lastCopies = [for (final e in copies) e.id];
          _lastFrom = from;
          sceneState.clearMultiSelection();
          for (final entity in copies) {
            sceneState.toggleMultiSelect(entity);
          }
          if (copies.isNotEmpty) sceneState.selectEntity(copies.first);
        },
      ),
    );
  }

  // The last duplicate's copies and where what they copied stood.
  List<EntityId> _lastCopies = const [];
  List<Vector3> _lastFrom = const [];

  /// How far [targets] — when they are the last duplicate's copies — have
  /// been moved from what they copied; null for anything else, or copies
  /// left where they were made (that repeats the default step anyway).
  Vector3? _repeatedOffset(List<Entity> targets) {
    if (targets.length != _lastCopies.length) return null;
    final ids = {for (final e in targets) e.id};
    if (!_lastCopies.every(ids.contains)) return null;
    final first = world.getEntity(_lastCopies.first);
    final at = first?.getComponent<TransformComponent>()?.position;
    if (at == null) return null;
    final moved = at - _lastFrom.first;
    return moved.lengthSquared < 1e-12 ? null : moved;
  }

  /// Copies the selection as [spec] lays them out — in a row, a grid or
  /// round a circle — about [pivot], as one undo step. The copies are
  /// selected with the originals.
  void arraySelection3D(
    EditorHistory history,
    Array3DSpec spec,
    Vector3 pivot,
  ) {
    final targets = _outermost(selectionEntities);
    final steps = spec.steps(pivot);
    if (targets.isEmpty || steps.isEmpty) return;
    final specs = <EntitySpec>[
      for (final step in steps)
        for (final entity in targets)
          ..._copiesOf(entity, (t) {
            t.position.setFrom(step.apply(t.position));
            if (step.turnsItself) {
              final own = Quaternion.identity();
              t.rotationInto(own);
              t.setRotation(Quaternion.copy(step.turn)..multiply(own));
            }
          }),
    ];
    history.push(
      CreateEntitiesCommand(
        label: 'Array ${spec.mode.label.toLowerCase()} ×${spec.total}',
        world: world,
        sceneState: sceneState,
        specs: specs,
      ),
    );
  }

  /// A copy of [entity] and of everything inside it, each placed by
  /// [edit] — a group copied whole — with new names, the copies inside the
  /// copy. [entity]'s copy first, just after it; the rest under their
  /// copied parents, in order.
  List<EntitySpec> _copiesOf(
    Entity entity,
    void Function(TransformComponent transform) edit,
  ) {
    final renamed = <String, String>{};
    String copyName(Entity e) {
      final name = uniqueName(_baseName(e.name));
      if (e.name != null) renamed[e.name!] = name;
      return name;
    }

    final specs = [
      EntitySpec.of(entity, scope.codec, world: world)
          .transformed(edit, newName: copyName(entity)),
    ];
    for (final child in _descendantsOf(entity)) {
      final spec = EntitySpec.of(child, scope.codec, world: world);
      specs.add(
        spec
            .transformed(edit, newName: copyName(child))
            .under(renamed[spec.parentName] ?? spec.parentName),
      );
    }
    return specs;
  }

  /// Whether [entity] is a group: an empty entity holding others, there
  /// to move, hide and lock them together.
  bool isGroup(Entity entity) {
    final children = entity.getComponent<ChildrenComponent>()?.childIds;
    if (children == null || children.isEmpty) return false;
    return entity.components.every(
      (c) => c is TransformComponent || c is ParentComponent || c is ChildrenComponent,
    );
  }

  /// [entities] less anything inside another of them, which goes with it.
  List<Entity> _outermost(List<Entity> entities) {
    final ids = {for (final e in entities) e.id};
    bool inside(Entity e) {
      var parent = e.getComponent<ParentComponent>()?.parentId;
      for (var guard = 0; parent != null && guard < 64; guard++) {
        if (ids.contains(parent)) return true;
        parent = world.getEntity(parent)?.getComponent<ParentComponent>()?.parentId;
      }
      return false;
    }

    return [for (final e in entities) if (!inside(e)) e];
  }

  /// Drops each selected thing straight down onto what is under it — the
  /// first surface [below] finds along a ray down from the middle of its
  /// base, or else [plane] when that is below it — as one undo step.
  /// Things already resting, or with nothing under them, stay. Returns how
  /// many moved.
  int dropSelectionToGround({
    required SurfacePoint? Function(Ray3 ray, Set<Entity> ignore) below,
    WorkingPlane? plane,
  }) {
    final targets = _outermost(selectionEntities);
    final moved = <Entity>[], before = <TransformSnapshot>[];
    final box = Aabb3();
    for (final entity in targets) {
      final transform = entity.getComponent<TransformComponent>();
      if (transform == null || !RayEntityPicker.boundsOf(entity, box)) continue;
      // Down is +Y; the base is the box's largest Y.
      final base = Vector3((box.min.x + box.max.x) / 2, box.max.y, (box.min.z + box.max.z) / 2);
      final ray = Ray3()..setValues(base.x, base.y - 1e-4, base.z, 0, 1, 0);
      final ignore = {entity, ..._descendantsOf(entity)};
      var landing = below(ray, ignore)?.position.y;
      final ground = plane?.axis == WorkingPlaneAxis.ground ? plane!.offset : null;
      if (landing == null && ground != null && ground > base.y) landing = ground;
      if (landing == null || (landing - base.y).abs() < 1e-6) continue;
      before.add(TransformSnapshot.of(entity));
      moved.add(entity);
      // What is inside it follows it, as it does a gizmo move.
      sceneState.setPosition3(entity, transform.position + Vector3(0, landing - base.y, 0));
    }
    if (moved.isEmpty) return 0;
    scope.history.pushApplied(
      TransformCommand(
        label: moved.length == 1
            ? 'Drop ${moved.single.name ?? 'entity'} to the ground'
            : 'Drop ${moved.length} entities to the ground',
        entities: moved,
        before: before,
        after: [for (final e in moved) TransformSnapshot.of(e)],
        sceneState: sceneState,
      ),
    );
    sceneState.markDirty();
    return moved.length;
  }

  /// Everything under [entity] in the tree, parents before their
  /// children, each family in its order.
  List<Entity> _descendantsOf(Entity entity) {
    final out = <Entity>[];
    final queue = [...?entity.getComponent<ChildrenComponent>()?.childIds];
    for (var i = 0; i < queue.length && i < 100000; i++) {
      final child = world.getEntity(queue[i]);
      if (child == null) continue;
      out.add(child);
      queue.addAll(child.getComponent<ChildrenComponent>()?.childIds ?? const []);
    }
    return out;
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
