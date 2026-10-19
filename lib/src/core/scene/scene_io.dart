import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';
import '../scope/editor_scope_services.dart';
import '../state/play_snapshot.dart';
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

  /// The entities a save writes: every live entity the scene holds,
  /// switched on or off, with a transform or without — not what a system
  /// generated from other data ([PlaySnapshot.authored]).
  static List<Entity> authored(World world) => PlaySnapshot.authored(world);

  /// Opens [sceneName]: destroys what is loaded, loads the scene file if
  /// there is one, re-links parents by name and hands the graph to
  /// [sceneState]. Returns false if another open or save was in flight, or
  /// the file could not be read: then an error is logged and the scene that
  /// was open stays open, untouched — an unreadable file never opens as an
  /// empty scene a save would write over it.
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
    if (!await _open(sceneName, raw: rawJson)) return false;
    sceneState.markDirty();
    scope.log.log(
      'Recovered unsaved changes to $sceneName from a backup.',
      source: 'editor',
      category: 'scene',
    );
    return true;
  });

  Future<bool> _opening(
    String sceneName,
    AssetTally Function()? assets,
    Future<bool> Function() open,
  ) async {
    if (_busy) return false;
    _busy = true;
    loading.begin(sceneName);
    var opened = false;
    try {
      opened = await open();
      return opened;
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

  /// Opens [sceneName] (from [raw] when given). False when it could not:
  /// then an error is logged, and — when the file itself could not be read
  /// — the scene that was open is left as it was.
  Future<bool> _open(String sceneName, {Map<String, dynamic>? raw}) async {
    final clock = Stopwatch()..start();
    loading.report(
      SceneLoadStage.read,
      detail: raw == null ? null : 'From a backup of unsaved changes',
    );
    // Read, and brought to the current format, before anything is
    // destroyed: a file that cannot be read must not open as an empty
    // scene, which the next save (or autosave) would write over it.
    Map<String, dynamic>? rawJson;
    try {
      rawJson = raw ?? await scope.scenes.loadRawSidecar(sceneName);
      rawJson = await _migrated(sceneName, rawJson, clock);
    } on Object catch (error, stack) {
      scope.log.log(
        'Could not open scene $sceneName: $error. Nothing was changed; fix '
        'the file (or open a backup) and open it again.',
        source: 'editor',
        category: 'scene',
        level: DebuggerLogLevel.error,
        details: '$stack',
      );
      return false;
    }

    _lastBackup = null;
    // Destroy any entities left over from a previously open scene.
    //
    // Everything alive, which is more than the things with a transform (a
    // HUD left behind by the last level would have piled up on top of this
    // one's) and more than a save writes: what a system generated from the
    // last scene goes with it.
    for (final e in world.entities.where((e) => e.isAlive).toList()) {
      world.destroyEntity(e);
    }
    _forgetSceneLeft();

    final made = <Entity>[];
    try {
      await _build(sceneName, rawJson, made, clock);
      return true;
    } on Object catch (error, stack) {
      // The scene being left is gone already, and this one is half made:
      // nothing is open, so nothing can be saved over either file.
      for (final e in made.reversed) {
        if (e.isAlive) world.destroyEntity(e);
      }
      sceneState.closeScene();
      scope.log.log(
        'Could not open scene $sceneName: $error. The file was not changed.',
        source: 'editor',
        category: 'scene',
        level: DebuggerLogLevel.error,
        details: '$stack',
      );
      return false;
    }
  }

  /// What the editor holds about the scene being left, by entity id — ids
  /// are handed out again in the next one — let go of: its history, what
  /// is hidden, locked and pinned, prefab mode, and the map files it edited
  /// but did not save.
  void _forgetSceneLeft() {
    // Every step in the history is an edit of the scene being left: undoing
    // one here would do nothing at best, and at worst write a file that
    // scene uses. A new scene starts a new history, as in any editor.
    scope.history.clear();
    // Hidden, locked and pinned are sets of ids: kept, they would hide and
    // lock whatever in this scene got those ids.
    scope.view
      ..showAll()
      ..unlockAll()
      ..unpin();
    // Prefab mode on an instance of the scene being left: dropped, nothing
    // applied — an id of this scene is another entity.
    scope.prefabInstances.forgetEditing();
    // Map files edited and not saved: their edits live in the engine's
    // shared map cache, where this scene (or its save) would find them.
    scope.mapDocs.discardUnsaved();
  }

  /// [rawJson] brought to the current scene format, in memory: the file
  /// itself changes only when the author saves.
  Future<Map<String, dynamic>?> _migrated(
    String sceneName,
    Map<String, dynamic>? rawJson,
    Stopwatch clock,
  ) async {
    if (rawJson == null ||
        SceneFormat.versionOf(rawJson) >= SceneFormat.current) {
      return rawJson;
    }
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
    return migration.scene;
  }

  /// The scene's entries, each one a scene can make: a hand-edited or
  /// tool-written entry with a name that is not text, or components that
  /// are not a list, is mended — and said — rather than stopping the open.
  List<Map<String, dynamic>> _entries(String sceneName, Object? entities) {
    if (entities == null) return const [];
    if (entities is! List) {
      _warn(sceneName, '"entities" is not a list; the scene opens empty.');
      return const [];
    }
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < entities.length; i++) {
      final e = entities[i];
      if (e is! Map) {
        _warn(sceneName, 'entry ${i + 1} is not an entity; left out.');
        continue;
      }
      final entry = Map<String, dynamic>.of(e.cast<String, dynamic>());
      final name = entry['name'];
      if (name != null && name is! String) {
        _warn(sceneName, 'entry ${i + 1} has a name that is not text: $name.');
        entry['name'] = '$name';
      }
      final components = entry['components'];
      if (components != null && components is! List) {
        _warn(
          sceneName,
          '"${entry['name'] ?? 'entry ${i + 1}'}" has components that are '
          'not a list; it opens with none.',
        );
        entry['components'] = const <Object?>[];
      }
      out.add(entry);
    }
    return out;
  }

  void _warn(String sceneName, String message) => scope.log.log(
    'Scene $sceneName: $message',
    source: 'editor',
    category: 'scene',
    level: DebuggerLogLevel.warning,
  );

  /// Makes the scene [rawJson] holds (an empty one named [sceneName] when
  /// null) in the world — what it makes in [made], in the file's order —
  /// and hands it to [sceneState].
  Future<void> _build(
    String sceneName,
    Map<String, dynamic>? rawJson,
    List<Entity> made,
    Stopwatch clock,
  ) async {
    // History, guides and hidden entities all refer to the scene being left.
    final editor = rawJson?['editor'];
    editorData = editor is Map ? editor.cast<String, dynamic>() : null;

    // Named after its file, whatever its header says: a save writes the
    // file of the scene's name, and a file copied by hand (its old name
    // inside) would otherwise be saved over the one it was copied from.
    final named = rawJson?['name'];
    if (named != null && named != sceneName) {
      _warn(
        sceneName,
        'the file names itself "$named"; it is opened, and saved, as '
        '$sceneName.',
      );
    }
    final scene = EditorScene(
      name: sceneName,
      mode: SceneMode.fromId(rawJson?['mode']),
    );
    // What this open makes, in the file's order. Frames go by while a big
    // scene is built, and a system may make entities of its own in them:
    // those are neither linked by name nor taken for the scene's roots.
    if (rawJson != null) {
      // The prefabs its instances are made from, read first; each instance
      // then becomes the entities it makes, as the game makes them.
      final library = PrefabLibrary.of(scope.context);
      await library.loadScene(rawJson);
      final entityList = PrefabExpander.expandScene(
        _entries(sceneName, rawJson['entities']),
        library.loaded,
      );
      for (final entry in entityList) {
        if (entry['prefabRef'] case {'missing': final String path}) {
          scope.log.log(
            'Scene $sceneName: the prefab $path could not be read '
            '(${library.errorOf(path) ?? 'no such file'}); '
            '"${entry['name']}" stands empty and keeps its place.',
            source: 'editor',
            category: 'scene',
            level: DebuggerLogLevel.warning,
          );
        }
      }
      // What each entry made, in step with the entries.
      final madeAt = List<Entity?>.filled(entityList.length, null);
      loading.report(SceneLoadStage.build, total: entityList.length);
      for (var i = 0; i < entityList.length; i++) {
        final entityData = entityList[i];
        final name = entityData['name'];
        final entityName = name is String ? name : null;
        // Anything no definition can read is kept as it was, so a save
        // cannot quietly delete it.
        final listed = entityData['components'];
        final components = scope.codec.decodeAll(
          listed is List ? listed : const [],
        );
        // An instance whose prefab is missing has none, and stays.
        if (components.isNotEmpty || entityData['prefabRef'] != null) {
          final entity = world.createEntityWithComponents(
            components,
            name: entityName,
          );
          // Saved switched off: it is in the scene and listed in the
          // tree, and the game will not run it.
          if (entityData['enabled'] == false) entity.isActive = false;
          made.add(entity);
          madeAt[i] = entity;
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

      // Second pass: re-link parent-child relationships — by name, as the
      // game does (SceneLoader.parentIndices): where names repeat, the one
      // on the way down; inside a prefab instance, by its place in it.
      //
      // Every entity, not only the ones with a transform: a piece of
      // interface has none, and linking through a transform query
      // silently dropped every HUD and menu link — the tree showed a
      // canvas's children as though they were roots.
      final parents = SceneLoader.parentIndices(entityList);
      for (var i = 0; i < entityList.length; i++) {
        final at = parents[i];
        if (at == null) continue;
        final childEntity = madeAt[i];
        final parentEntity = madeAt[at];
        if (childEntity == null || parentEntity == null) continue;
        if (!childEntity.isAlive || !parentEntity.isAlive) continue;
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
      // Where what a prefab made came from, and each instance placed: what
      // is inside it against its top where the prefab has it, then
      // following the top to where it is.
      for (var i = 0; i < entityList.length; i++) {
        final ref = entityList[i]['prefabRef'];
        final entity = madeAt[i];
        if (ref is! Map || entity == null) continue;
        final instance = ref['instance'];
        final path = ref['path'];
        if (instance is! int || path is! String) continue;
        if (instance < 0 || instance >= madeAt.length) continue;
        final top = madeAt[instance];
        if (top == null) continue;
        entity.addComponent(PrefabLink(instance: top.id, path: path));
        if (ref['block'] case final Map block) {
          entity.addComponent(
            PrefabInstanceComponent(
              block: PrefabInstance.fromJson(block),
              missing: ref['missing'] != null,
            ),
          );
        }
      }
      for (var i = 0; i < entityList.length; i++) {
        final ref = entityList[i]['prefabRef'];
        final top = madeAt[i];
        if (ref is! Map || ref['instance'] != i || top == null) continue;
        if (ref['home'] case final Map home) {
          final at = scope.codec.decode(home.cast<String, dynamic>());
          if (at is TransformComponent) {
            SceneLoader.placeFromHome(world, top, at);
          }
        }
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
    // loader creates them in the order they are written. Switched off or
    // not — being off is not being gone, and leaving those out moved them
    // to the end of the file on the next save.
    sceneState.openScene(
      scene,
      rootOrder: [
        for (final entity in made)
          if (entity.isAlive &&
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
    // The files the scene refers to that modules keep — a terrain's
    // heights — written with it.
    final failed = await scope.modules.notifySceneSaving(scene.name);
    for (final MapEntry(key: module, value: error) in failed.entries) {
      scope.log.log(
        'Saving scene ${scene.name}: $module could not write its files: $error',
        source: 'editor',
        category: 'scene',
        level: DebuggerLogLevel.warning,
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
