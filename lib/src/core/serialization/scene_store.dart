import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine/just_game_engine.dart';

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
  /// manifest. Never overwrites a scene that already exists.
  Future<void> writeInitialFiles(String sceneName) async {
    await _ensureRoot();
    final file = File(_jsonPath(sceneName));
    if (!file.existsSync()) {
      await file.writeAsString(_buildInitialScene(sceneName));
    }
    await _editManifest((names) {
      if (!names.contains(sceneName)) names.add(sceneName);
    });
  }

  String _buildInitialScene(String sceneName) {
    List<Map<String, dynamic>> encode(List<Component> components) =>
        components.map(codec.encode).whereType<Map<String, dynamic>>().toList();
    return _pretty.convert({
      'version': SceneFormat.current,
      ...Scene(name: sceneName).toJson(),
      'entities': [
        {
          'name': 'MainCamera',
          'parentName': null,
          'components': encode([
            TransformComponent(position: Vector3(2000, 400, 0)),
            // Follows whatever the game tags 'player' once it is spawned.
            VirtualCameraComponent(followTag: 'player'),
            CameraFramingComponent(),
            CameraConfinerComponent(boundsName: 'LevelBounds'),
          ]),
        },
        {
          'name': 'LevelBounds',
          'parentName': null,
          'components': encode([
            TransformComponent(position: Vector3(2000, 400, 0)),
            CameraBoundsComponent(width: 4000, height: 800),
          ]),
        },
        {
          'name': 'PlayerSpawn',
          'parentName': null,
          'components': encode([
            TransformComponent(position: Vector3(200, 400, 0)),
            SpawnComponent(tag: 'player'),
          ]),
        },
      ],
    });
  }

  /// Saves [entities] as [sceneName].
  Future<void> writeJsonSidecar(
    String sceneName,
    Scene scene,
    List<Entity> entities,
  ) => writeSceneJson(sceneName, scene, codec.encodeEntities(entities));

  /// Saves already-encoded [entities] as [sceneName] — for writing a snapshot
  /// taken earlier rather than the live world.
  ///
  /// [editor] is saved alongside as the `editor` section — guides, camera
  /// bookmarks — which the game's scene loader ignores.
  Future<void> writeSceneJson(
    String sceneName,
    Scene scene,
    List<Map<String, dynamic>> entities, {
    Map<String, dynamic>? editor,
  }) async {
    await _ensureRoot();
    await File(_jsonPath(sceneName)).writeAsString(
      _pretty.convert({
        'version': SceneFormat.current,
        ...scene.toJson(),
        'entities': entities,
        'editor': ?editor,
      }),
    );
    await _editManifest((names) {
      if (!names.contains(sceneName)) names.add(sceneName);
    });
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
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return (json['scenes'] as List? ?? const []).cast<String>().toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> _editManifest(void Function(List<String> names) edit) async {
    await _ensureRoot();
    final names = _readManifest();
    edit(names);
    await File(_manifestPath).writeAsString(_pretty.convert({'scenes': names}));
  }

  // ── Read ─────────────────────────────────────────────────────────────────

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

  /// The scene graph stored in [sceneName], or null.
  Future<Scene?> loadFromSidecar(String sceneName) async {
    final raw = await loadRawSidecar(sceneName);
    if (raw == null) return null;
    try {
      return Scene.fromJson(raw);
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
