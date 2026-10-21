/// Rewriting the project's prefab files for a change made everywhere: a tag
/// renamed or deleted, a collision layer deleted.
library;

import 'package:just_editor_core/host.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../scope/editor_scope_services.dart';

/// The project's prefab files (`*.prefab.json` under `assets/`), read for a
/// change made in every file and written back after a backup — what
/// `TagRefactor` and `LayerRefactor` do to them, besides the scenes.
///
/// A prefab's entities are listed as a scene's are, so whatever walks a
/// scene's JSON walks a prefab's [read] too.
final class PrefabRewrites {
  PrefabRewrites(this.scope, {required this.root});

  /// The editor.
  final EditorScope scope;

  /// The project: where `assets/` is.
  final String root;

  /// How many backups of one prefab are kept, as for a scene rewritten by a
  /// rename.
  static const int backupsKept = 20;

  /// Every prefab file under `assets/`, project-relative, in order. None
  /// when the folder cannot be listed.
  List<String> files() {
    final dir = Directory('$root/assets');
    try {
      if (!dir.existsSync()) return const [];
      return [
        for (final f in dir.listSync(recursive: true).whereType<File>())
          if (jge.PrefabFile.isPrefabPath(f.path))
            f.path.replaceAll(r'\', '/').substring(root.length + 1),
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }

  /// The prefab at [path] as JSON, its components brought up to the current
  /// scene format — what a change is made to, in place — and the file's
  /// text as it was, for the backup. Throws what reading it throws.
  ({Map<String, dynamic> json, String before}) read(String path) {
    final text = File('$root/$path').readAsStringSync();
    final file = jge.PrefabFile.parse(text).migrated(
      (scene) =>
          jge.SceneFormat.migrate(scene, hooks: scope.context.migrations),
    );
    return (json: file.toJson(), before: text);
  }

  /// Writes [json] — [read]'s, changed — over the prefab at [path], whole or
  /// not at all, after keeping [before] (what the file held) as a backup.
  /// Throws when what was changed is no longer a prefab, or a write fails;
  /// the file is then as it was.
  Future<void> write(
    String path,
    Map<String, dynamic> json, {
    required String before,
  }) async {
    final file = jge.PrefabFile.fromJson(json);
    await _backup(path, before);
    await ProjectFiles.writeString('$root/$path', file.encode());
  }

  /// Makes the open scene's instances of each prefab in [paths] again from
  /// its file as it is now — each keeping what it changes — and has the
  /// engine read it again, then tells the modules the file changed. A
  /// prefab the engine has not read is not read now: nothing in the scene
  /// is made from it.
  Future<void> refresh(Iterable<String> paths) async {
    final instances = scope.prefabInstances;
    for (final path in paths) {
      if (instances.library.loaded(path) != null) {
        await instances.refresh(path);
      }
      for (final module in scope.modules.withBuiltIns) {
        module.onAssetChanged(path);
      }
    }
  }

  // `.editor_backups/.prefabs/<path without its ending>/<when>.prefab.json`:
  // beside the scenes' backups, in a folder no scene can be called.
  Future<void> _backup(String path, String text) async {
    const ending = jge.PrefabFile.ending;
    final name = path.toLowerCase().endsWith(ending)
        ? path.substring(0, path.length - ending.length)
        : path;
    final dir = Directory('${scope.scenes.backupsRoot}/.prefabs/$name');
    await dir.create(recursive: true);
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}-'
        '${t.millisecond.toString().padLeft(3, '0')}';
    await ProjectFiles.writeString('${dir.path}/$stamp$ending', text);
    // Newest first by name, which is by time.
    final all = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in all.skip(backupsKept)) {
      try {
        await old.delete();
      } on FileSystemException {
        // Open elsewhere: it goes next time.
      }
    }
  }
}
