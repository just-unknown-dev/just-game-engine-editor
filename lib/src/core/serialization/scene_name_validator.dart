import 'dart:io';

import 'package:just_game_engine/just_game_engine.dart' show SceneNames;

import 'scene_store.dart';

/// Validates scene names and scans the project for existing scenes.
///
/// The rules themselves are the engine's [SceneNames], shared with
/// `just scene new`, so a name the editor refuses the command line refuses
/// too.
class SceneNameValidator {
  const SceneNameValidator._();

  /// Returns an error string if [name] is invalid, or `null` if valid.
  ///
  /// [existingNames] is compared case-insensitively to catch near-duplicates.
  static String? validate(
    String name, {
    List<String> existingNames = const [],
  }) => SceneNames.problem(name, existing: existingNames);

  /// Every existing scene name. One source of truth: the same listing the
  /// scene picker and the manifest use.
  static List<String> existingSceneNames(SceneStore store) {
    try {
      return store.listSceneNames();
    } on FileSystemException {
      return [];
    }
  }
}
