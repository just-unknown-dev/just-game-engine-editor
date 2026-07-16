import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart' show AnimatedSpriteComponent, AnimationControllerComponent, AnimationEvent, RenderableComponent, Sprite, TransformComponent, TransformKeyframe;
import 'package:just_storage/just_storage.dart';

import '../panels/entity_inspector_panel.dart';
import '../panels/scene_picker_panel.dart';
import '../panels/scene_tree_panel.dart';
import '../theme/editor_theme.dart';
import '../../core/services/editor_log_service.dart';
import '../../core/services/editor_log_entry.dart';
import '../../core/plugin/editor_plugin.dart';

part 'overlay_settings_store.part.dart';
part 'overlay_dock_metrics.part.dart';
part 'overlay_settings_dialog.part.dart';
part 'overlay_shared_widgets.part.dart';
part 'overlay_compact_dock.part.dart';
part 'overlay_dock_logs_panel.part.dart';
part 'overlay_dock_assets_panel.part.dart';
part 'overlay_dock_timeline_panel.part.dart';
part 'overlay_detail_cards.part.dart';
part 'overlay_right_panel.part.dart';
part 'overlay_snackbar.part.dart';

// ─ Frame-safe overlay settings watcher ────────────────────────────────────

/// Wrapper that applies overlay settings on the next frame, avoiding
/// FlutterError 'Build scheduled during frame'.
///
/// This defers [plugin.applyOverlaySettings] to post-frame via SchedulerBinding,
/// ensuring it runs outside of build/layout/paint phases.
class _OverlayUiSettingsWatcher extends StatefulWidget {
  const _OverlayUiSettingsWatcher({
    required this.plugin,
    required this.settings,
    required this.child,
  });

  final JustGameEditorPlugin plugin;
  final _OverlayUiSettings settings;
  final Widget child;

  @override
  State<_OverlayUiSettingsWatcher> createState() =>
      _OverlayUiSettingsWatcherState();
}

class _OverlayUiSettingsWatcherState extends State<_OverlayUiSettingsWatcher> {
  @override
  void didUpdateWidget(_OverlayUiSettingsWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _scheduleSettingsApplication();
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleSettingsApplication();
  }

