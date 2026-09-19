import 'package:flutter/material.dart';

enum WarningSeverityMode { lenient, balanced, strict }

extension WarningSeverityModeX on WarningSeverityMode {
  String get label => switch (this) {
    WarningSeverityMode.lenient => 'Lenient',
    WarningSeverityMode.balanced => 'Balanced',
    WarningSeverityMode.strict => 'Strict',
  };
}

enum AccessibilityMode { off, readable, highContrast }

extension AccessibilityModeX on AccessibilityMode {
  String get label => switch (this) {
    AccessibilityMode.off => 'Off',
    AccessibilityMode.readable => 'Readable',
    AccessibilityMode.highContrast => 'High Contrast',
  };

  double get textMultiplier => switch (this) {
    AccessibilityMode.off => 1.0,
    AccessibilityMode.readable => 1.15,
    AccessibilityMode.highContrast => 1.25,
  };

  double get separatorThickness => switch (this) {
    AccessibilityMode.off => 1,
    AccessibilityMode.readable => 1.5,
    AccessibilityMode.highContrast => 2,
  };

  double get separatorAlpha => switch (this) {
    AccessibilityMode.off => 0.08,
    AccessibilityMode.readable => 0.12,
    AccessibilityMode.highContrast => 0.2,
  };
}

enum OverlayProfilePreset { compact, defaultProfile, readable, streaming }

extension OverlayProfilePresetX on OverlayProfilePreset {
  String get label => switch (this) {
    OverlayProfilePreset.compact => 'Compact',
    OverlayProfilePreset.defaultProfile => 'Default',
    OverlayProfilePreset.readable => 'Readable',
    OverlayProfilePreset.streaming => 'Streaming',
  };
}

enum SettingsThemePreset { sunrise, mint, cobalt, amber, mono }

extension SettingsThemePresetX on SettingsThemePreset {
  String get label => switch (this) {
    SettingsThemePreset.sunrise => 'Sunrise',
    SettingsThemePreset.mint => 'Mint',
    SettingsThemePreset.cobalt => 'Cobalt',
    SettingsThemePreset.amber => 'Amber',
    SettingsThemePreset.mono => 'Mono',
  };

  Color get color => switch (this) {
    SettingsThemePreset.sunrise => const Color(0xFFFF6F61),
    SettingsThemePreset.mint => const Color(0xFF5FD7A3),
    SettingsThemePreset.cobalt => const Color(0xFF5A8DFF),
    SettingsThemePreset.amber => const Color(0xFFFFC86B),
    SettingsThemePreset.mono => const Color(0xFFB7BDC8),
  };
}

enum StatusMetricId { fps, entities, logs, assets, timeline }

extension StatusMetricIdX on StatusMetricId {
  String get label => switch (this) {
    StatusMetricId.fps => 'FPS',
    StatusMetricId.entities => 'Entities',
    StatusMetricId.logs => 'Logs',
    StatusMetricId.assets => 'Assets',
    StatusMetricId.timeline => 'Timeline',
  };

  IconData get icon => switch (this) {
    StatusMetricId.fps => Icons.speed_rounded,
    StatusMetricId.entities => Icons.blur_linear_rounded,
    StatusMetricId.logs => Icons.article_outlined,
    StatusMetricId.assets => Icons.folder_outlined,
    StatusMetricId.timeline => Icons.movie_filter_rounded,
  };
}

class OverlayUiSettings {
  const OverlayUiSettings({
    required this.textScale,
    required this.cornerRadius,
    required this.themePreset,
    required this.compactness,
    required this.animationSpeed,
    required this.ecsWarnOnInactive,
    required this.ecsWarnOnNoSystems,
    required this.warningSeverity,
    required this.metricRefreshMs,
    required this.logLineClamp,
    required this.logsAutoScroll,
    required this.accessibilityMode,
    required this.showGrid,
    required this.gridSnappingEnabled,
    required this.gridSize,
  });

  const OverlayUiSettings.defaults()
    : textScale = 1.0,
      cornerRadius = 4,
      themePreset = SettingsThemePreset.sunrise,
      compactness = 1.0,
      animationSpeed = 1.0,
      ecsWarnOnInactive = true,
      ecsWarnOnNoSystems = true,
      warningSeverity = WarningSeverityMode.balanced,
      metricRefreshMs = 120,
      logLineClamp = 8,
      logsAutoScroll = true,
      accessibilityMode = AccessibilityMode.off,
      showGrid = true,
      gridSnappingEnabled = true,
      gridSize = 32;

  final double textScale;
  final double cornerRadius;
  final SettingsThemePreset themePreset;
  final double compactness;
  final double animationSpeed;
  final bool ecsWarnOnInactive;
  final bool ecsWarnOnNoSystems;
  final WarningSeverityMode warningSeverity;
  final double metricRefreshMs;
  final int logLineClamp;
  final bool logsAutoScroll;
  final AccessibilityMode accessibilityMode;
  final bool showGrid;
  final bool gridSnappingEnabled;
  final double gridSize;

  Color get themeColor => themePreset.color;
  double get effectiveTextScale => textScale * accessibilityMode.textMultiplier;

  OverlayUiSettings copyWith({
    double? textScale,
    double? cornerRadius,
    SettingsThemePreset? themePreset,
    double? compactness,
    double? animationSpeed,
    bool? ecsWarnOnInactive,
    bool? ecsWarnOnNoSystems,
    WarningSeverityMode? warningSeverity,
    double? metricRefreshMs,
    int? logLineClamp,
    bool? logsAutoScroll,
    AccessibilityMode? accessibilityMode,
    bool? showGrid,
    bool? gridSnappingEnabled,
    double? gridSize,
  }) {
    return OverlayUiSettings(
      textScale: textScale ?? this.textScale,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      themePreset: themePreset ?? this.themePreset,
      compactness: compactness ?? this.compactness,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      ecsWarnOnInactive: ecsWarnOnInactive ?? this.ecsWarnOnInactive,
      ecsWarnOnNoSystems: ecsWarnOnNoSystems ?? this.ecsWarnOnNoSystems,
      warningSeverity: warningSeverity ?? this.warningSeverity,
      metricRefreshMs: metricRefreshMs ?? this.metricRefreshMs,
      logLineClamp: logLineClamp ?? this.logLineClamp,
      logsAutoScroll: logsAutoScroll ?? this.logsAutoScroll,
      accessibilityMode: accessibilityMode ?? this.accessibilityMode,
      showGrid: showGrid ?? this.showGrid,
      gridSnappingEnabled: gridSnappingEnabled ?? this.gridSnappingEnabled,
      gridSize: gridSize ?? this.gridSize,
    );
  }
}
