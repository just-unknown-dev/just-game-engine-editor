import 'dart:convert';
import 'dart:typed_data';

import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart'
    show PackageAssetPaths, ProjectFiles;
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show CookedModel, CookedResult, cookModel, cookStamp, modelFilesOf;

import 'cooked_head.dart' if (dart.library.js_interop) 'cooked_head_web.dart';

/// Import settings and cooking for the project's models, on disk.
///
/// A model's settings live beside it (`<model>.import.json`) and its cooked
/// copy too (`<model>.jmodel`), which the game loads in its place. A model
/// with neither is used as it is; one with settings is cooked when they are
/// saved, and again whenever the file or the settings change ([isStale]).
///
/// Paths are asset keys: project paths, or a package's `packages/<name>/…`,
/// read wherever the package is ([PackageAssetPaths]). A package's models
/// are read, never written: their settings and cooked copies are the
/// package's ([isWritable]).
final class ModelCooking {
  /// Cooking for the project at [root].
  ModelCooking({required String root}) : root = root.replaceAll(r'\', '/');

  /// The project folder.
  final String root;

  File _file(String path) => PackageAssetPaths.of(root).file(path);

  /// Whether [path] is a model file it cooks.
  static bool isModel(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.glb') || p.endsWith('.gltf');
  }

  /// Whether the settings and cooked copy of the model at [path] may be
  /// written: a project file, not a package's (`packages/<name>/…`, in
  /// pub's cache or an Asset Store item) nor one outside the project.
  bool isWritable(String path) =>
      !PackageAssetPaths.isPackageKey(path) &&
      PackageAssetPaths.of(root).isWritable(path);

  void _mustWrite(String path) {
    if (isWritable(path)) return;
    throw UnsupportedError(
      '$path is not one of the project\'s files: its settings and cooked '
      'copy are not the editor\'s to write.',
    );
  }

  /// The settings of the model at [path]: its sidecar's, or the defaults.
  ModelImportSettings settingsOf(String path) {
    final file = _file(ModelImportSettings.sidecarOf(path));
    if (!file.existsSync()) return const ModelImportSettings();
    try {
      return ModelImportSettings.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
    } on Object {
      return const ModelImportSettings();
    }
  }

  /// Whether the model at [path] has settings of its own.
  bool hasSettings(String path) =>
      _file(ModelImportSettings.sidecarOf(path)).existsSync();

  /// Whether the model at [path] has a cooked copy.
  bool isCooked(String path) =>
      _file(ModelImportSettings.cookedOf(path)).existsSync();

  /// Saves [settings] beside the model at [path], whole or not at all.
  /// Throws an [UnsupportedError] for a model that is not [isWritable].
  Future<void> saveSettings(String path, ModelImportSettings settings) async {
    _mustWrite(path);
    await ProjectFiles.writeString(
      _file(ModelImportSettings.sidecarOf(path)).path,
      '${const JsonEncoder.withIndent('  ').convert(settings.toJson())}\n',
    );
  }

  /// Whether the model at [path] is to be cooked and its cooked copy is
  /// missing or was made from another file — the model, or one it refers
  /// to (a `.gltf`'s buffers and images) — or other settings.
  ///
  /// Read without stopping the editor: a big model is not read and hashed
  /// on the UI thread's watch. A cooked copy that can't be read — held by
  /// another program, or no cooked model at all — is stale: cooking writes
  /// it again.
  Future<bool> isStale(String path) async {
    if (!hasSettings(path) && !isCooked(path)) return false;
    final source = _file(path);
    if (!await source.exists()) return false;
    final cooked = _file(ModelImportSettings.cookedOf(path));
    if (!await cooked.exists()) return true;
    try {
      final stamp = CookedModel.stampOf(await readCookedHead(cooked.path));
      if (stamp == null) return true;
      final bytes = await source.readAsBytes();
      final folder = source.parent.path;
      final files = <String, Uint8List>{
        for (final file in modelFilesOf(bytes))
          file: await File('$folder/$file').readAsBytes(),
      };
      return stamp != cookStamp(bytes, settingsOf(path), files: files);
    } on Object {
      return true; // Missing, malformed or unreadable: cook (and report) again.
    }
  }

  /// Cooks the model at [path] with its settings, writing its cooked copy
  /// whole or not at all: a cook cut short leaves the copy that was there.
  /// Throws an [UnsupportedError] for a model that is not [isWritable].
  Future<CookedResult> cook(String path) async {
    _mustWrite(path);
    final source = _file(path);
    final folder = source.parent.path;
    final result = await cookModel(
      await source.readAsBytes(),
      name: path,
      fetch: (uri) => File('$folder/$uri').readAsBytes(),
      settings: settingsOf(path),
    );
    await ProjectFiles.writeBytes(
      _file(ModelImportSettings.cookedOf(path)).path,
      result.bytes,
    );
    return result;
  }

  /// Cooks each of [paths] that [isStale]; the ones cooked, with what
  /// failed by path. A package's models are passed over.
  Future<(List<String>, Map<String, Object>)> cookStale(
    Iterable<String> paths,
  ) async {
    final cooked = <String>[];
    final failed = <String, Object>{};
    for (final path in paths) {
      if (!isModel(path) || !isWritable(path)) continue;
      try {
        if (!await isStale(path)) continue;
        await cook(path);
        cooked.add(path);
      } on Object catch (error) {
        failed[path] = error;
      }
    }
    return (cooked, failed);
  }

  /// Deletes the cooked copy of the model at [path]: the game loads the
  /// file itself again. Its settings stay. Throws an [UnsupportedError]
  /// for a model that is not [isWritable].
  Future<void> uncook(String path) async {
    _mustWrite(path);
    final cooked = _file(ModelImportSettings.cookedOf(path));
    if (await cooked.exists()) await cooked.delete();
  }

  /// The model files under [folder] (project-relative), recursively.
  List<String> modelsUnder(String folder) {
    final dir = Directory('$root/$folder');
    if (!dir.existsSync()) return const [];
    final out = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final rel = entity.path.replaceAll(r'\', '/').substring(root.length + 1);
      if (isModel(rel)) out.add(rel);
    }
    return out..sort();
  }
}
