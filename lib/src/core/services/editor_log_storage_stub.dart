import 'editor_log_entry.dart';
import 'editor_log_storage.dart';

class _StubEditorLogStorage implements EditorLogStorage {
  @override
  String? get filePath => null;

  @override
  Future<void> appendEntry(EditorLogEntry entry) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<List<EditorLogEntry>> loadEntries() async => const <EditorLogEntry>[];
}

EditorLogStorage createEditorLogStorageImpl() => _StubEditorLogStorage();
