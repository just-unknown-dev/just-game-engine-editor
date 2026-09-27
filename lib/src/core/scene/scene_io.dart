import 'package:just_game_engine/just_game_engine.dart';

import '../scope/editor_scope.dart';
import '../state/editor_scene_state.dart';
import '../state/play_snapshot.dart';

/// Opens and saves scenes: the world on one side, the scope's [SceneStore]
/// on the other.
///
/// Guards against re-entrancy: a double-click in the scene picker, or Ctrl+S
/// again before a save's writes finish, must not interleave two file writes
/// or let a save-in-flight mark a scene opened after it started as clean.
class SceneIO {
  SceneIO({
    required this.scope,
    required World Function() world,
    required this.sceneState,
  }) : _worldOf = world;

  final EditorScope scope;
  final World Function() _worldOf;

  /// The world being edited. Read on use: an engine's world does not exist
  /// until it initialises, and the overlay builds before that.
  World get world => _worldOf();
  final EditorSceneState sceneState;

  bool _busy = false;

  /// Whether an open or save is in flight.
  bool get isBusy => _busy;

  /// The open scene's `editor` section (guides, bookmarks) as loaded, and as
  /// the designer last reported it. Saved back alongside the entities.
  Map<String, dynamic>? editorData;

  /// The entities a save writes: everything active with a transform.
  static List<Entity> authored(World world) => PlaySnapshot.authored(world);

  /// Opens [sceneName]: destroys what is loaded, loads the scene file if
  /// there is one, re-links parents by name and hands the graph to
  /// [sceneState]. Returns false if another open or save was in flight.
  ///
  /// File creation is deliberately not done here; `CreateSceneOverlay`
  /// writes the file first and then calls this.
  Future<bool> open(String sceneName) async {
    if (_busy) return false;
    _busy = true;
    try {
      await _open(sceneName);
      return true;
    } finally {
      _busy = false;
    }
  }

  /// Saves the active scene to its file, the one the game loads, so there
  /// is nothing else to regenerate. [asAuthored] is the play snapshot's
  /// entities while a play-test is on; the live world otherwise.
  Future<bool> save({
    List<Map<String, dynamic>>? asAuthored,
    Map<String, dynamic>? editorData,
  }) async {
    if (_busy) return false;
    _busy = true;
    try {
      await _save(asAuthored: asAuthored, editorData: editorData);
      return true;
    } finally {
      _busy = false;
    }
  }

