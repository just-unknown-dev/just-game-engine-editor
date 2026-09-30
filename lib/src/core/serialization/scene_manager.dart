import 'scene_store.dart';
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
  SceneManager({required this.store, this.protectedSceneNames = const {}});

  /// The scene files this manages.
  final SceneStore store;

  final Set<String> protectedSceneNames;

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

  /// Validates a candidate scene name, excluding [ignoring] (the scene's own
  /// current name, when renaming/duplicating) from the existing-name check.
  String? validateName(String name, {String? ignoring}) {
    final existing = SceneNameValidator.existingSceneNames(
      store,
    ).where((n) => n != ignoring).toList();
    return SceneNameValidator.validate(name, existingNames: existing);
  }

  /// Permanently deletes [name]'s folder. Throws [SceneManagerException] if
  /// [name] is protected.
  Future<void> deleteScene(String name) async {
    if (isProtected(name)) {
      throw SceneManagerException(
        '"$name" is used by the game\'s own code and cannot be deleted.',
      );
    }
    await store.deleteSceneFiles(name);
  }

  /// Renames [oldName] to [newName]. Throws [SceneManagerException] if
  /// [oldName] is protected or [newName] is invalid/taken.
  Future<void> renameScene(String oldName, String newName) async {
    if (isProtected(oldName)) {
      throw SceneManagerException(
        '"$oldName" is used by the game\'s own code and cannot be renamed.',
      );
    }
    final error = validateName(newName, ignoring: oldName);
    if (error != null) throw SceneManagerException(error);
    await store.renameSceneFiles(oldName, newName);
  }

  /// Copies [sourceName] to a new scene [newName], leaving [sourceName]
  /// untouched. Throws [SceneManagerException] if [newName] is invalid/taken.
  Future<void> duplicateScene(String sourceName, String newName) async {
    final error = validateName(newName, ignoring: sourceName);
    if (error != null) throw SceneManagerException(error);
    await store.duplicateSceneFiles(sourceName, newName);
  }
}
