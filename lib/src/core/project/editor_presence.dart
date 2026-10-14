import 'dart:async';
import 'dart:io';

/// Tells the `just` tool the editor has this project open.
///
/// While the editor runs it touches [path] every few seconds. The editor
/// holds the scenes in memory and saves them over the files, so `just
/// scene` and `just upgrade` wait while the file is fresh. A heartbeat, not
/// a pid: after a crash or a hot restart the file goes stale on its own.
/// (just_game_engine_cli's `EditorPresence` reads it; the two must agree on [path].)
final class EditorPresence {
  EditorPresence._(this._file, this._timer);

  /// The file, relative to the project root.
  static const String path = '.dart_tool/just_core_cli/editor.lock';

  /// How often it is touched.
  static const Duration beat = Duration(seconds: 5);

  final File _file;
  final Timer _timer;

  /// Starts the heartbeat in the project at [root] (the current folder: the
  /// editor runs from the project root). Null when the file can't be
  /// written, and under `flutter test`, which has no project to guard.
  static EditorPresence? start({String? root}) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
    final file = File('${root ?? Directory.current.path}/$path');
    try {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync('$pid');
    } on FileSystemException {
      return null;
    }
    final timer = Timer.periodic(beat, (_) {
      try {
        file.setLastModifiedSync(DateTime.now());
      } on FileSystemException {
        // Gone (a clean, say): written again on the next start.
      }
    });
    return EditorPresence._(file, timer);
  }

  /// Stops it and removes the file.
  void stop() {
    _timer.cancel();
    try {
      if (_file.existsSync()) _file.deleteSync();
    } on FileSystemException {
      // Stale in thirty seconds anyway.
    }
  }
}
