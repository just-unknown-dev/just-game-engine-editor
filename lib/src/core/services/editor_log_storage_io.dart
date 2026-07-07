import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'editor_log_entry.dart';
import 'editor_log_storage.dart';

/// Maximum file size in bytes before the log is rotated (~5 MB).
@visibleForTesting
const int kMaxFileSizeBytes = 5 * 1024 * 1024;

/// Number of backup files to keep alongside the primary log.
const int _kMaxBackupFiles = 2;

class _IoEditorLogStorage implements EditorLogStorage {
  _IoEditorLogStorage() : _fileFuture = _resolveFile();

  @visibleForTesting
  _IoEditorLogStorage.forPath(String path)
    : _fileFuture = Future.value(File(path)),
      _file = File(path);

  final Future<File> _fileFuture;
  File? _file;

  @override
  String? get filePath => _file?.path;

  /// Resolves the log file once and caches it so [filePath] is available
  /// synchronously after the first storage operation completes.
  Future<File> _resolvedFile() async => _file ??= await _fileFuture;

  @override
  Future<List<EditorLogEntry>> loadEntries() async {
    final file = await _resolvedFile();
    if (!await file.exists()) {
      return const <EditorLogEntry>[];
    }

    late final List<String> lines;
    try {
      // Read as bytes and decode with allowMalformed so a single bad byte
      // (BOM, partial multi-byte sequence, non-UTF-8 captured output) doesn't
      // throw and wipe the entire log history.
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      lines = const LineSplitter().convert(content);
    } catch (_) {
      return const <EditorLogEntry>[];
    }

    final entries = <EditorLogEntry>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          entries.add(EditorLogEntry.fromJson(decoded));
        }
      } catch (_) {
        // Ignore malformed persisted lines so the session can still load.
      }
    }
    return entries;
  }

  @override
  Future<void> appendEntry(EditorLogEntry entry) async {
    final file = await _resolvedFile();
    await _ensureDir(file);
    await _rotateIfNeeded(file);
    await file.writeAsString(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
      encoding: utf8,
      flush: true,
    );
  }

  @override
  Future<void> clear() async {
    final file = await _resolvedFile();
    if (await file.exists()) {
      await file.writeAsString('', encoding: utf8, flush: true);
    }
    // Also remove any backup files so the cleared state is clean.
    for (var i = 1; i <= _kMaxBackupFiles; i++) {
      final backup = File('${file.path}.$i.bak');
      if (await backup.exists()) {
        await backup.delete();
      }
    }
  }

  Future<void> _ensureDir(File file) async {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
  }

  /// Rotates the primary log file when it exceeds [_kMaxFileSizeBytes].
  ///
  /// Rotation shifts existing backups one level (`*.1.bak` → `*.2.bak`, …),
  /// evicting the oldest when the backup count exceeds [_kMaxBackupFiles],
  /// then renames the primary file to `*.1.bak`.
  Future<void> _rotateIfNeeded(File file) async {
    if (!await file.exists()) {
      return;
    }
    final size = await file.length();
    if (size < kMaxFileSizeBytes) {
      return;
    }

    // Shift existing backups: *.N.bak → *.(N+1).bak, dropping the oldest.
    for (var i = _kMaxBackupFiles; i >= 1; i--) {
      final src = File('${file.path}.$i.bak');
      if (!await src.exists()) {
        continue;
      }
      if (i == _kMaxBackupFiles) {
        await src.delete();
      } else {
        await src.rename('${file.path}.${i + 1}.bak');
      }
    }

    // Move primary → *.1.bak
    await file.rename('${file.path}.1.bak');
  }

  /// On Android/iOS, [Directory.current] is typically `/` and read-only, so
  /// logs go under the app's support directory there. Desktop keeps using the
  /// working directory so `.editor_logs/` stays alongside the project like
  /// before.
  static Future<File> _resolveFile() async {
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    final Directory root;
    if (isTest) {
      root = Directory.systemTemp;
    } else if (Platform.isAndroid || Platform.isIOS) {
      root = await getApplicationSupportDirectory();
    } else {
      root = Directory.current;
    }
    return File(
      '${root.path}${Platform.pathSeparator}.editor_logs${Platform.pathSeparator}editor_runtime.jsonl',
    );
  }
}

EditorLogStorage createEditorLogStorageImpl() => _IoEditorLogStorage();

@visibleForTesting
EditorLogStorage createEditorLogStorageForPath(String path) =>
    _IoEditorLogStorage.forPath(path);
