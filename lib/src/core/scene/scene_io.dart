import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_game_engine/just_game_engine.dart';

import '../scope/editor_scope.dart';
import '../state/editor_scene_state.dart';
import '../state/play_snapshot.dart';
import 'editor_scene.dart';
import 'scene_loading.dart';

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
    SceneLoading? loading,
  }) : _worldOf = world,
       loading = loading ?? SceneLoading();

  final EditorScope scope;
  final World Function() _worldOf;

  /// The world being edited. Read on use: an engine's world does not exist
  /// until it initialises, and the overlay builds before that.
  World get world => _worldOf();
  final EditorSceneState sceneState;

  /// Where an open has got to, for the loader shown over it.
  final SceneLoading loading;

  /// How long an open works before it lets a frame through, so the loader
  /// moves while a big scene is built.
  static const Duration _slice = Duration(milliseconds: 10);

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
  ///
  /// [loading] follows it. With [assets], it then waits on the loads the
  /// scene's entities start, as [assets] counts them; without, it ends as
  /// the scene opens.
  Future<bool> open(String sceneName, {AssetTally Function()? assets}) =>
      _opening(sceneName, assets, () => _open(sceneName));

  /// Opens [sceneName] from [rawJson] — a backup — instead of its file. It
  /// opens with unsaved changes, which is what it holds.
  Future<bool> openFrom(
    String sceneName,
    Map<String, dynamic> rawJson, {
    AssetTally Function()? assets,
  }) => _opening(sceneName, assets, () async {
    await _open(sceneName, raw: rawJson);
    sceneState.markDirty();
    scope.log.log(
      'Recovered unsaved changes to $sceneName from a backup.',
      source: 'editor',
      category: 'scene',
    );
  });

  Future<bool> _opening(
    String sceneName,
    AssetTally Function()? assets,
    Future<void> Function() open,
  ) async {
    if (_busy) return false;
    _busy = true;
    loading.begin(sceneName);
    var opened = false;
    try {
      await open();
      opened = true;
      return true;
    } finally {
      _busy = false;
      // Failed, or nothing to count: the loader goes with the open.
      if (opened && assets != null) {
        loading.watchAssets(assets);
      } else {
        loading.end();
      }
    }
  }

  /// Lets a frame through once [clock] has run a [_slice]: the loader moves
  /// on, and the engine starts loading what is already made.
  Future<void> _breathe(Stopwatch clock) async {
    if (clock.elapsed < _slice) return;
    await Future<void>.delayed(Duration.zero);
    clock.reset();
  }

  /// The open scene as a save would write it, without writing it or
  /// disturbing anything: a timeline preview goes on showing. Null when no
  /// scene is open.
  String? encodeCurrent({
    List<Map<String, dynamic>>? asAuthored,
    Map<String, dynamic>? editorData,
  }) {
    final scene = sceneState.activeScene.value;
    if (scene == null) return null;
    final encoded =
        asAuthored ??
        scope.codec.encodeEntities(
          authored(world),
          rootOrder: sceneState.rootOrder(world),
        );
    return scope.scenes.encodeScene(scene, encoded, editor: editorData);
  }

  String? _lastBackup;

  /// Writes a backup of the open scene, keeping the newest [keep]. Nothing
  /// is written — and false returned — when no scene is open, an open or
  /// save is in flight, or the scene is as the last backup had it.
  Future<bool> backup({
    List<Map<String, dynamic>>? asAuthored,
    Map<String, dynamic>? editorData,
    required int keep,
  }) async {
    final scene = sceneState.activeScene.value;
    if (_busy || scene == null) return false;
    final text = encodeCurrent(asAuthored: asAuthored, editorData: editorData);
    if (text == null || text == _lastBackup) return false;
    _lastBackup = text;
    await scope.scenes.writeBackup(scene.name, text, keep: keep);
    return true;
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

  Future<void> _open(String sceneName, {Map<String, dynamic>? raw}) async {
    _lastBackup = null;
    final clock = Stopwatch()..start();
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

    loading.report(
      SceneLoadStage.read,
      detail: raw == null ? null : 'From a backup of unsaved changes',
    );
    var rawJson = raw ?? await scope.scenes.loadRawSidecar(sceneName);
    // An older file is brought to the current format in memory; the file
    // itself changes only when the author saves.
    if (rawJson != null &&
        SceneFormat.versionOf(rawJson) < SceneFormat.current) {
      final from = SceneFormat.versionOf(rawJson);
      loading.report(
        SceneLoadStage.read,
        detail: 'Upgrading from format v$from to v${SceneFormat.current}',
      );
      await _breathe(clock);
      // With the packages' rules, as the game migrates it.
      final migration = SceneFormat.migrateWithReport(
        rawJson,
        hooks: scope.context.migrations,
      );
      rawJson = migration.scene;
      scope.log.log(
        'Scene $sceneName is format v$from; migrated to v${SceneFormat.current} '
        'in memory. Save to persist.',
        source: 'editor',
        category: 'scene',
      );
      for (final note in migration.notes) {
        scope.log.log(
          'Scene $sceneName: ${note.message}',
          source: 'editor',
          category: 'scene',
          level: DebuggerLogLevel.warning,
        );
      }
      if (migration.needsAtlas.isNotEmpty) {
        scope.log.log(
          'Scene $sceneName: ${migration.needsAtlas.join(', ')} animated a '
          'sprite sheet with no atlas; export one for each before it '
          'animates again.',
          source: 'editor',
          category: 'scene',
          level: DebuggerLogLevel.warning,
        );
      }
    }

    // History, guides and hidden entities all refer to the scene being left.
    final editor = rawJson?['editor'];
    editorData = editor is Map ? editor.cast<String, dynamic>() : null;

    final EditorScene scene = rawJson != null
        ? (EditorScene.fromJson(rawJson))
        : EditorScene(name: sceneName);
    // What this open makes, in the file's order. Frames go by while a big
    // scene is built, and a system may make entities of its own in them:
    // those are neither linked by name nor taken for the scene's roots.
    final made = <Entity>[];
    if (rawJson != null) {
      final entityList = (rawJson['entities'] as List<dynamic>? ?? []);
      loading.report(SceneLoadStage.build, total: entityList.length);
      for (var i = 0; i < entityList.length; i++) {
        final entityData = entityList[i] as Map<String, dynamic>;
        final entityName = entityData['name'] as String?;
        // Anything no definition can read is kept as it was, so a save
        // cannot quietly delete it.
        final components = scope.codec.decodeAll(
          entityData['components'] as List<dynamic>? ?? const [],
        );
        if (components.isNotEmpty) {
          final entity = world.createEntityWithComponents(
            components,
            name: entityName,
          );
          // Saved switched off: it is in the scene and listed in the
          // tree, and the game will not run it.
          if (entityData['enabled'] == false) entity.isActive = false;
          made.add(entity);
        }
        if (clock.elapsed >= _slice) {
          loading.report(
            SceneLoadStage.build,
            done: i + 1,
            total: entityList.length,
          );
          await _breathe(clock);
        }
      }
      loading.report(
        SceneLoadStage.build,
        detail: 'Linking parents and children',
        done: entityList.length,
        total: entityList.length,
      );
      await _breathe(clock);

      // Second pass: re-link parent-child relationships by name.
      //
      // Every entity, not only the ones with a transform: a piece of
      // interface has none, and building this map from a transform query
      // silently dropped every HUD and menu link — the tree showed a
      // canvas's children as though they were roots.
      final nameToEntity = <String?, Entity>{
        for (final e in made)
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

    final placed = made
        .where(
          (e) =>
              e.isAlive && e.isActive && e.hasComponent<TransformComponent>(),
        )
        .length;

    // Each child's offset from its parent follows from the world transforms
    // the file holds — worked out now, since while authoring the game's
    // clock (and with it the world's own pass) stands still.
    world.transformHierarchy.propagate();

    // The file's order is the record of what order the roots are in: the
    // loader creates them in the order they are written.
    sceneState.openScene(
      scene,
      rootOrder: [
        for (final entity in made)
          if (entity.isAlive &&
              entity.isActive &&
              entity.getComponent<ParentComponent>()?.parentId == null)
            entity.id,
      ],
    );
    scope.modules.notifySceneOpened(sceneName);
    scope.log.log(
      'Opened scene $sceneName with $placed placed entities.',
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
