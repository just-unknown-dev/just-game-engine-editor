import 'dart:convert';
import 'dart:io';

import 'package:just_inputs/just_inputs.dart';

/// Writes and reads the project's `lib/game/input/input_bindings.json` using
/// [dart:io] — the game's single canonical source of input bindings
/// (bundled as an asset for the app's own runtime load; this class is only
/// for the editor's dev-time write/read path), analogous to how
/// [SceneFileGenerator] persists `.scene.json` files.
///
/// Only usable on native desktop targets in debug mode.
class InputBindingsFileGenerator {
  const InputBindingsFileGenerator._();

  static String get _dir => '${Directory.current.path}/lib/game/input';
  static String get _path => '$_dir/input_bindings.json';

  /// Writes [actions] to `lib/game/input/input_bindings.json`, creating the
  /// directory if it doesn't exist yet.
  static Future<void> writeBindings(InputActionSet actions) async {
    final dir = Directory(_dir);
    if (!dir.existsSync()) await dir.create(recursive: true);
    final json = const JsonEncoder.withIndent('  ').convert(actions.toJson());
    await File(_path).writeAsString(json);
  }

  /// Reads `lib/game/input/input_bindings.json`, or `null` if it doesn't
  /// exist yet or fails to parse.
  static Future<InputActionSet?> loadRaw() async {
    final file = File(_path);
    if (!file.existsSync()) return null;
    try {
      return InputActionSet.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