  Future<void> _open(String sceneName) async {
    // Destroy any entities left over from a previously open scene.
    //
    // Everything alive, which is more than the things with a transform (a
    // HUD left behind by the last level would have piled up on top of this
    // one's) and more than a save writes: what a system generated from the
    // last scene goes with it.
    for (final e in world.entities.where((e) => e.isAlive).toList()) {
      world.destroyEntity(e);
    }
    // Every step in the history is an edit of the scene being left: undoing
    // one here would do nothing at best, and at worst write a file that
    // scene uses. A new scene starts a new history, as in any editor.
    scope.history.clear();

    var rawJson = await scope.scenes.loadRawSidecar(sceneName);
    // An older file is brought to the current format in memory; the file
    // itself changes only when the author saves.
    if (rawJson != null &&
        SceneFormat.versionOf(rawJson) < SceneFormat.current) {
      final from = SceneFormat.versionOf(rawJson);
      rawJson = SceneFormat.migrate(rawJson);
      scope.log.log(
        'Scene $sceneName is format v$from; migrated to v${SceneFormat.current} '
        'in memory. Save to persist.',
        source: 'editor',
        category: 'scene',
      );
    }

    // History, guides and hidden entities all refer to the scene being left.
    final editor = rawJson?['editor'];
    editorData = editor is Map ? editor.cast<String, dynamic>() : null;

    final Scene scene = rawJson != null
        ? (Scene.fromJson(rawJson))
        : Scene(name: sceneName);

    if (rawJson != null) {
      final entityList = (rawJson['entities'] as List<dynamic>? ?? []);
      for (final item in entityList) {
        final entityData = item as Map<String, dynamic>;
        final entityName = entityData['name'] as String?;
        final components = (entityData['components'] as List<dynamic>? ?? [])
            .map((c) => scope.codec.decode(c as Map<String, dynamic>))
            .whereType<Component>()
            .toList();
        if (components.isNotEmpty) {
          final made = world.createEntityWithComponents(
            components,
            name: entityName,
          );
          // Saved switched off: it is in the scene and listed in the
          // tree, and the game will not run it.
          if (entityData['enabled'] == false) made.isActive = false;
        }
      }

      // Second pass: re-link parent-child relationships by name.
      //
      // Every entity, not only the ones with a transform: a piece of
      // interface has none, and building this map from a transform query
      // silently dropped every HUD and menu link — the tree showed a
      // canvas's children as though they were roots.
      final nameToEntity = <String?, Entity>{
        for (final e in world.entities)
          if (e.isAlive) e.name: e,
      };
      for (final item in entityList) {
        final entityData = item as Map<String, dynamic>;
        final parentName = entityData['parentName'] as String?;
        if (parentName == null) continue;
        final childEntity = nameToEntity[entityData['name'] as String?];
        final parentEntity = nameToEntity[parentName];
        if (childEntity == null || parentEntity == null) continue;
        // Both ends of the link, and both made where a file leaves one
        // out — the same rule `SceneLoader` follows.
        final existing = childEntity.getComponent<ParentComponent>();
        if (existing != null) {
          existing.parentId = parentEntity.id;
        } else {
          childEntity.addComponent(ParentComponent(parentId: parentEntity.id));
        }
        if (!parentEntity.hasComponent<ChildrenComponent>()) {
          parentEntity.addComponent(ChildrenComponent());
        }
        parentEntity.getComponent<ChildrenComponent>()!.addChild(
          childEntity.id,
        );
      }
    }

    final entities = world
        .query([TransformComponent])
        .where((e) => e.isActive)
        .toList();

    final nodeMap = <EntityId, SceneNode>{};
    for (final entity in entities) {
      final transform = entity.getComponent<TransformComponent>()!;
      final nodeName = entity.name ?? 'entity_${entity.id}';
      SceneNode? node = scene.findNode(nodeName);
      if (node == null) {
        node = SceneNode(nodeName)
          ..localPosition = transform.position.toOffset()
          ..localRotation = transform.rotation
          ..localScale = transform.scale.x;
        scene.addNode(node);
      }
      nodeMap[entity.id] = node;
    }

    // The file's order is the record of what order the roots are in: the
    // loader creates them in the order they are written.
    sceneState.openScene(
      scene,
      nodeMap,
      rootOrder: [
        for (final entity in world.entities)
          if (entity.isActive &&
              entity.getComponent<ParentComponent>()?.parentId == null)
            entity.id,
      ],
    );
    scope.modules.notifySceneOpened(sceneName);
    scope.log.log(
      'Opened scene $sceneName with ${nodeMap.length} linked entities.',
      source: 'editor',
      category: 'scene',
    );
  }

  Future<void> _save({
    required List<Map<String, dynamic>>? asAuthored,
    required Map<String, dynamic>? editorData,
  }) async {
    final scene = sceneState.activeScene.value;
    if (scene == null) return;
    scope.restoreAuthoredState();

    // While playing, the world holds simulated state and spawned entities,
    // not the level. Save what was authored.
    final snapshot = asAuthored;
    final List<Map<String, dynamic>> encoded;
    if (snapshot != null) {
      encoded = snapshot;
    } else {
      final entities = authored(world);
      encoded = scope.codec.encodeEntities(
        entities,
        rootOrder: sceneState.rootOrder(world),
      );
    }
    await scope.scenes.writeSceneJson(
      scene.name,
      scene,
      encoded,
      editor: editorData,
    );
    final entityCount = encoded.length;

    sceneState.markClean();
    scope.log.log(
      'Saved scene ${scene.name} with $entityCount entities'
      '${snapshot != null ? ' (as authored — play-mode changes are not saved)' : ''}.',
      source: 'editor',
      category: 'scene',
    );
  }
}
