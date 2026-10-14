import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine/just_game_engine.dart';

import '../scene/editor_scene.dart';
import 'scene_codec.dart';

/// Reads and writes the project's scene files.
///
/// Scenes are plain JSON assets, flat in one directory, listed in order by a
/// manifest:
///
/// ```
/// assets/scenes/
///   scenes.json            ← {"scenes": ["level_01", "level_02"]}
///   level_01.scene.json
///   level_02.scene.json
/// ```
///
/// There is no generated code. The shipped game loads these same files with
/// the engine's `SceneLoader`, through the same codecs the editor saves with,
/// so what you save is exactly what ships — and nothing here is imported by
/// the game.
///
/// Flat on purpose: `assets/scenes/` is declared once in `pubspec.yaml` and
/// every scene saved into it ships. A folder per scene needed a pubspec edit
/// for each new level.
///
/// Uses `dart:io`, so only runs where the editor does: native desktop, debug.
class SceneStore {
  /// A store rooted at [root], or at the project's `assets/scenes` when
  /// null. Tests point it at a temporary directory.
  SceneStore({required this.codec, String? root}) : _root = root;

  /// Encodes what is written here; the scope's codec.
  final SceneCodec codec;

  final String? _root;

  /// Directory scenes live in.
  String get scenesRoot =>
      _root ?? '${Directory.current.path}/${SceneAssets.directory}';

  String _jsonPath(String name) => '$scenesRoot/$name.scene.json';
  String get _manifestPath => '$scenesRoot/scenes.json';

  static const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

  Future<void> _ensureRoot() async {
    final dir = Directory(scenesRoot);
    if (!dir.existsSync()) await dir.create(recursive: true);
  }

  // ── Write ────────────────────────────────────────────────────────────────

  /// Creates [sceneName] with a camera and a spawn point, and lists it in the
  /// manifest. Never overwrites a scene that already exists. [mode] is how
  /// it will be authored — 2-D unless 3-D authoring is switched on.
  Future<void> writeInitialFiles(
    String sceneName, {
    SceneMode mode = SceneMode.twoD,
  }) async {
    await _ensureRoot();
    final file = File(_jsonPath(sceneName));
    if (!file.existsSync()) {
      await file.writeAsString(_buildInitialScene(sceneName, mode));
    }
    await _editManifest((names) {
      if (!names.contains(sceneName)) names.add(sceneName);
    });
  }

  // The starters are shared with `just game scene new`, so a level made either
  // way is the same file (test/scene_starters_parity_test.dart checks they
  // still match the live components, encoded).
  String _buildInitialScene(String sceneName, SceneMode mode) =>
      SceneStarters.encode(SceneStarters.forMode(sceneName, mode: mode.id));

  /// Saves [entities] as [sceneName].
  Future<void> writeJsonSidecar(
    String sceneName,
    EditorScene scene,
    List<Entity> entities,
  ) => writeSceneJson(sceneName, scene, codec.encodeEntities(entities));

  /// Saves already-encoded [entities] as [sceneName] — for writing a snapshot
  /// taken earlier rather than the live world.
  ///
  /// [editor] is saved alongside as the `editor` section — guides, camera
  /// bookmarks — which the game's scene loader ignores.
  Future<void> writeSceneJson(
    String sceneName,
    EditorScene scene,
    List<Map<String, dynamic>> entities, {
    Map<String, dynamic>? editor,
  }) async {
    await _ensureRoot();
    await File(
      _jsonPath(sceneName),
    ).writeAsString(encodeScene(scene, entities, editor: editor));
    await _editManifest((names) {
      if (!names.contains(sceneName)) names.add(sceneName);
    });
  }

  /// [scene] with [entities] — and [editor], the section the game ignores
  /// — exactly as its file holds them.
  String encodeScene(
    EditorScene scene,
    List<Map<String, dynamic>> entities, {
    Map<String, dynamic>? editor,
  }) => _pretty.convert({
    'version': SceneFormat.current,
    ...scene.toJson(),
    'entities': entities,
    'editor': ?editor,
  });

  // ── Backups ─────────────────────────────────────────────────────────────

