import 'dart:async';

import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/settings/overlay_settings_store.dart';
import 'package:just_storage/just_storage.dart';

/// The settings store, in memory: what the real one does, minus the disk —
/// so a test's prefs neither touch path_provider nor outlive the test.
class MemorySettingsStore extends OverlaySettingsStore {
  MemorySettingsStore() : super(Completer<JustStandardStorage>().future);

  final Map<String, String> values = {};
  OverlayUiSettings saved = const OverlayUiSettings.defaults();

  @override
  Future<OverlayUiSettings> loadSettings() async => saved;
  @override
  Future<void> saveSettings(OverlayUiSettings settings) async =>
      saved = settings;
  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
  @override
  Future<void> writeRaw(String key, String value) async => values[key] = value;
  @override
  Future<int> readIntByKey(String key, {required int fallback}) async =>
      int.tryParse(values[key] ?? '') ?? fallback;
  @override
  Future<void> writeIntByKey(String key, int value) async =>
      values[key] = '$value';
  @override
  Future<bool> readBoolByKey(String key, {required bool fallback}) async =>
      values.containsKey(key) ? values[key] == 'true' : fallback;
  @override
  Future<void> writeBoolByKey(String key, bool value) async =>
      values[key] = '$value';
}
