import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_game_engine/graphics_3d.dart';

/// Import settings and cooking for the project's models, on disk.
///
/// A model's settings live beside it (`<model>.import.json`) and its cooked
/// copy too (`<model>.jmodel`), which the game loads in its place. A model
/// with neither is used as it is; one with settings is cooked when they are
/// saved, and again whenever the file or the settings change ([isStale]).
final class ModelCooking {
  /// Cooking for the project at [root].
  ModelCooking({required String root}) : root = root.replaceAll(r'\', '/');

  /// The project folder.
  final String root;

  File _file(String path) => File('$root/$path');

  /// Whether [path] is a model file it cooks.
  static bool isModel(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.glb') || p.endsWith('.gltf');
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

  /// Saves [settings] beside the model at [path].
  Future<void> saveSettings(String path, ModelImportSettings settings) async {
    final file = _file(ModelImportSettings.sidecarOf(path));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(settings.toJson())}\n',
    );
  }

  /// Whether the model at [path] is to be cooked and its cooked copy is
  /// missing or was made from another file or other settings.
  bool isStale(String path) {
    if (!hasSettings(path) && !isCooked(path)) return false;
    final source = _file(path);
    if (!source.existsSync()) return false;
    final cooked = _file(ModelImportSettings.cookedOf(path));
    if (!cooked.existsSync()) return true;
    final stamp = CookedModel.stampOf(_head(cooked));
    return stamp != cookStamp(source.readAsBytesSync(), settingsOf(path));
  }

  // The header holds the stamp: no need to read the textures behind it.
  static Uint8List _head(File file) {
    final raf = file.openSync();
    try {
      final first = raf.readSync(12);
      if (first.length < 12) return first;
      final n = ByteData.sublistView(first).getUint32(8, Endian.little);
      raf.setPositionSync(0);
      return raf.readSync(12 + n);
    } finally {
      raf.closeSync();
    }
  }

  /// Cooks the model at [path] with its settings, writing its cooked copy.
  Future<CookedResult> cook(String path) async {
    final source = _file(path);
    final folder = source.parent.path;
    final result = await cookModel(
      await source.readAsBytes(),
      name: path,
      fetch: (uri) => File('$folder/$uri').readAsBytes(),
      settings: settingsOf(path),
    );
    await _file(
      ModelImportSettings.cookedOf(path),
    ).writeAsBytes(result.bytes, flush: true);
    return result;
  }

  /// Cooks each of [paths] that [isStale]; the ones cooked, with what
  /// failed by path.
  Future<(List<String>, Map<String, Object>)> cookStale(
    Iterable<String> paths,
  ) async {
    final cooked = <String>[];
    final failed = <String, Object>{};
    for (final path in paths) {
      if (!isModel(path) || !isStale(path)) continue;
      try {
        await cook(path);
        cooked.add(path);
      } on Object catch (error) {
        failed[path] = error;
      }
    }
    return (cooked, failed);
  }

  /// Deletes the cooked copy of the model at [path]: the game loads the
  /// file itself again. Its settings stay.
  Future<void> uncook(String path) async {
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
