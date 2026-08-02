part of 'editor_overlay.dart';

class _OverlaySettingsStore {
  const _OverlaySettingsStore(this._storageFuture);

  final Future<JustStandardStorage> _storageFuture;

  Future<_OverlayUiSettings> loadSettings() async {
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

    return _OverlayUiSettings(
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
          _SettingsThemePreset.values[themePresetIndex.clamp(
            0,
            _SettingsThemePreset.values.length - 1,
          )],
      compactness: _readDouble(
        values,
        OverlaySettingsPrefKeys.prefCompactness,
        fallback: 1.0,
      ),
      showStatusBadge: _readBool(
        values,
        OverlaySettingsPrefKeys.prefShowStatusBadge,
        fallback: true,
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
          _WarningSeverityMode.values[warningSeverityIndex.clamp(
            0,
            _WarningSeverityMode.values.length - 1,
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
          _AccessibilityMode.values[accessibilityModeIndex.clamp(
            0,
            _AccessibilityMode.values.length - 1,
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

  Future<void> saveSettings(_OverlayUiSettings settings) async {
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
        OverlaySettingsPrefKeys.prefShowStatusBadge,
        settings.showStatusBadge.toString(),
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