  /// Where backups go: `.editor_backups/` in the project, never under
  /// `assets/`, which ships with the game — or `.backups` under a test's
  /// root. A folder per scene, a file per backup, named by when.
  String get backupsRoot => _root != null
      ? '$_root/.backups'
      : '${Directory.current.path}/.editor_backups';

  static const String _backupSuffix = '.scene.json';

  /// Writes [text] as a backup of [sceneName] and deletes all but the
  /// newest [keep].
  Future<File> writeBackup(
    String sceneName,
    String text, {
    required int keep,
  }) async {
    final dir = Directory('$backupsRoot/$sceneName');
    await dir.create(recursive: true);
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}-'
        '${t.millisecond.toString().padLeft(3, '0')}';
    final file = File('${dir.path}/$stamp$_backupSuffix');
    await file.writeAsString(text);
    // Newest first by name, which is by time; a backup set aside counts.
    final all = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in all.skip(keep < 1 ? 1 : keep)) {
      try {
        await old.delete();
      } on FileSystemException {
        // Open elsewhere: it goes next time.
      }
    }
    return file;
  }

  /// The backups of [sceneName] that can be recovered, newest first.
  List<File> backupsOf(String sceneName) {
    final dir = Directory('$backupsRoot/$sceneName');
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith(_backupSuffix))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  /// The newest backup of [sceneName] holding changes that were never
  /// saved: made after the scene file was last written, and not the same.
  /// Null when there is none.
  File? unsavedBackupOf(String sceneName) {
    final backups = backupsOf(sceneName);
    if (backups.isEmpty) return null;
    final latest = backups.first;
    final saved = File(_jsonPath(sceneName));
    if (saved.existsSync()) {
      if (!latest.lastModifiedSync().isAfter(saved.lastModifiedSync())) {
        return null;
      }
      if (latest.readAsStringSync() == saved.readAsStringSync()) return null;
    }
    return latest;
  }

  /// [backup]'s scene, or null when it cannot be read.
  Future<Map<String, dynamic>?> readBackup(File backup) async {
    try {
      final decoded = jsonDecode(await backup.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    }
  }

  /// Sets [backup] aside: kept on disk, and never offered again.
  Future<void> setAside(File backup) async {
    try {
      await backup.rename('${backup.path}.declined');
    } on FileSystemException {
      // Gone already.
    }
  }

  // ── Delete / rename / duplicate ─────────────────────────────────────────

  /// Deletes [name] and drops it from the manifest. A missing scene is a
  /// no-op.
  Future<void> deleteSceneFiles(String name) async {
    final file = File(_jsonPath(name));
    if (file.existsSync()) await file.delete();
    await _editManifest((names) => names.remove(name));
  }

  /// Renames [oldName] to [newName], keeping its place in the manifest.
  Future<void> renameSceneFiles(String oldName, String newName) async {
    if (oldName == newName) return;
    await _copyScene(oldName, newName);
    final old = File(_jsonPath(oldName));
    if (old.existsSync()) await old.delete();
    await _editManifest((names) {
      final i = names.indexOf(oldName);
      if (i >= 0) {
        names[i] = newName;
      } else if (!names.contains(newName)) {
        names.add(newName);
      }
    });
  }

  /// Copies [fromName] to [toName], listed straight after the original.
  Future<void> duplicateSceneFiles(String fromName, String toName) async {
    await _copyScene(fromName, toName);
    await _editManifest((names) {
      if (names.contains(toName)) return;
      final i = names.indexOf(fromName);
      i >= 0 ? names.insert(i + 1, toName) : names.add(toName);
    });
  }

  Future<void> _copyScene(String fromName, String toName) async {
    final from = File(_jsonPath(fromName));
    if (!from.existsSync()) return;
    await _ensureRoot();
    final raw = await from.readAsString();
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      data['name'] = toName;
      await File(_jsonPath(toName)).writeAsString(_pretty.convert(data));
    } on FormatException {
      // Not valid JSON — keep the content rather than lose it.
      await File(_jsonPath(toName)).writeAsString(raw);
    }
  }

  // ── Manifest ─────────────────────────────────────────────────────────────

  List<String> _readManifest() {
    final file = File(_manifestPath);
    if (!file.existsSync()) return [];
    return SceneManifest.parse(file.readAsStringSync());
  }

  Future<void> _editManifest(void Function(List<String> names) edit) async {
    await _ensureRoot();
    final names = _readManifest();
    edit(names);
    await File(_manifestPath).writeAsString(SceneManifest.encode(names));
  }

  // ── Play order ───────────────────────────────────────────────────────────

  /// The scenes the game plays, in order: the manifest's names that have a
  /// file. The first is where the shipped game starts.
  List<String> playOrder() {
    final onDisk = listSceneNames().toSet();
    return _readManifest().where(onDisk.contains).toList();
  }

  /// Makes [names] the game's play order: the manifest lists exactly these,
  /// in this order. A scene left out stays on disk, unlisted.
  Future<void> writePlayOrder(List<String> names) => _editManifest(
    (list) => list
      ..clear()
      ..addAll(names),
  );

  // ── Read ─────────────────────────────────────────────────────────────────

  /// What the Scenes list tells about [name] without opening it: its mode,
  /// how many entities it holds and when it was last saved. Null when the
  /// file is missing; a file that is not valid JSON has no mode or count.
  ///
  /// Read at once, like [listSceneNames]: a list of levels is a handful of
  /// small files, and the rows show what is in them from the first frame.
  SceneSummary? summaryOf(String name) {
    final file = File(_jsonPath(name));
    if (!file.existsSync()) return null;
    final saved = file.lastModifiedSync();
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, dynamic>) {
        return SceneSummary(name: name, savedAt: saved);
      }
      return SceneSummary(
        name: name,
        mode: SceneMode.fromId(json['mode']),
        entityCount: (json['entities'] as List?)?.length ?? 0,
        savedAt: saved,
      );
    } on FormatException {
      return SceneSummary(name: name, savedAt: saved);
    }
  }

  /// The raw JSON for [sceneName], or null if it is missing or unreadable.
  Future<Map<String, dynamic>?> loadRawSidecar(String sceneName) async {
    final file = File(_jsonPath(sceneName));
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  /// [raw] as its file holds it — for a backup of a scene about to be
  /// rewritten.
  String encodeRawText(Map<String, dynamic> raw) => _pretty.convert(raw);

  /// [loadRawSidecar], read at once — for a check that cannot wait.
  Map<String, dynamic>? readRawSync(String sceneName) {
    final file = File(_jsonPath(sceneName));
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  /// The scene graph stored in [sceneName], or null.
  Future<EditorScene?> loadFromSidecar(String sceneName) async {
    final raw = await loadRawSidecar(sceneName);
    if (raw == null) return null;
    try {
      return EditorScene.fromJson(raw);
    } on Object {
      return null;
    }
  }

  /// Every scene: manifest order first, then any scene file the manifest
  /// does not list yet — copied in by hand, say — so none are invisible.
  List<String> listSceneNames() {
    final dir = Directory(scenesRoot);
    if (!dir.existsSync()) return [];
    const suffix = '.scene.json';
    final onDisk = <String>{
      for (final f in dir.listSync().whereType<File>())
        if (f.uri.pathSegments.last.endsWith(suffix))
          f.uri.pathSegments.last.substring(
            0,
            f.uri.pathSegments.last.length - suffix.length,
          ),
    };
    final listed = _readManifest().where(onDisk.contains).toList();
    return [...listed, ...(onDisk.difference(listed.toSet()).toList()..sort())];
  }
}

/// A scene as the Scenes list shows it, read from its file.
class SceneSummary {
  const SceneSummary({
    required this.name,
    required this.savedAt,
    this.mode,
    this.entityCount,
  });

  final String name;

  /// How it is authored; null when the file could not be read.
  final SceneMode? mode;

  /// Every entity in it, children too; null when unreadable.
  final int? entityCount;

  /// When its file was last written.
  final DateTime savedAt;

  /// Whether the file could be read as a scene.
  bool get isReadable => mode != null;
}
