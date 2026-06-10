import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_storage/just_storage.dart';

import '../panels/entity_inspector_panel.dart';
import '../panels/scene_picker_panel.dart';
import '../panels/scene_tree_panel.dart';
import '../theme/editor_theme.dart';
import '../../core/plugin/editor_plugin.dart';

part 'overlay_settings_store.part.dart';
part 'overlay_dock_metrics.part.dart';
part 'overlay_settings_dialog.part.dart';

// ── Public overlay host ───────────────────────────────────────────────────────

/// Wraps the game surface with the runtime editor UI.
///
/// When [plugin.isVisible] is false the widget keeps the game interactive.
/// If [plugin.isStatusPanelVisible] is true, the compact dock can still be
/// shown independently. When visible it switches to a split layout: game
/// canvas on the left, editor panel on the right.
class JustGameEditorOverlay extends StatelessWidget {
  const JustGameEditorOverlay({
    super.key,
    required this.plugin,
    required this.gameChild,
  });

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return gameChild;

    return FocusScope(
      node: plugin.gameFocusScopeNode,
      child: Focus(
        autofocus: true,
        canRequestFocus: true,
        child: AnimatedBuilder(
          animation: plugin,
          builder: (context, _) {
            if (!plugin.isVisible) {
              if (!plugin.isStatusPanelVisible) {
                return AbsorbPointer(absorbing: false, child: gameChild);
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: <Widget>[
                      Positioned.fill(
                        child: AbsorbPointer(
                          absorbing: false,
                          child: gameChild,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _CompactStatusDock(
                          plugin: plugin,
                          maxDetailWidth: constraints.maxWidth,
                          maxDetailHeight: constraints.maxHeight,
                        ),
                      ),
                    ],
                  );
                },
              );
            }

            return ValueListenableBuilder<_OverlayUiSettings>(
              valueListenable: _overlayUiSettingsSignal,
              builder: (context, settings, _) {
                plugin.applyOverlaySettings(
                  showGrid: settings.showGrid,
                  gridSnappingEnabled: settings.gridSnappingEnabled,
                  gridSize: settings.gridSize,
                );
                return Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: _EditorSplitLayout(
                        plugin: plugin,
                        gameChild: gameChild,
                        settings: settings,
                      ),
                    ),
                    if (settings.showStatusBadge)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: IgnorePointer(
                          child: _EditorStatusBadge(settings: settings),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

enum _WarningSeverityMode { lenient, balanced, strict }

extension on _WarningSeverityMode {
  String get label => switch (this) {
    _WarningSeverityMode.lenient => 'Lenient',
    _WarningSeverityMode.balanced => 'Balanced',
    _WarningSeverityMode.strict => 'Strict',
  };
}

enum _AccessibilityMode { off, readable, highContrast }

extension on _AccessibilityMode {
  String get label => switch (this) {
    _AccessibilityMode.off => 'Off',
    _AccessibilityMode.readable => 'Readable',
    _AccessibilityMode.highContrast => 'High Contrast',
  };

  double get textMultiplier => switch (this) {
    _AccessibilityMode.off => 1.0,
    _AccessibilityMode.readable => 1.15,
    _AccessibilityMode.highContrast => 1.25,
  };

  double get separatorThickness => switch (this) {
    _AccessibilityMode.off => 1,
    _AccessibilityMode.readable => 1.5,
    _AccessibilityMode.highContrast => 2,
  };

  double get separatorAlpha => switch (this) {
    _AccessibilityMode.off => 0.08,
    _AccessibilityMode.readable => 0.12,
    _AccessibilityMode.highContrast => 0.2,
  };
}

enum _OverlayProfilePreset { compact, defaultProfile, readable, streaming }

extension on _OverlayProfilePreset {
  String get label => switch (this) {
    _OverlayProfilePreset.compact => 'Compact',
    _OverlayProfilePreset.defaultProfile => 'Default',
    _OverlayProfilePreset.readable => 'Readable',
    _OverlayProfilePreset.streaming => 'Streaming',
  };
}

class _EditorSplitLayout extends StatelessWidget {
  const _EditorSplitLayout({
    required this.plugin,
    required this.gameChild,
    required this.settings,
  });

  final JustGameEditorPlugin plugin;
  final Widget gameChild;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _EditorWorkspaceArea(plugin: plugin, gameChild: gameChild),
        ),
        SizedBox(
          width: 360,
          child: _EditorRightPanel(plugin: plugin, settings: settings),
        ),
      ],
    );
  }
}

class _EditorWorkspaceArea extends StatelessWidget {
  const _EditorWorkspaceArea({required this.plugin, required this.gameChild});

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            Positioned.fill(
              child: _GameCanvasArea(plugin: plugin, gameChild: gameChild),
            ),
            if (plugin.isStatusPanelVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _CompactStatusDock(
                  plugin: plugin,
                  maxDetailWidth: constraints.maxWidth,
                  maxDetailHeight: constraints.maxHeight,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GameCanvasArea extends StatelessWidget {
  const _GameCanvasArea({required this.plugin, required this.gameChild});

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        plugin.updateCanvasSize(size);

        return Listener(
          onPointerDown: plugin.onPointerDown,
          onPointerMove: plugin.onPointerMove,
          onPointerUp: plugin.onPointerUp,
          child: AbsorbPointer(absorbing: true, child: gameChild),
        );
      },
    );
  }
}

// ── Right panel ───────────────────────────────────────────────────────────────

enum _StatusMetricId { fps, entities, memory, logs }

extension on _StatusMetricId {
  _StatusDetailSection get section => switch (this) {
    _StatusMetricId.fps => _StatusDetailSection.performance,
    _StatusMetricId.entities => _StatusDetailSection.ecs,
    _StatusMetricId.memory => _StatusDetailSection.memory,
    _StatusMetricId.logs => _StatusDetailSection.logs,
  };

  String get label => switch (this) {
    _StatusMetricId.fps => 'FPS',
    _StatusMetricId.entities => 'Entities',
    _StatusMetricId.memory => 'Runtime',
    _StatusMetricId.logs => 'Logs',
  };

  IconData get icon => switch (this) {
    _StatusMetricId.fps => Icons.speed_rounded,
    _StatusMetricId.entities => Icons.blur_linear_rounded,
    _StatusMetricId.memory => Icons.memory_rounded,
    _StatusMetricId.logs => Icons.article_outlined,
  };
}

enum _StatusDetailSection { performance, ecs, memory, logs }

enum _SettingsThemePreset { sunrise, mint, cobalt, amber, mono }

extension on _SettingsThemePreset {
  String get label => switch (this) {
    _SettingsThemePreset.sunrise => 'Sunrise',
    _SettingsThemePreset.mint => 'Mint',
    _SettingsThemePreset.cobalt => 'Cobalt',
    _SettingsThemePreset.amber => 'Amber',
    _SettingsThemePreset.mono => 'Mono',
  };

  Color get color => switch (this) {
    _SettingsThemePreset.sunrise => const Color(0xFFFF6F61),
    _SettingsThemePreset.mint => const Color(0xFF5FD7A3),
    _SettingsThemePreset.cobalt => const Color(0xFF5A8DFF),
    _SettingsThemePreset.amber => const Color(0xFFFFC86B),
    _SettingsThemePreset.mono => const Color(0xFFB7BDC8),
  };
}

class _OverlayUiSettings {
  const _OverlayUiSettings({
    required this.textScale,
    required this.cornerRadius,
    required this.themePreset,
    required this.compactness,
    required this.showStatusBadge,
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

  const _OverlayUiSettings.defaults()
    : textScale = 1.0,
      cornerRadius = 4,
      themePreset = _SettingsThemePreset.sunrise,
      compactness = 1.0,
      showStatusBadge = true,
      animationSpeed = 1.0,
      ecsWarnOnInactive = true,
      ecsWarnOnNoSystems = true,
      warningSeverity = _WarningSeverityMode.balanced,
      metricRefreshMs = 120,
      logLineClamp = 8,
      logsAutoScroll = true,
      accessibilityMode = _AccessibilityMode.off,
      showGrid = true,
      gridSnappingEnabled = true,
      gridSize = 32;

  final double textScale;
  final double cornerRadius;
  final _SettingsThemePreset themePreset;
  final double compactness;
  final bool showStatusBadge;
  final double animationSpeed;
  final bool ecsWarnOnInactive;
  final bool ecsWarnOnNoSystems;
  final _WarningSeverityMode warningSeverity;
  final double metricRefreshMs;
  final int logLineClamp;
  final bool logsAutoScroll;
  final _AccessibilityMode accessibilityMode;
  final bool showGrid;
  final bool gridSnappingEnabled;
  final double gridSize;

  Color get themeColor => themePreset.color;
  double get effectiveTextScale => textScale * accessibilityMode.textMultiplier;

  _OverlayUiSettings copyWith({
    double? textScale,
    double? cornerRadius,
    _SettingsThemePreset? themePreset,
    double? compactness,
    bool? showStatusBadge,
    double? animationSpeed,
    bool? ecsWarnOnInactive,
    bool? ecsWarnOnNoSystems,
    _WarningSeverityMode? warningSeverity,
    double? metricRefreshMs,
    int? logLineClamp,
    bool? logsAutoScroll,
    _AccessibilityMode? accessibilityMode,
    bool? showGrid,
    bool? gridSnappingEnabled,
    double? gridSize,
  }) {
    return _OverlayUiSettings(
      textScale: textScale ?? this.textScale,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      themePreset: themePreset ?? this.themePreset,
      compactness: compactness ?? this.compactness,
      showStatusBadge: showStatusBadge ?? this.showStatusBadge,
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

final ValueNotifier<_OverlayUiSettings> _overlayUiSettingsSignal =
    ValueNotifier<_OverlayUiSettings>(const _OverlayUiSettings.defaults());
bool _overlayUiSettingsLoaded = false;
Future<void>? _overlayUiSettingsLoadFuture;

final _OverlaySettingsStore _overlaySettingsStore = _OverlaySettingsStore(
  JustStorage.standard(),
);

extension on _StatusDetailSection {
  String get title => switch (this) {
    _StatusDetailSection.performance => 'Performance Details',
    _StatusDetailSection.ecs => 'ECS Details',
    _StatusDetailSection.memory => 'Runtime Details',
    _StatusDetailSection.logs => 'Log Details',
  };

  IconData get icon => switch (this) {
    _StatusDetailSection.performance => Icons.bolt_rounded,
    _StatusDetailSection.ecs => Icons.hub_rounded,
    _StatusDetailSection.memory => Icons.monitor_heart_rounded,
    _StatusDetailSection.logs => Icons.subject_rounded,
  };
}

class _CompactStatusDock extends StatefulWidget {
  const _CompactStatusDock({
    required this.plugin,
    required this.maxDetailWidth,
    required this.maxDetailHeight,
  });

  final JustGameEditorPlugin plugin;
  final double maxDetailWidth;
  final double maxDetailHeight;

  static const double _panelHeight = 56;
  static const double _detailWidth = 350;

  @override
  State<_CompactStatusDock> createState() => _CompactStatusDockState();
}

class _CompactStatusDockState extends State<_CompactStatusDock> {
  _StatusMetricId? _selectedMetric;
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _settingsAnchorKey = GlobalKey();
  final Map<_StatusMetricId, GlobalKey> _anchorKeys =
      <_StatusMetricId, GlobalKey>{};
  int _lastMetricSampleMs = 0;
  _DockMetricsSnapshot? _displayMetrics;
  bool _isSettingsOpen = false;

  GlobalKey _anchorKeyFor(_StatusMetricId metric) {
    return _anchorKeys.putIfAbsent(metric, GlobalKey.new);
  }

  void _selectMetric(_StatusMetricId metric) {
    setState(() {
      _isSettingsOpen = false;
      _selectedMetric = _selectedMetric == metric ? null : metric;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedMetric = null;
      _isSettingsOpen = false;
    });
  }

  void _updateSettings(_OverlayUiSettings settings) {
    _overlayUiSettingsSignal.value = settings;
    _persistSettings(settings);
  }

  void _toggleSettings() {
    setState(() {
      _selectedMetric = null;
      _isSettingsOpen = !_isSettingsOpen;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPersistedSettings();
  }

  Future<void> _loadPersistedSettings() async {
    if (_overlayUiSettingsLoaded) {
      return;
    }
    if (_overlayUiSettingsLoadFuture != null) {
      await _overlayUiSettingsLoadFuture;
      return;
    }

    _overlayUiSettingsLoadFuture = _loadPersistedSettingsOnce();
    await _overlayUiSettingsLoadFuture;
  }

  Future<void> _loadPersistedSettingsOnce() async {
    try {
      final settings = await _overlaySettingsStore.loadSettings();
      _overlayUiSettingsSignal.value = settings;
    } catch (error, stackTrace) {
      debugPrint('Failed to load overlay settings: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _overlayUiSettingsLoaded = true;
    }
  }

  Future<void> _persistSettings(_OverlayUiSettings settings) async {
    try {
      await _overlaySettingsStore.saveSettings(settings);
    } catch (error, stackTrace) {
      debugPrint('Failed to save overlay settings: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  double _detailWidth() {
    final availableWidth = widget.maxDetailWidth - 24;
    if (availableWidth <= 0) {
      return 0;
    }
    return math.min(_CompactStatusDock._detailWidth, availableWidth);
  }

  double _detailLeftForKey(GlobalKey anchorKey, double detailWidth) {
    final stackContext = _stackKey.currentContext;
    final anchorContext = anchorKey.currentContext;
    if (stackContext == null || anchorContext == null) {
      return 12;
    }

    final stackBox = stackContext.findRenderObject() as RenderBox?;
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    if (stackBox == null ||
        anchorBox == null ||
        !stackBox.hasSize ||
        !anchorBox.hasSize) {
      return 12;
    }

    final anchorCenter = anchorBox.localToGlobal(
      anchorBox.size.center(Offset.zero),
      ancestor: stackBox,
    );
    final minLeft = 12.0;
    final maxLeft = math.max(minLeft, widget.maxDetailWidth - detailWidth - 12);
    return (anchorCenter.dx - detailWidth / 2).clamp(minLeft, maxLeft);
  }

  double _detailLeftFor(_StatusMetricId metric, double detailWidth) {
    return _detailLeftForKey(_anchorKeyFor(metric), detailWidth);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.plugin.debuggerController,
      builder: (context, _) {
        final controller = widget.plugin.debuggerController;
        final liveMetrics = _DockMetricsSnapshot.fromController(controller);

        final refreshMs = _overlayUiSettingsSignal.value.metricRefreshMs
            .clamp(33, 2000)
            .round();
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final shouldSample =
            _lastMetricSampleMs == 0 ||
            nowMs - _lastMetricSampleMs >= refreshMs;

        if (shouldSample) {
          _lastMetricSampleMs = nowMs;
          _displayMetrics = liveMetrics;
        }

        final sampledMetrics = shouldSample
            ? liveMetrics
            : (_displayMetrics ?? liveMetrics);
        final snapshot = sampledMetrics.snapshot;
        final performance = sampledMetrics.performance;
        final memory = sampledMetrics.memory;
        final logs = sampledMetrics.logs;
        final health = sampledMetrics.health;

        final warningCount = logs
            .where((entry) => entry.level == DebuggerLogLevel.warning)
            .length;
        final errorCount = logs
            .where((entry) => entry.level == DebuggerLogLevel.error)
            .length;
        final detailMaxHeight =
            widget.maxDetailHeight - _CompactStatusDock._panelHeight - 40;
        final detailHeight = detailMaxHeight.clamp(180.0, 320.0).toDouble();
        final settingsPanelHeight = detailMaxHeight
            .clamp(260.0, 460.0)
            .toDouble();
        final floatingPanelHeight = _isSettingsOpen
            ? settingsPanelHeight
            : (_selectedMetric != null ? detailHeight : 0.0);
        final dockHeight =
            _CompactStatusDock._panelHeight +
            (floatingPanelHeight > 0 ? floatingPanelHeight + 12.0 : 0.0);

        return ValueListenableBuilder<_OverlayUiSettings>(
          valueListenable: _overlayUiSettingsSignal,
          builder: (context, settings, _) {
            final panelPadding = 12.0 * settings.compactness;
            final panelVertical = 3.0 * settings.compactness;
            final animationMs = (220 / settings.animationSpeed).clamp(80, 420);
            return AnimatedContainer(
              duration: Duration(milliseconds: animationMs.round()),
              curve: Curves.easeOutCubic,
              height: dockHeight,
              child: Material(
                color: Colors.transparent,
                child: Stack(
                  key: _stackKey,
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: _CompactStatusDock._panelHeight,
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(0),
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                            left: BorderSide(
                              color: Colors.white.withValues(alpha: 0.04),
                            ),
                            right: BorderSide(
                              color: Colors.white.withValues(alpha: 0.04),
                            ),
                            bottom: BorderSide(
                              color: Colors.white.withValues(alpha: 0.04),
                            ),
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x55000000),
                              blurRadius: 14,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: panelPadding,
                            vertical: panelVertical,
                          ),
                          child: Column(
                            children: <Widget>[
                              Expanded(
                                child: Row(
                                  children: <Widget>[
                                    _StatusMetricButton(
                                      metric: _StatusMetricId.fps,
                                      anchorKey: _anchorKeyFor(
                                        _StatusMetricId.fps,
                                      ),
                                      value:
                                          '${performance.currentFps} fps • ${performance.lastUpdateMs.toStringAsFixed(1)} ms',
                                      accent: settings.themeColor,
                                      isSelected:
                                          _selectedMetric ==
                                          _StatusMetricId.fps,
                                      onTap: _selectMetric,
                                      settings: settings,
                                    ),
                                    _StatusSeparator(settings: settings),
                                    _StatusMetricButton(
                                      metric: _StatusMetricId.entities,
                                      anchorKey: _anchorKeyFor(
                                        _StatusMetricId.entities,
                                      ),
                                      value: '${snapshot.entityCount}',
                                      accent: const Color(0xFF7DE6B1),
                                      isSelected:
                                          _selectedMetric ==
                                          _StatusMetricId.entities,
                                      onTap: _selectMetric,
                                      settings: settings,
                                    ),
                                    _StatusSeparator(settings: settings),
                                    _StatusMetricButton(
                                      metric: _StatusMetricId.memory,
                                      anchorKey: _anchorKeyFor(
                                        _StatusMetricId.memory,
                                      ),
                                      value: _formatBytes(memory.rssBytes),
                                      accent: health.hasWarnings
                                          ? EditorTheme.warning
                                          : const Color(0xFFFFC86B),
                                      isSelected:
                                          _selectedMetric ==
                                          _StatusMetricId.memory,
                                      onTap: _selectMetric,
                                      settings: settings,
                                    ),
                                    _StatusSeparator(settings: settings),
                                    _StatusMetricButton(
                                      metric: _StatusMetricId.logs,
                                      anchorKey: _anchorKeyFor(
                                        _StatusMetricId.logs,
                                      ),
                                      value: errorCount > 0
                                          ? '${logs.length} total • $errorCount err'
                                          : '${logs.length} total • $warningCount warn',
                                      accent: const Color(0xFFD9A7FF),
                                      isSelected:
                                          _selectedMetric ==
                                          _StatusMetricId.logs,
                                      onTap: _selectMetric,
                                      settings: settings,
                                    ),
                                    const Spacer(),
                                    _EditorSettingsButton(
                                      anchorKey: _settingsAnchorKey,
                                      settings: settings,
                                      isSelected: _isSettingsOpen,
                                      onPressed: _toggleSettings,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_selectedMetric != null)
                      Positioned(
                        left: _detailLeftFor(_selectedMetric!, _detailWidth()),
                        bottom: _CompactStatusDock._panelHeight + 12,
                        child: SizedBox(
                          width: _detailWidth(),
                          child: _StatusDetailCard(
                            controller: controller,
                            section: _selectedMetric!.section,
                            onClose: _clearSelection,
                            maxHeight: detailMaxHeight,
                            settings: settings,
                          ),
                        ),
                      ),
                    if (_isSettingsOpen)
                      Positioned(
                        left: _detailLeftForKey(
                          _settingsAnchorKey,
                          math.min(
                            420,
                            math.max(280, widget.maxDetailWidth - 24),
                          ),
                        ),
                        bottom: _CompactStatusDock._panelHeight + 12,
                        child: SizedBox(
                          width: math.min(
                            420,
                            math.max(280, widget.maxDetailWidth - 24),
                          ),
                          child: _EditorSettingsPanel(
                            initial: _overlayUiSettingsSignal.value,
                            onChanged: _updateSettings,
                            onClose: _toggleSettings,
                            maxHeight: settingsPanelHeight,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StatusMetricButton extends StatelessWidget {
  const _StatusMetricButton({
    required this.metric,
    required this.anchorKey,
    required this.value,
    required this.accent,
    required this.isSelected,
    required this.onTap,
    required this.settings,
  });

  final _StatusMetricId metric;
  final GlobalKey anchorKey;
  final String value;
  final Color accent;
  final bool isSelected;
  final ValueChanged<_StatusMetricId> onTap;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: anchorKey,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(metric),
          borderRadius: BorderRadius.circular(settings.cornerRadius),
          child: Ink(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 7 * settings.compactness,
                vertical: 2 * settings.compactness,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(metric.icon, size: 11, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        metric.label,
                        style: TextStyle(
                          fontSize: 9 * settings.effectiveTextScale,
                          fontWeight: FontWeight.w500,
                          color: EditorTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: 6 * settings.compactness),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10 * settings.effectiveTextScale,
                      fontWeight: FontWeight.w500,
                      color: EditorTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDetailCard extends StatelessWidget {
  const _StatusDetailCard({
    required this.controller,
    required this.section,
    required this.onClose,
    required this.maxHeight,
    required this.settings,
  });

  final JustDebuggerController controller;
  final _StatusDetailSection section;
  final VoidCallback onClose;
  final double maxHeight;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight.clamp(180, 320)),
            decoration: BoxDecoration(
              color: const Color(0xF41B1B1B),
              borderRadius: BorderRadius.circular(settings.cornerRadius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: EditorTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          section.icon,
                          size: 12,
                          color: EditorTheme.primaryBright,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              section.title,
                              style: TextStyle(
                                fontSize: 12 * settings.effectiveTextScale,
                                fontWeight: FontWeight.w500,
                                color: EditorTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text.rich(_detailSubtitle(section, controller)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                        color: EditorTheme.textSecondary,
                        iconSize: 16,
                        splashRadius: 16,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildDetailContent(controller),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  TextSpan _detailSubtitle(
    _StatusDetailSection section,
    JustDebuggerController controller,
  ) {
    final logs = controller.logs;
    final runtimeWarningThreshold = switch (settings.warningSeverity) {
      _WarningSeverityMode.lenient => 3,
      _WarningSeverityMode.balanced => 1,
      _WarningSeverityMode.strict => 1,
    };
    final runtimeWarningCount = controller.health.messages.length;
    final runtimeWarn = runtimeWarningCount >= runtimeWarningThreshold;
    final runtimeHealth = runtimeWarn
        ? '$runtimeWarningCount alerts'
        : 'Healthy';
    final hasNoSystems = controller.snapshot.systemCount == 0;
    final inactiveCount =
        controller.snapshot.entityCount - controller.snapshot.activeEntityCount;
    final inactiveRatio = controller.snapshot.entityCount <= 0
        ? 0.0
        : inactiveCount / controller.snapshot.entityCount;
    final inactiveThreshold = switch (settings.warningSeverity) {
      _WarningSeverityMode.lenient => 0.5,
      _WarningSeverityMode.balanced => 0.2,
      _WarningSeverityMode.strict => 0.05,
    };
    final hasInactive = inactiveRatio >= inactiveThreshold;
    final ecsWarning = hasNoSystems && settings.ecsWarnOnNoSystems
        ? 'No systems'
        : hasInactive && settings.ecsWarnOnInactive
        ? 'Inactive entities'
        : 'Healthy';
    final ecsColor =
        (hasNoSystems && settings.ecsWarnOnNoSystems) ||
            (hasInactive && settings.ecsWarnOnInactive)
        ? EditorTheme.warning
        : const Color(0xFF6DE0A7);
    final performanceStatus = controller.performance.isOverBudget
        ? 'Over budget'
        : 'Within frame budget';
    final statusColor = controller.performance.isOverBudget
        ? EditorTheme.warning
        : const Color(0xFF6DE0A7);
    final healthColor = runtimeWarn
        ? EditorTheme.warning
        : const Color(0xFF6DE0A7);
    return switch (section) {
      _StatusDetailSection.performance => TextSpan(
        style: const TextStyle(fontSize: 9, color: EditorTheme.textMuted),
        children: <InlineSpan>[
          TextSpan(text: 'Frame ${controller.performance.frameNumber} • '),
          TextSpan(
            text: '${controller.performance.currentFps} FPS',
            style: const TextStyle(color: EditorTheme.textPrimary),
          ),
          const TextSpan(text: ' • '),
          TextSpan(
            text: performanceStatus,
            style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      _StatusDetailSection.ecs => TextSpan(
        style: const TextStyle(fontSize: 9, color: EditorTheme.textMuted),
        children: <InlineSpan>[
          TextSpan(text: '${controller.snapshot.entityCount} entities'),
          const TextSpan(text: ' • '),
          TextSpan(
            text: '${controller.snapshot.systemCount} systems',
            style: const TextStyle(color: EditorTheme.textPrimary),
          ),
          const TextSpan(text: ' • '),
          TextSpan(
            text: ecsWarning,
            style: TextStyle(color: ecsColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      _StatusDetailSection.memory => TextSpan(
        style: const TextStyle(fontSize: 9, color: EditorTheme.textMuted),
        children: <InlineSpan>[
          TextSpan(
            text: '${_formatBytes(controller.memory.rssBytes)} RSS',
            style: const TextStyle(color: EditorTheme.textPrimary),
          ),
          const TextSpan(text: ' • '),
          TextSpan(
            text: runtimeHealth,
            style: TextStyle(color: healthColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      _StatusDetailSection.logs => TextSpan(
        style: const TextStyle(fontSize: 9, color: EditorTheme.textMuted),
        children: <InlineSpan>[
          TextSpan(text: '${logs.length} captured events • latest '),
          TextSpan(
            text: logs.isEmpty ? '--' : logs.last.timeLabel,
            style: const TextStyle(color: EditorTheme.textPrimary),
          ),
        ],
      ),
    };
  }

  Widget _buildDetailContent(JustDebuggerController controller) {
    return switch (section) {
      _StatusDetailSection.performance => _PerformanceDetailContent(
        controller: controller,
        settings: settings,
      ),
      _StatusDetailSection.ecs => _EcsDetailContent(
        controller: controller,
        settings: settings,
      ),
      _StatusDetailSection.memory => _RuntimeDetailContent(
        controller: controller,
        settings: settings,
      ),
      _StatusDetailSection.logs => _LogsDetailContent(
        controller: controller,
        settings: settings,
      ),
    };
  }
}

class _EditorSettingsButton extends StatelessWidget {
  const _EditorSettingsButton({
    required this.anchorKey,
    required this.settings,
    required this.isSelected,
    required this.onPressed,
  });

  final GlobalKey anchorKey;
  final _OverlayUiSettings settings;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: anchorKey,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: 'Editor settings',
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(settings.cornerRadius),
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    color: settings.themeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(settings.cornerRadius),
                    border: Border.all(
                      color: settings.themeColor.withValues(alpha: 0.28),
                    ),
                  )
                : null,
            padding: EdgeInsets.symmetric(
              horizontal: 8 * settings.compactness,
              vertical: 6 * settings.compactness,
            ),
            child: Icon(
              Icons.tune_rounded,
              size: 15 * settings.effectiveTextScale,
              color: settings.themeColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusSeparator extends StatelessWidget {
  const _StatusSeparator({required this.settings});

  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: settings.accessibilityMode.separatorThickness,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: Colors.white.withValues(
        alpha: settings.accessibilityMode.separatorAlpha,
      ),
    );
  }
}

class _DetailStatTile extends StatelessWidget {
  const _DetailStatTile({
    required this.label,
    required this.value,
    required this.settings,
  });

  final String label;
  final String value;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceBg,
        borderRadius: BorderRadius.circular(settings.cornerRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            spacing: 8,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11 * settings.effectiveTextScale,
                  color: EditorTheme.textMuted,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12 * settings.effectiveTextScale,
                  fontWeight: FontWeight.w700,
                  color: EditorTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailSectionCard extends StatefulWidget {
  const _DetailSectionCard({
    required this.sectionId,
    required this.title,
    required this.child,
    required this.settings,
  });

  final String sectionId;
  final String title;
  final Widget child;
  final _OverlayUiSettings settings;

  @override
  State<_DetailSectionCard> createState() => _DetailSectionCardState();
}

class _DetailSectionCardState extends State<_DetailSectionCard> {
  bool _collapsed = false;

  String get _prefKey => 'editor.overlay.sectionCollapsed.${widget.sectionId}';

  @override
  void initState() {
    super.initState();
    _loadCollapsed();
  }

  Future<void> _loadCollapsed() async {
    final collapsed = await _overlaySettingsStore.readBoolByKey(
      _prefKey,
      fallback: false,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _collapsed = collapsed;
    });
  }

  Future<void> _toggleCollapsed() async {
    setState(() {
      _collapsed = !_collapsed;
    });
    await _overlaySettingsStore.writeBoolByKey(_prefKey, _collapsed);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceDark,
        borderRadius: BorderRadius.circular(widget.settings.cornerRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: _toggleCollapsed,
            borderRadius: BorderRadius.circular(widget.settings.cornerRadius),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 10 * widget.settings.effectiveTextScale,
                      fontWeight: FontWeight.w700,
                      color: EditorTheme.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  _collapsed
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                  color: EditorTheme.textMuted,
                  size: 16,
                ),
              ],
            ),
          ),
          if (!_collapsed) ...<Widget>[
            const SizedBox(height: 10),
            widget.child,
          ],
        ],
      ),
    );
  }
}

class _PerformanceDetailContent extends StatelessWidget {
  const _PerformanceDetailContent({
    required this.controller,
    required this.settings,
  });

  final JustDebuggerController controller;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final performance = controller.performance;
    final timings = performance.systemTimesMs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: <Widget>[
            _DetailStatTile(
              label: 'FPS',
              value: '${performance.currentFps}',
              settings: settings,
            ),
            _DetailStatTile(
              label: 'Update Time',
              value: '${performance.lastUpdateMs.toStringAsFixed(1)} ms',
              settings: settings,
            ),
            _DetailStatTile(
              label: 'Budget Left',
              value: '${performance.budgetRemainingMs.toStringAsFixed(1)} ms',
              settings: settings,
            ),
            _DetailStatTile(
              label: 'Frame',
              value: '${performance.frameNumber}',
              settings: settings,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'performance_hottest_systems',
          title: 'Hottest Systems',
          settings: settings,
          child: Column(
            children: timings
                .take(5)
                .map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 10,
                              color: EditorTheme.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '${entry.value.toStringAsFixed(2)} ms',
                          style: const TextStyle(
                            fontSize: 10,
                            color: EditorTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _EcsDetailContent extends StatelessWidget {
  const _EcsDetailContent({required this.controller, required this.settings});

  final JustDebuggerController controller;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final components = snapshot.componentUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: <Widget>[
            _DetailStatTile(
              label: 'Entities',
              value: '${snapshot.entityCount}',
              settings: settings,
            ),
            _DetailStatTile(
              label: 'Active Entities',
              value: '${snapshot.activeEntityCount}',
              settings: settings,
            ),
            _DetailStatTile(
              label: 'Systems',
              value: '${snapshot.systemCount}',
              settings: settings,
            ),
            _DetailStatTile(
              label: 'Archetypes',
              value: '${snapshot.archetypeCount}',
              settings: settings,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'ecs_top_components',
          title: 'Top Components',
          settings: settings,
          child: Column(
            children: components
                .take(6)
                .map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 10,
                              color: EditorTheme.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '${entry.value}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: EditorTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _RuntimeDetailContent extends StatelessWidget {
  const _RuntimeDetailContent({
    required this.controller,
    required this.settings,
  });

  final JustDebuggerController controller;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final memory = controller.memory;
    final health = controller.health;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: <Widget>[
            _DetailStatTile(
              label: 'App RSS',
              value: _formatBytes(memory.rssBytes),
              settings: settings,
            ),
            _DetailStatTile(
              label: 'Entities',
              value: '${memory.entityCount}',
              settings: settings,
            ),
            _DetailStatTile(
              label: 'Components',
              value: '${memory.componentCount}',
              settings: settings,
            ),
            _DetailStatTile(
              label: 'Warnings',
              value: '${health.messages.length}',
              settings: settings,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'runtime_memory_counters',
          title: 'Memory Counters',
          settings: settings,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: memory.counters.entries
                .map((entry) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${entry.key}: ${entry.value}',
                      style: const TextStyle(
                        color: EditorTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'runtime_current_signals',
          title: 'Current Signals',
          settings: settings,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: health.hasWarnings
                ? health.messages
                      .map((message) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 14,
                                  color: EditorTheme.warning,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  message,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: EditorTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                      .toList(growable: false)
                : const <Widget>[
                    Text(
                      'No active warnings. Runtime metrics look stable.',
                      style: TextStyle(
                        fontSize: 10,
                        color: EditorTheme.textSecondary,
                      ),
                    ),
                  ],
          ),
        ),
      ],
    );
  }
}

class _LogsDetailContent extends StatelessWidget {
  const _LogsDetailContent({required this.controller, required this.settings});

  final JustDebuggerController controller;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final logs = settings.logsAutoScroll
        ? controller.logs.reversed
              .take(settings.logLineClamp)
              .toList(growable: false)
        : controller.logs.take(settings.logLineClamp).toList(growable: false);
    final infoCount = controller.logs
        .where((entry) => entry.level == DebuggerLogLevel.info)
        .length;
    final warningCount = controller.logs
        .where((entry) => entry.level == DebuggerLogLevel.warning)
        .length;
    final errorCount = controller.logs
        .where((entry) => entry.level == DebuggerLogLevel.error)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: <Widget>[
            _DetailStatTile(
              label: 'Total Logs',
              value: '${controller.logs.length}',
              settings: settings,
            ),
            _DetailStatTile(
              label: 'Info',
              value: '$infoCount',
              settings: settings,
            ),
            _DetailStatTile(
              label: 'Warnings',
              value: '$warningCount',
              settings: settings,
            ),
            _DetailStatTile(
              label: 'Errors',
              value: '$errorCount',
              settings: settings,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'logs_recent_entries',
          title: 'Recent Entries',
          settings: settings,
          child: SingleChildScrollView(
            child: Column(
              children: logs.isEmpty
                  ? const <Widget>[
                      Text(
                        'No log entries captured yet.',
                        style: TextStyle(
                          fontSize: 10,
                          color: EditorTheme.textSecondary,
                        ),
                      ),
                    ]
                  : logs
                        .map((entry) {
                          final color = switch (entry.level) {
                            DebuggerLogLevel.info => const Color(0xFF7CD7FF),
                            DebuggerLogLevel.warning => EditorTheme.warning,
                            DebuggerLogLevel.error => EditorTheme.errorLight,
                          };
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),

                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  spacing: 4,
                                  children: <Widget>[
                                    Text(
                                      '${entry.category.toUpperCase()} • ${entry.timeLabel}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      entry.message,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: EditorTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        })
                        .toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }

  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }

  final precision = unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
}

// ── Right panel ───────────────────────────────────────────────────────────────

class _EditorRightPanel extends StatelessWidget {
  const _EditorRightPanel({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EditorTheme.panelBg,
      child: SafeArea(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: EditorTheme.border, width: 1),
            ),
          ),
          child: ListenableBuilder(
            listenable: plugin.sceneState,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _HeaderBar(plugin: plugin, settings: settings),
                  const Divider(height: 1, color: EditorTheme.border),
                  if (!plugin.sceneState.hasScene)
                    Expanded(
                      child: ScenePickerPanel(
                        onSceneSelected: (name) => plugin.openScene(name),
                      ),
                    )
                  else ...<Widget>[
                    // Scene tree (fixed height)
                    SizedBox(
                      height: 220,
                      child: SceneTreePanel(
                        sceneState: plugin.sceneState,
                        world: plugin.engine.world,
                        onCreateEntity: plugin.createEntity,
                        onCreateGroup: plugin.createGroup,
                        onCreateGroupFrom: (entity) =>
                            plugin.createGroup(children: [entity]),
                        onDeleteEntity: plugin.deleteEntity,
                        onCopyEntity: plugin.copyEntity,
                        onPasteEntity: plugin.pasteEntity,
                        onReparentEntity: plugin.reparentEntity,
                      ),
                    ),
                    const Divider(height: 1, color: EditorTheme.border),
                    // Inspector (fills remaining space)
                    Expanded(
                      child: EntityInspectorPanel(
                        sceneState: plugin.sceneState,
                        world: plugin.engine.world,
                        onDetachFromParent: plugin.detachFromParent,
                        onGroupSelection: plugin.createGroup,
                      ),
                    ),
                    // Save button footer
                    _SaveFooter(plugin: plugin, settings: settings),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Header bar ────────────────────────────────────────────────────────────────

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final sceneName = plugin.sceneState.activeScene?.name;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          if (sceneName != null) ...<Widget>[
            Tooltip(
              message: 'Back to scene list',
              child: IconButton(
                onPressed: plugin.sceneState.closeScene,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                iconSize: 14,
                color: settings.themeColor,
                splashRadius: 16,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ),
            const SizedBox(width: 4),
          ] else ...<Widget>[
            const Icon(
              Icons.tune_rounded,
              color: EditorTheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Just Runtime Editor',
                  style: TextStyle(
                    fontSize: 13 * settings.effectiveTextScale,
                    fontWeight: FontWeight.w700,
                    color: EditorTheme.textPrimary,
                  ),
                ),
                if (sceneName != null)
                  Text(
                    sceneName,
                    style: TextStyle(
                      fontSize: 10 * settings.effectiveTextScale,
                      color: settings.themeColor.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          _Badge(label: 'JIT', accent: settings.themeColor, settings: settings),
        ],
      ),
    );
  }
}

// ── Save footer ───────────────────────────────────────────────────────────────

class _SaveFooter extends StatelessWidget {
  const _SaveFooter({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final isDirty = plugin.sceneState.isDirty;

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: EditorTheme.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            if (isDirty)
              Padding(
                padding: EdgeInsets.only(right: 8),
                child: _Badge(
                  label: 'UNSAVED',
                  accent: EditorTheme.warning,
                  settings: settings,
                ),
              ),
            const Spacer(),
            SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: isDirty ? () => plugin.saveScene() : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: EditorTheme.buttonBg,
                  disabledBackgroundColor: EditorTheme.surfaceBg,
                  foregroundColor: settings.themeColor,
                  disabledForegroundColor: EditorTheme.border,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(settings.cornerRadius),
                  ),
                ),
                icon: const Icon(Icons.save_rounded, size: 14),
                label: Text(
                  'Save',
                  style: TextStyle(
                    fontSize: 12 * settings.effectiveTextScale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status badge (top-left corner) ────────────────────────────────────────────

class _EditorStatusBadge extends StatelessWidget {
  const _EditorStatusBadge({required this.settings});

  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EditorTheme.statusBadgeBg,
        borderRadius: BorderRadius.circular(settings.cornerRadius + 6),
        border: Border.all(color: settings.themeColor, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10 * settings.compactness,
          vertical: 8 * settings.compactness,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.visibility_rounded,
              size: 14 * settings.effectiveTextScale,
              color: EditorTheme.textBright,
            ),
            const SizedBox(width: 6),
            Text(
              'EDITOR: OPEN',
              style: TextStyle(
                fontSize: 11 * settings.effectiveTextScale,
                fontWeight: FontWeight.w700,
                color: EditorTheme.textBright,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared badge chip ─────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    this.accent = EditorTheme.buttonBg,
    this.settings = const _OverlayUiSettings.defaults(),
  });

  final String label;
  final Color accent;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8 * settings.compactness,
          vertical: 3 * settings.compactness,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: EditorTheme.textBadge,
            fontSize: 11 * settings.effectiveTextScale,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
