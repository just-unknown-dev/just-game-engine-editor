import 'package:just_editor_core/host.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart' show SceneAssets;

import 'scene_name_validator.dart';

/// Thrown by [SceneManager] operations that are refused (invalid name,
/// protected scene, missing source scene, ...). [message] is user-facing.
class SceneManagerException implements Exception {
  SceneManagerException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Single entry point for scene lifecycle operations (list/delete/rename/
/// duplicate), replacing ad-hoc calls to [SceneStore]/
/// [SceneNameValidator] scattered across the UI.
///
/// [protectedSceneNames] are scenes wired directly into the shipped app
/// (e.g. hardcoded imports in `lib/game/world_setup.dart`) — there is no
/// registry that tracks this automatically, so it must be configured
/// explicitly (see `JustGameEditorPlugin.register(protectedSceneNames: ...)`).
class SceneManager {
  /// Scenes in [store]. A deleted scene goes to [trashRoot]: the project's
  /// `.editor_trash/` when [store] is the project's own, else a `.trash`
  /// folder in the store's folder (a test's).
  SceneManager({
    required this.store,
    this.protectedSceneNames = const {},
    String? trashRoot,
  }) : trashRoot = trashRoot ?? _trashFor(store);

  /// The scene files this manages.
  final SceneStore store;

  final Set<String> protectedSceneNames;

  /// Where deleted scenes are kept, so a delete can be taken back: a
  /// folder per delete, named by when, holding the file at its project
  /// path — the way the Assets dock's trash keeps a file.
  final String trashRoot;

  static String _trashFor(SceneStore store) {
    final project = Directory.current.path;
    return store.backupsRoot == '$project/.editor_backups'
        ? '$project/${AssetIndex.trashFolder}'
        : '${store.scenesRoot}/.trash';
  }

  /// The summaries read so far, by name, with the file's modified time and
  /// size when it was read: a file not changed since is not read again.
  final Map<String, (DateTime, int, SceneSummary)> _summaries = {};

  /// Every scene in `assets/scenes/`, sorted by name.
  List<String> listScenes() => store.listSceneNames()..sort();

  /// The scenes the game plays, in order; the first is where it starts.
  List<String> playOrder() => store.playOrder();

  /// Makes [names] the game's play order. Each must be a scene on disk.
  Future<void> setPlayOrder(List<String> names) async {
    final onDisk = store.listSceneNames().toSet();
    final missing = names.where((n) => !onDisk.contains(n)).toList();
    if (missing.isNotEmpty) {
      throw SceneManagerException('No scene named "${missing.first}".');
    }
    if (names.toSet().length != names.length) {
      throw SceneManagerException('A scene can be in the play order once.');
    }
    await store.writePlayOrder(names);
  }

  bool isProtected(String name) => protectedSceneNames.contains(name);

  /// What the Scenes list shows about [name] ([SceneStore.summaryOf]), read
  /// again only when its file has changed. A file that cannot be read as a
  /// scene — not JSON, or JSON of the wrong shape — is summed up as
  /// unreadable rather than throwing. Null when there is no such file.
  SceneSummary? summaryOf(String name) {
    final FileStat stat;
    try {
      stat = FileStat.statSync(_pathOf(name));
    } on FileSystemException {
      return null;
    }
    if (stat.type == FileSystemEntityType.notFound) {
      _summaries.remove(name);
      return null;
    }
    final seen = _summaries[name];
    if (seen != null && seen.$1 == stat.modified && seen.$2 == stat.size) {
      return seen.$3;
    }
    SceneSummary? summary;
    try {
      summary = store.summaryOf(name);
    } on FileSystemException {
      return null;
    } on Object {
      // `"entities": {}` and the like: the row says it cannot be read.
      summary = SceneSummary(name: name, savedAt: stat.modified);
    }
    if (summary == null) {
      _summaries.remove(name);
    } else {
      _summaries[name] = (stat.modified, stat.size, summary);
    }
    return summary;
  }

  /// Validates a candidate scene name, excluding [ignoring] — the scene's
  /// own current name, when renaming — from the existing-name check, so
  /// that a rename may change only its letter case. Every other scene's
  /// name is taken, in any letter case.
  String? validateName(String name, {String? ignoring}) {
    final existing = SceneNameValidator.existingSceneNames(
      store,
    ).where((n) => n != ignoring).toList();
    return SceneNameValidator.validate(name, existingNames: existing);
  }

  /// Moves [name] to the trash ([trashRoot]) and drops it from the play
  /// order. The result puts it back. Throws [SceneManagerException] if
  /// [name] is protected or is not a scene on disk.
  Future<DeletedScene> deleteScene(String name) async {
    if (isProtected(name)) {
      throw SceneManagerException(
        '"$name" is used by the game\'s own code and cannot be deleted.',
      );
    }
    _requireScene(name);
    final playIndex = store.playOrder().indexOf(name);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final kept = '$trashRoot/$stamp/${SceneAssets.pathFor(name)}';
    await ProjectFiles.rename(_pathOf(name), kept);
    _summaries.remove(name);
    // The file has gone already: this takes it out of `scenes.json`.
    await store.deleteSceneFiles(name);
    return DeletedScene._(this, name, kept, playIndex);
  }

  Future<void> _restore(DeletedScene deleted) async {
    final name = deleted.name;
    final lower = name.toLowerCase();
    if (store.listSceneNames().any((n) => n.toLowerCase() == lower)) {
      throw SceneManagerException(
        'A scene named "$name" is there again; the deleted one stays in '
        '${deleted.keptAt}.',
      );
    }
    await ProjectFiles.rename(deleted.keptAt, _pathOf(name));
    if (deleted._playIndex >= 0) {
      final order = store.playOrder()..remove(name);
      order.insert(deleted._playIndex.clamp(0, order.length), name);
      await store.writePlayOrder(order);
    }
  }

  /// Renames [oldName] to [newName], and its backups with it. A rename
  /// that changes only the letter case is allowed; [newName] may not be
  /// any other scene's name, in any case. Renaming to the same name does
  /// nothing. Throws [SceneManagerException] if [oldName] is protected or
  /// is not a scene on disk, or if [newName] is invalid or taken.
  Future<void> renameScene(String oldName, String newName) async {
    if (isProtected(oldName)) {
      throw SceneManagerException(
        '"$oldName" is used by the game\'s own code and cannot be renamed.',
      );
    }
    if (newName == oldName) return;
    _requireScene(oldName);
    final error = validateName(newName, ignoring: oldName);
    if (error != null) throw SceneManagerException(error);
    await store.renameSceneFiles(oldName, newName);
    _summaries
      ..remove(oldName)
      ..remove(newName);
    await _moveBackups(oldName, newName);
  }

  /// `.editor_backups/<from>/` follows the scene to `<to>/` — unless a
  /// folder is there already (backups of an older scene of that name),
  /// when the backups stay where they are rather than mix.
  Future<void> _moveBackups(String from, String to) async {
    final old = '${store.backupsRoot}/$from';
    if (!Directory(old).existsSync()) return;
    try {
      await ProjectFiles.rename(old, '${store.backupsRoot}/$to');
    } on FileSystemException {
      // Something is there under the new name: the backups stay put.
    }
  }

  /// Copies [sourceName] to a new scene [newName], leaving [sourceName]
  /// untouched. [newName] may not be any scene's name, the source's own
  /// included, in any letter case. Throws [SceneManagerException] if
  /// [sourceName] is not a scene on disk or [newName] is invalid or taken.
  Future<void> duplicateScene(String sourceName, String newName) async {
    _requireScene(sourceName);
    final error = validateName(newName);
    if (error != null) throw SceneManagerException(error);
    await store.duplicateSceneFiles(sourceName, newName);
  }

  /// The other scenes that name [name] — a goal's next scene, a door's —
  /// and how many times each does: every text value in them that is
  /// exactly [name]. [except] (the scene itself, under its new name after
  /// a rename) is not searched. A scene that cannot be read is skipped.
  Future<Map<String, int>> mentionsOf(String name, {String? except}) async {
    final out = <String, int>{};
    for (final scene in store.listSceneNames()) {
      if (scene == name || scene == except) continue;
      final raw = await _readRaw(scene);
      if (raw == null) continue;
      final count = _replaceIn(raw, name, null);
      if (count > 0) out[scene] = count;
    }
    return out;
  }

  /// Points every mention of [from] in [scenes] (see [mentionsOf]) at [to]
  /// instead, each scene file rewritten whole or not at all. Returns how
  /// many mentions changed.
  Future<int> rewriteMentions(
    String from,
    String to,
    Iterable<String> scenes,
  ) async {
    var changed = 0;
    for (final scene in scenes) {
      final raw = await _readRaw(scene);
      if (raw == null) continue;
      final count = _replaceIn(raw, from, to);
      if (count == 0) continue;
      await ProjectFiles.writeString(_pathOf(scene), store.encodeRawText(raw));
      _summaries.remove(scene);
      changed += count;
    }
    return changed;
  }

  Future<Map<String, dynamic>?> _readRaw(String scene) async {
    try {
      return await store.loadRawSidecar(scene);
    } on Object {
      // Not a scene's JSON (a list, say): nothing in it to point anywhere.
      return null;
    }
  }

  /// Counts the text values in [scene] that are exactly [from] — the
  /// scene's own `name` aside — and, when [to] is given, makes them [to].
  static int _replaceIn(Map<String, dynamic> scene, String from, String? to) {
    var count = 0;
    Object? visit(Object? value) {
      if (value is String) {
        if (value != from) return value;
        count++;
        return to ?? value;
      }
      if (value is Map) {
        for (final key in value.keys.toList()) {
          value[key] = visit(value[key]);
        }
      } else if (value is List) {
        for (var i = 0; i < value.length; i++) {
          value[i] = visit(value[i]);
        }
      }
      return value;
    }

    for (final key in scene.keys.toList()) {
      if (key == 'name') continue;
      scene[key] = visit(scene[key]);
    }
    return count;
  }

  String _pathOf(String name) => '${store.scenesRoot}/$name.scene.json';

  /// Throws unless [name] is a scene on disk, spelled as its file is.
  void _requireScene(String name) {
    if (!SceneNameValidator.existingSceneNames(store).contains(name)) {
      throw SceneManagerException('No scene named "$name".');
    }
  }
}

/// A scene [SceneManager.deleteScene] moved to the trash, able to come back.
class DeletedScene {
  DeletedScene._(this._manager, this.name, this.keptAt, this._playIndex);

  final SceneManager _manager;

  /// The scene's name.
  final String name;

  /// Where its file is kept meanwhile.
  final String keptAt;

  /// Where it was in the play order; -1 when it was not in it.
  final int _playIndex;

  /// Puts it back under its own name, at its place in the play order.
  /// Throws [SceneManagerException] when a scene of that name has been
  /// made since; the deleted file then stays where it is kept.
  Future<void> restore() => _manager._restore(this);
}
