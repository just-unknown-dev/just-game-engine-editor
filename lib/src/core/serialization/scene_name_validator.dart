import 'dart:io';

/// Validates scene names and scans the project for existing scenes.
class SceneNameValidator {
  const SceneNameValidator._();

  static const Set<String> _dartKeywords = {
    'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
    'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
    'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
    'external', 'factory', 'false', 'final', 'finally', 'for', 'Function',
    'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
    'late', 'library', 'mixin', 'new', 'null', 'of', 'on', 'operator', 'part',
    'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static',
    'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'type',
    'typedef', 'var', 'void', 'when', 'while', 'with', 'yield',
  };

  /// Returns an error string if [name] is invalid, or `null` if valid.
  ///
  /// [existingNames] is compared case-insensitively to catch near-duplicates.
  static String? validate(
    String name, {
    List<String> existingNames = const [],
  }) {
    if (name.isEmpty) return 'Scene name cannot be empty.';

    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(name)) {
      return 'Must start with a letter or underscore and contain only '
          'letters, digits, and underscores.';
    }

    if (_dartKeywords.contains(name)) {
      return '"$name" is a reserved Dart keyword.';
    }

    if (existingNames.any((e) => e.toLowerCase() == name.toLowerCase())) {
      return 'A scene named "$name" already exists.';
    }

    return null;
  }

  /// Returns the names of all scene folders in `lib/game/scenes/`.
  /// Each scene lives in its own sub-folder: `lib/game/scenes/{name}/`.
  /// Returns an empty list if the directory is missing or I/O fails.
  static List<String> existingSceneNames() {
    try {
      final dir = Directory(
        '${Directory.current.path}/lib/game/scenes',
      );
      if (!dir.existsSync()) return [];
      return dir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split(RegExp(r'[/\\]')).last)
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
