import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';

import '../entities/entity_ops.dart';
import 'scope_prefabs.dart';

/// Placing prefabs with the entity operations: a prefab file's instance
/// or a prefab's own entity, standing on a surface, as one undo step.
///
/// Here, beside the prefab instances, so the entity operations need no
/// prefab code.
extension EntityOpsPrefabs on EntityOps {
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
    final entity = spawnPrefab(
      prefab,
      at,
      align: align,
      spin: spin,
      size: size,
    );
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
            // A top just made: its instance is there.
            'prefab': instances.changesOf(top)!.block.toJson(),
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
}
