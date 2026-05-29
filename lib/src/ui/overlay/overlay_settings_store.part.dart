part of 'editor_overlay.dart';

class _OverlaySettingsStore {
  const _OverlaySettingsStore(this._storageFuture);

  final Future<JustStandardStorage> _storageFuture;

  static const String prefTextScale = 'editor.overlay.textScale';
  static const String prefCornerRadius = 'editor.overlay.cornerRadius';
  static const String prefThemePreset = 'editor.overlay.themePreset';
  static const String prefCompactness = 'editor.overlay.compactness';
  static const String prefShowStatusBadge = 'editor.overlay.showStatusBadge';
  static const String prefAnimationSpeed = 'editor.overlay.animationSpeed';
  static const String prefEcsWarnOnInactive =
      'editor.overlay.ecsWarnOnInactive';
  static const String prefEcsWarnOnNoSystems =
      'editor.overlay.ecsWarnOnNoSystems';
  static const String prefWarningSeverity = 'editor.overlay.warningSeverity';
  static const String prefMetricRefreshMs = 'editor.overlay.metricRefreshMs';
  static const String prefLogLineClamp = 'editor.overlay.logLineClamp';
  static const String prefLogsAutoScroll = 'editor.overlay.logsAutoScroll';
  static const String prefAccessibilityMode =
      'editor.overlay.accessibilityMode';

  Future<_OverlayUiSettings> loadSettings() async {
    final values = await (await _storageFuture).readAll();

    final themePresetIndex = _readInt(values, prefThemePreset, fallback: 0);
    final warningSeverityIndex = _readInt(
      values,
      prefWarningSeverity,
      fallback: 1,
    );
    final accessibilityModeIndex = _readInt(
      values,
      prefAccessibilityMode,
      fallback: 0,
    );

    return _OverlayUiSettings(
      textScale: _readDouble(values, prefTextScale, fallback: 1.0),
      cornerRadius: _readDouble(values, prefCornerRadius, fallback: 4),
      themePreset:
          _SettingsThemePreset.values[themePresetIndex.clamp(
            0,
            _SettingsThemePreset.values.length - 1,
          )],
      compactness: _readDouble(values, prefCompactness, fallback: 1.0),
      showStatusBadge: _readBool(values, prefShowStatusBadge, fallback: true),
      animationSpeed: _readDouble(values, prefAnimationSpeed, fallback: 1.0),
      ecsWarnOnInactive: _readBool(
        values,
        prefEcsWarnOnInactive,
        fallback: true,
      ),
      ecsWarnOnNoSystems: _readBool(
        values,
        prefEcsWarnOnNoSystems,
        fallback: true,
      ),
      warningSeverity:
          _WarningSeverityMode.values[warningSeverityIndex.clamp(
            0,
            _WarningSeverityMode.values.length - 1,
          )],
      metricRefreshMs: _readDouble(values, prefMetricRefreshMs, fallback: 120),
      logLineClamp: _readInt(values, prefLogLineClamp, fallback: 8),
      logsAutoScroll: _readBool(values, prefLogsAutoScroll, fallback: true),
      accessibilityMode:
          _AccessibilityMode.values[accessibilityModeIndex.clamp(
            0,
            _AccessibilityMode.values.length - 1,
          )],
    );
  }

  Future<void> saveSettings(_OverlayUiSettings settings) async {
    final storage = await _storageFuture;
    await Future.wait(<Future<void>>[
      storage.write(prefTextScale, settings.textScale.toString()),
      storage.write(prefCornerRadius, settings.cornerRadius.toString()),
      storage.write(prefThemePreset, settings.themePreset.index.toString()),
      storage.write(prefCompactness, settings.compactness.toString()),
      storage.write(prefShowStatusBadge, settings.showStatusBadge.toString()),
      storage.write(prefAnimationSpeed, settings.animationSpeed.toString()),
      storage.write(
        prefEcsWarnOnInactive,
        settings.ecsWarnOnInactive.toString(),
      ),
      storage.write(
        prefEcsWarnOnNoSystems,
        settings.ecsWarnOnNoSystems.toString(),
      ),
      storage.write(
        prefWarningSeverity,
        settings.warningSeverity.index.toString(),
      ),
      storage.write(prefMetricRefreshMs, settings.metricRefreshMs.toString()),
      storage.write(prefLogLineClamp, settings.logLineClamp.toString()),
      storage.write(prefLogsAutoScroll, settings.logsAutoScroll.toString()),
      storage.write(
        prefAccessibilityMode,
        settings.accessibilityMode.index.toString(),
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
