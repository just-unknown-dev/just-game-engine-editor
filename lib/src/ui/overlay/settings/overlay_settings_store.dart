import 'dart:async';

import 'package:just_storage/just_storage.dart';

import '../../../core/constants/editor_constants.dart';
import '../settings/overlay_ui_settings.dart';

class OverlaySettingsStore {
  const OverlaySettingsStore(this._storageFuture);

  final Future<JustStandardStorage> _storageFuture;

  Future<OverlayUiSettings> loadSettings() async {
    final values = await (await _storageFuture).readAll();

    final themePresetIndex = _readInt(
      values,
      OverlaySettingsPrefKeys.prefThemePreset,
      fallback: 0,
    );
    final warningSeverityIndex = _readInt(
      values,
      OverlaySettingsPrefKeys.prefWarningSeverity,
      fallback: 1,
    );
    final accessibilityModeIndex = _readInt(
      values,
      OverlaySettingsPrefKeys.prefAccessibilityMode,
      fallback: 0,
    );

    return OverlayUiSettings(
      textScale: _readDouble(
        values,
        OverlaySettingsPrefKeys.prefTextScale,
        fallback: 1.0,
      ),
      cornerRadius: _readDouble(
        values,
        OverlaySettingsPrefKeys.prefCornerRadius,
        fallback: 4,
      ),
      themePreset:
          SettingsThemePreset.values[themePresetIndex.clamp(
            0,
            SettingsThemePreset.values.length - 1,
          )],
      compactness: _readDouble(
        values,
        OverlaySettingsPrefKeys.prefCompactness,
        fallback: 1.0,
      ),
      animationSpeed: _readDouble(
        values,
        OverlaySettingsPrefKeys.prefAnimationSpeed,
        fallback: 1.0,
      ),
      ecsWarnOnInactive: _readBool(
        values,
        OverlaySettingsPrefKeys.prefEcsWarnOnInactive,
        fallback: true,
      ),
      ecsWarnOnNoSystems: _readBool(
        values,
        OverlaySettingsPrefKeys.prefEcsWarnOnNoSystems,
        fallback: true,
      ),
      warningSeverity:
          WarningSeverityMode.values[warningSeverityIndex.clamp(
            0,
            WarningSeverityMode.values.length - 1,
          )],
      metricRefreshMs: _readDouble(
        values,
        OverlaySettingsPrefKeys.prefMetricRefreshMs,
        fallback: 120,
      ),
      logLineClamp: _readInt(
        values,
        OverlaySettingsPrefKeys.prefLogLineClamp,
        fallback: 8,
      ),
      logsAutoScroll: _readBool(
        values,
        OverlaySettingsPrefKeys.prefLogsAutoScroll,
        fallback: true,
      ),
      accessibilityMode:
          AccessibilityMode.values[accessibilityModeIndex.clamp(
            0,
            AccessibilityMode.values.length - 1,
          )],
      showGrid: _readBool(
        values,
        OverlaySettingsPrefKeys.prefShowGrid,
        fallback: true,
      ),
      gridSnappingEnabled: _readBool(
        values,
        OverlaySettingsPrefKeys.prefGridSnappingEnabled,
        fallback: true,
      ),
      gridSize: _readDouble(
        values,
        OverlaySettingsPrefKeys.prefGridSize,
        fallback: 32,
      ),
    );
  }

  Future<void> saveSettings(OverlayUiSettings settings) async {
    final storage = await _storageFuture;
    await Future.wait(<Future<void>>[
      storage.write(
        OverlaySettingsPrefKeys.prefTextScale,
        settings.textScale.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefCornerRadius,
        settings.cornerRadius.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefThemePreset,
        settings.themePreset.index.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefCompactness,
        settings.compactness.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefAnimationSpeed,
        settings.animationSpeed.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefEcsWarnOnInactive,
        settings.ecsWarnOnInactive.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefEcsWarnOnNoSystems,
        settings.ecsWarnOnNoSystems.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefWarningSeverity,
        settings.warningSeverity.index.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefMetricRefreshMs,
        settings.metricRefreshMs.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefLogLineClamp,
        settings.logLineClamp.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefLogsAutoScroll,
        settings.logsAutoScroll.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefAccessibilityMode,
        settings.accessibilityMode.index.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefShowGrid,
        settings.showGrid.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefGridSnappingEnabled,
        settings.gridSnappingEnabled.toString(),
      ),
      storage.write(
        OverlaySettingsPrefKeys.prefGridSize,
        settings.gridSize.toString(),
      ),
    ]);
  }

  /// Every stored key and its raw value; what module preferences decode from.
  Future<Map<String, String>> readAll() async =>
      (await _storageFuture).readAll().then(
        (values) => {for (final e in values.entries) e.key: e.value.toString()},
      );

  /// Stores one raw value under [key].
  Future<void> writeRaw(String key, String value) async =>
      (await _storageFuture).write(key, value);

  Future<bool> readBoolByKey(String key, {required bool fallback}) async {
    final raw = await (await _storageFuture).read(key);
    if (raw == null) {
      return fallback;
    }
    return raw == 'true';
  }

  Future<void> writeBoolByKey(String key, bool value) async {
    await (await _storageFuture).write(key, value.toString());
  }

  Future<int> readIntByKey(String key, {required int fallback}) async {
    final raw = await (await _storageFuture).read(key);
    if (raw == null) {
      return fallback;
    }
    return int.tryParse(raw) ?? fallback;
  }

  Future<void> writeIntByKey(String key, int value) async {
    await (await _storageFuture).write(key, value.toString());
  }

  static double _readDouble(
    Map<String, String> values,
    String key, {
    required double fallback,
  }) {
    return double.tryParse(values[key] ?? '') ?? fallback;
  }

  static int _readInt(
    Map<String, String> values,
    String key, {
    required int fallback,
  }) {
    return int.tryParse(values[key] ?? '') ?? fallback;
  }

  static bool _readBool(
    Map<String, String> values,
    String key, {
    required bool fallback,
  }) {
    final raw = values[key];
    if (raw == null) {
      return fallback;
    }
    return raw == 'true';
  }
}
