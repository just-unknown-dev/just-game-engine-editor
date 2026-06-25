import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine_editor/src/core/services/editor_log_entry.dart';
import 'package:just_game_engine_editor/src/core/services/editor_log_service.dart';
import 'package:just_game_engine_editor/src/core/services/editor_log_storage.dart';
import 'package:just_game_engine_editor/src/core/services/editor_log_storage_io.dart'
    show kMaxFileSizeBytes, createEditorLogStorageForPath;

void main() {
  test('runWithCapture records plain print output once', () async {
    final storage = _MemoryEditorLogStorage();
    final service = EditorLogService.withStorage(storage);

    await service.runWithCapture(() async {
      // ignore: avoid_print
      print('captured plain print');
    });

    final matches = service.entries
        .where(
          (entry) =>
              entry.message == 'captured plain print' &&
              entry.category == 'print',
        )
        .toList();

    expect(matches, hasLength(1));

    service.resetForTesting();
  });

  test('startSession keeps pre-session entries without duplication', () async {
    final storage = _MemoryEditorLogStorage();
    final service = EditorLogService.withStorage(storage);

    service.log(
      'boot log before session',
      source: 'bootstrap',
      category: 'startup',
      mirrorToDebugger: false,
    );

    await service.startSession(
      controller: JustDebuggerController(overlayVisible: false),
    );

    final matches = service.entries
        .where((entry) => entry.message == 'boot log before session')
        .toList();

    expect(matches, hasLength(1));
    expect(
      service.entries.any(
        (entry) => entry.message == 'Editor log capture session started.',
      ),
      isTrue,
    );

    service.stopSession();
    service.resetForTesting();
  });

  test('IO log storage rotates when file exceeds max size', () async {
    final dir = await Directory.systemTemp.createTemp('jge_log_rotation_test');
    try {
      final primaryPath = '${dir.path}/editor_runtime.jsonl';
      final storage = createEditorLogStorageForPath(primaryPath);

      // Pre-fill the file so it is above the rotation threshold.
      final primary = File(primaryPath);
      final filler = List.filled(kMaxFileSizeBytes, 0x41); // 'A' * threshold
      await primary.writeAsBytes(filler);

      final entry = EditorLogEntry(
        message: 'after rotation',
        source: 'test',
        category: 'rotation',
        level: DebuggerLogLevel.info,
        timestamp: DateTime.now(),
      );
      await storage.appendEntry(entry);

      // The primary file should now be small (only the new entry).
      final primarySize = await primary.length();
      expect(
        primarySize < kMaxFileSizeBytes,
        isTrue,
        reason: 'Primary file should have been rotated',
      );

      // A backup should exist.
      final backup = File('$primaryPath.1.bak');
      expect(
        await backup.exists(),
        isTrue,
        reason: 'Backup file should exist after rotation',
      );
      final backupSize = await backup.length();
      expect(
        backupSize >= kMaxFileSizeBytes,
        isTrue,
        reason: 'Backup should contain the original oversized data',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('IO log storage clear removes primary and backup files', () async {
    final dir = await Directory.systemTemp.createTemp('jge_log_clear_test');
    try {
      final primaryPath = '${dir.path}/editor_runtime.jsonl';
      final storage = createEditorLogStorageForPath(primaryPath);

      // Write something to primary + create a fake backup.
      final primary = File(primaryPath);
      await primary.writeAsString('line\n');
      final backup = File('$primaryPath.1.bak');
      await backup.writeAsString('old data\n');

      await storage.clear();

      expect(await primary.readAsString(), isEmpty);
      expect(await backup.exists(), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

class _MemoryEditorLogStorage implements EditorLogStorage {
  final List<EditorLogEntry> _entries = <EditorLogEntry>[];

  @override
  String get filePath => 'memory://editor-log';

  @override
  Future<void> appendEntry(EditorLogEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }

  @override
  Future<List<EditorLogEntry>> loadEntries() async {
    return List<EditorLogEntry>.from(_entries);
  }
}
