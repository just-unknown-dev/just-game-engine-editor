import 'editor_log_storage_stub.dart'
    if (dart.library.io) 'editor_log_storage_io.dart';

import 'editor_log_entry.dart';

abstract interface class EditorLogStorage {
  String? get filePath;

  Future<List<EditorLogEntry>> loadEntries();

  Future<void> appendEntry(EditorLogEntry entry);

  Future<void> clear();
}

EditorLogStorage createEditorLogStorage() => createEditorLogStorageImpl();
