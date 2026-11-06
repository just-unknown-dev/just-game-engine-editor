import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:just_editor_core/io.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show EditorHeartbeat;

/// Tells the `just` tool the editor has this project open.
///
/// While the editor runs it writes its heartbeat ([EditorHeartbeat.path])
/// every [EditorHeartbeat.interval]. The editor holds the scenes in memory
/// and saves them over the files, so `just game scene` and `just upgrade`
/// wait while the heartbeat is fresh. A heartbeat, not a pid: after a crash
/// or a hot restart it goes stale on its own.
///
/// [EditorHeartbeat] (just_game_engine_formats) is the file's one
/// contract: just_game_engine_cli reads it through the same class.
final class EditorPresence {
  EditorPresence._(this._file, this._timer);

  final File _file;
  final Timer _timer;

  /// Starts the heartbeat in the project at [root] (the current folder: the
  /// editor runs from the project root). Null when the file can't be
  /// written, and under `flutter test`, which has no project to guard.
  static EditorPresence? start({String? root}) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
    return startIn(root ?? Directory.current.path);
  }

  /// [start] in the project at [root], under `flutter test` too, beating
  /// every [interval]. Null when the file can't be written.
  @visibleForTesting
  static EditorPresence? startIn(
    String root, {
    Duration interval = EditorHeartbeat.interval,
  }) {
    final file = File('$root/${EditorHeartbeat.path}');
    try {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(_beat());
    } on FileSystemException {
      return null;
    }
    final timer = Timer.periodic(interval, (_) {
      try {
        // Not created again: a project cleaned under the editor gets its
        // heartbeat back on the next start.
        if (file.existsSync()) file.writeAsStringSync(_beat());
      } on FileSystemException {
        // Gone, or held by a reader: the next beat writes it.
      }
    });
    return EditorPresence._(file, timer);
  }

  /// The heartbeat's text, beating now.
  static String _beat() =>
      EditorHeartbeat(beatAt: DateTime.now(), pid: pid).encode();

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
