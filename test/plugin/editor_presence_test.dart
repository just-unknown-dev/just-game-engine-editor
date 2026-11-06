// The editor's heartbeat, as the `just` tool reads it: written through
// EditorHeartbeat, fresh while the editor runs, gone when it stops. The
// tool's reader (just_game_engine_cli's `editorIsOpen`) is
// `!EditorHeartbeat.decode(text, modified: lastModified).isStale(now)`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/src/plugin/editor_presence.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';

void main() {
  late Directory root;
  late File lock;

  /// What the `just` tool makes of the file now.
  EditorHeartbeat read() => EditorHeartbeat.decode(
    lock.readAsStringSync(),
    modified: lock.lastModifiedSync(),
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('editor_presence_');
    lock = File('${root.path}/${EditorHeartbeat.path}');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('not under flutter test: no project to guard', () {
    expect(EditorPresence.start(root: root.path), isNull);
    expect(lock.existsSync(), isFalse);
  });

  test('the file it writes is an open editor to the just tool, until it '
      'stops', () {
    final presence = EditorPresence.startIn(root.path)!;
    addTearDown(presence.stop);
    final beat = read();
    expect(beat.pid, pid);
    expect(beat.isStale(DateTime.now()), isFalse);
    expect(
      beat.isStale(DateTime.now().add(EditorHeartbeat.staleAfter)),
      isTrue,
    );
    presence.stop();
    expect(lock.existsSync(), isFalse);
  });

  test('each beat writes a new one', () async {
    final presence = EditorPresence.startIn(
      root.path,
      interval: const Duration(milliseconds: 20),
    )!;
    addTearDown(presence.stop);
    // As an editor that stopped long ago left it.
    final old = DateTime.now().subtract(EditorHeartbeat.staleAfter * 2);
    lock.writeAsStringSync(EditorHeartbeat(beatAt: old, pid: pid).encode());
    expect(read().isStale(DateTime.now()), isTrue);
    for (var i = 0; i < 100 && read().isStale(DateTime.now()); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(read().isStale(DateTime.now()), isFalse);
  });
}