  void _scheduleSettingsApplication() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.plugin.applyOverlaySettings(
          showGrid: widget.settings.showGrid,
          gridSnappingEnabled: widget.settings.gridSnappingEnabled,
          gridSize: widget.settings.gridSize,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ── Public overlay host ───────────────────────────────────────────────────────

/// Wraps the game surface with the runtime editor UI.
///
/// When [plugin.isVisible] is false the widget keeps the game interactive.
/// If [plugin.isStatusPanelVisible] is true, the compact dock can still be
/// shown independently. When visible it switches to a split layout: game
/// canvas on the left, editor panel on the right.
///
/// The dock/panel/badge/snackbar "chrome" is projected into the ambient
/// [Overlay] via [OverlayPortal] rather than painted inline. Apps typically
/// stack pause/game-over dialogs above this widget (see just_zombies'
/// GameScreen); painting chrome inline would put it underneath those
/// dialogs. Routing it through the Overlay makes the editor — a developer
/// tool, not game UI — always render on top, regardless of sibling order
/// elsewhere in the app. Only the game canvas itself stays in its normal
/// tree position, since gameplay must still render beneath the app's own
/// HUD/dialogs as before.
class JustGameEditorOverlay extends StatefulWidget {
  const JustGameEditorOverlay({
    super.key,
    required this.plugin,
    required this.gameChild,
  });

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  State<JustGameEditorOverlay> createState() => _JustGameEditorOverlayState();
}

class _JustGameEditorOverlayState extends State<JustGameEditorOverlay> {
  final OverlayPortalController _chromeController = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    if (kDebugMode) _chromeController.show();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.gameChild;

    final plugin = widget.plugin;
    final gameChild = widget.gameChild;

    return EditorMessenger(
      child: FocusScope(
        node: plugin.gameFocusScopeNode,
        child: Focus(
          autofocus: true,
          canRequestFocus: true,
          child: OverlayPortal(
            controller: _chromeController,
            overlayChildBuilder: (context) {
              return AnimatedBuilder(
                animation: plugin,
                builder: (context, _) {
                  if (!plugin.isVisible) {
                    if (!plugin.isStatusPanelVisible) {
                      return const SizedBox.shrink();
                    }
                    return _CompactChrome(plugin: plugin);
                  }

                  return ValueListenableBuilder<_OverlayUiSettings>(
                    valueListenable: _overlayUiSettingsSignal,
                    builder: (context, settings, _) =>
                        _FullEditorChrome(plugin: plugin, settings: settings),
                  );
                },
              );
            },
            child: AnimatedBuilder(
              animation: plugin,
              builder: (context, _) {
                if (!plugin.isVisible) {
                  return AbsorbPointer(absorbing: false, child: gameChild);
                }

                return ValueListenableBuilder<_OverlayUiSettings>(
                  valueListenable: _overlayUiSettingsSignal,
                  builder: (context, settings, _) {
                    return _OverlayUiSettingsWatcher(
                      plugin: plugin,
                      settings: settings,
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: _GameCanvasArea(
                              plugin: plugin,
                              gameChild: gameChild,
                            ),
                          ),
                          const SizedBox(width: _EditorRightPanel.panelWidth),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Chrome shown when the full editor is closed but the compact status dock
/// is pinned open. Sized against [MediaQuery]'s screen size since it now
/// paints in the root [Overlay] rather than inline with [JustGameEditorOverlay],
/// which — for this package's expected full-bleed usage — matches the size
/// the dock would have received locally.
class _CompactChrome extends StatelessWidget {
  const _CompactChrome({required this.plugin});

  final JustGameEditorPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _CompactStatusDock(
            plugin: plugin,
            maxDetailWidth: size.width,
            maxDetailHeight: size.height,
          ),
        ),
        const Positioned(
          bottom: _CompactStatusDock._panelHeight + 8,
          right: 8,
          child: _EditorSnackBarLayer(),
        ),
      ],
    );
  }
}

/// Chrome shown while the full editor is open: right inspector panel, the
/// compact dock confined to the canvas column, the status badge, and
/// snackbars. See [_CompactChrome] for the sizing assumption.
class _FullEditorChrome extends StatelessWidget {
  const _FullEditorChrome({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final leftWidth = math.max(0.0, size.width - _EditorRightPanel.panelWidth);

    return Stack(
      children: <Widget>[
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: _EditorRightPanel.panelWidth,
          child: _EditorRightPanel(plugin: plugin, settings: settings),
        ),
        if (plugin.isStatusPanelVisible)
          Positioned(
            left: 0,
            right: _EditorRightPanel.panelWidth,
            bottom: 0,
            child: _CompactStatusDock(
              plugin: plugin,
              maxDetailWidth: leftWidth,
              maxDetailHeight: size.height,
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
        Positioned(
          top: 16,
          right: _EditorRightPanel.panelWidth + 16,
          child: _PlayControlsToolbar(plugin: plugin, settings: settings),
        ),
        const Positioned(
          bottom: _CompactStatusDock._panelHeight + 8,
          right: _EditorRightPanel.panelWidth + 8,
          child: _EditorSnackBarLayer(),
        ),
      ],
    );
  }
}

// ── Enums & data classes ──────────────────────────────────────────────────────

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

enum _StatusMetricId { fps, entities, logs, assets, timeline }

extension on _StatusMetricId {
  String get label => switch (this) {
    _StatusMetricId.fps => 'FPS',
    _StatusMetricId.entities => 'Entities',
    _StatusMetricId.logs => 'Logs',
    _StatusMetricId.assets => 'Assets',
    _StatusMetricId.timeline => 'Timeline',
  };

  IconData get icon => switch (this) {
    _StatusMetricId.fps => Icons.speed_rounded,
    _StatusMetricId.entities => Icons.blur_linear_rounded,
    _StatusMetricId.logs => Icons.article_outlined,
    _StatusMetricId.assets => Icons.folder_outlined,
    _StatusMetricId.timeline => Icons.movie_filter_rounded,
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

// ── Global settings state ─────────────────────────────────────────────────────

final ValueNotifier<_OverlayUiSettings> _overlayUiSettingsSignal =
    ValueNotifier<_OverlayUiSettings>(const _OverlayUiSettings.defaults());
bool _overlayUiSettingsLoaded = false;
Future<void>? _overlayUiSettingsLoadFuture;

final _OverlaySettingsStore _overlaySettingsStore = _OverlaySettingsStore(
  JustStorage.standard(),
);

// ── Global performance history (persists across panel open/close) ────────────

class _PerfHistorySample {
  const _PerfHistorySample({
    required this.frameNumber,
    required this.fps,
    required this.frameMs,
    required this.budgetRemainingMs,
    required this.rssBytes,
  });

  final int frameNumber;
  final int fps;
  final double frameMs;
  final double budgetRemainingMs;
  final int rssBytes;

  /// Frame time as a percentage of the engine's fixed frame budget — used as
  /// a CPU-load proxy since no real OS-level CPU% is tracked anywhere in the
  /// engine/debugger. Can exceed 100 when the frame is over budget.
  double get cpuUsagePercent {
    final totalBudgetMs = frameMs + budgetRemainingMs;
    if (totalBudgetMs <= 0) return 0;
    return (frameMs / totalBudgetMs) * 100;
  }
}

const int _perfHistoryCapacity = 180;
final List<_PerfHistorySample> _perfHistory = <_PerfHistorySample>[];

/// Appends a sample to the session-level performance history, skipping
/// duplicates when the underlying frame hasn't advanced (e.g. game paused).
void _recordPerfSample(
  PerformanceDebuggerSnapshot performance,
  MemoryDebuggerSnapshot memory,
) {
  if (_perfHistory.isNotEmpty &&
      _perfHistory.last.frameNumber == performance.frameNumber) {
    return;
  }
  _perfHistory.add(
    _PerfHistorySample(
      frameNumber: performance.frameNumber,
      fps: performance.currentFps,
      frameMs: performance.lastUpdateMs,
      budgetRemainingMs: performance.budgetRemainingMs,
      rssBytes: memory.rssBytes,
    ),
  );
  if (_perfHistory.length > _perfHistoryCapacity) {
    _perfHistory.removeAt(0);
  }
}

// ── Canvas ─────────────────────────────────────────────────────────────────

class _GameCanvasArea extends StatefulWidget {
  const _GameCanvasArea({required this.plugin, required this.gameChild});

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  State<_GameCanvasArea> createState() => _GameCanvasAreaState();
}

class _GameCanvasAreaState extends State<_GameCanvasArea> {
  Size? _lastCanvasSize;

  void _scheduleCanvasSizeUpdate(Size size) {
    if (_lastCanvasSize == size) return;
    _lastCanvasSize = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.plugin.updateCanvasSize(size);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _scheduleCanvasSizeUpdate(size);

        return Listener(
          onPointerDown: widget.plugin.onPointerDown,
          onPointerMove: widget.plugin.onPointerMove,
          onPointerUp: widget.plugin.onPointerUp,
          onPointerSignal: widget.plugin.onPointerScroll,
          child: AbsorbPointer(absorbing: true, child: widget.gameChild),
        );
      },
    );
  }
}
