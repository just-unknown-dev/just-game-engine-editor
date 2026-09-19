import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../docks/assets_dock.dart';
import '../docks/detail_cards.dart';
import '../docks/dock_metrics.dart';
import '../docks/logs_dock.dart';
import '../docks/timeline_dock.dart';
import '../input_setup/input_setup_panel.dart';
import '../settings/overlay_ui_settings.dart';
import '../settings/settings_dialog.dart';
import '../shared/snackbar.dart';
import '../../../extension/editor_contributions.dart';
import 'dock_controller.dart';

class CompactStatusDock extends StatefulWidget {
  const CompactStatusDock({
    super.key,
    required this.plugin,
    required this.maxDetailWidth,
    required this.maxDetailHeight,
  });

  final JustGameEditorPlugin plugin;
  final double maxDetailWidth;
  final double maxDetailHeight;

  @override
  State<CompactStatusDock> createState() => _CompactStatusDockState();
}

class _CompactStatusDockState extends State<CompactStatusDock> {
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _settingsAnchorKey = GlobalKey();
  int _lastMetricSampleMs = 0;
  DockMetricsSnapshot? _displayMetrics;
  int _assetFileCount = 0;

  // Resolved once: dispose runs after the plugin may have closed the scope,
  // and must not go back through the container.
  late final DockController _dock = widget.plugin.scope.dockController;

  /// Docks may grow to three quarters of what the overlay allows.
  double get _maxDockHeight =>
      (widget.maxDetailHeight * 0.75).clamp(180.0, 700.0);

  void _onDockChanged() => setState(() {});
  List<VoidCallback> _stopWatchingDock = const [];

  double _defaultHeightOf(String id) => switch (id) {
    'timeline' => 300,
    'fps' || 'entities' || 'logs' || 'assets' => 280,
    _ =>
      widget.plugin.scope.docks
              .where((d) => d.id == id)
              .map((d) => d.defaultHeight)
              .firstOrNull ??
          280,
  };

  void _updateSettings(OverlayUiSettings settings) {
    final scope = widget.plugin.scope;
    scope.prefs.update(settings);
    // The accent the user picked is the theme the rest of the chrome reads.
    scope.theme.select(settings.themePreset.name);
  }

  void _toggleSettings() => _dock.toggle(DockController.settingsId);
  void _toggleLogsPanel() => _dock.toggle('logs');
  void _toggleAssetsPanel() => _dock.toggle('assets');
  void _toggleTimelinePanel() => _dock.toggle('timeline');
  void _togglePerformancePanel() => _dock.toggle('fps');
  void _toggleEcsPanel() => _dock.toggle('entities');

  void _resize(String id, double dy, double fallback) =>
      _dock.resize(id, dy, fallback: fallback, max: _maxDockHeight);

  @override
  void initState() {
    super.initState();
    _stopWatchingDock = [
      _dock.openId.watch(_onDockChanged),
      _dock.heights.watch(_onDockChanged),
    ];
    _loadPersistedSettings();
    _scanAssetFileCount();
  }

  String _timelineLabel() {
    final entity = widget.plugin.sceneState.selectedEntity.value;
    if (entity == null) return 'no selection';
    // Whichever component's extras can summarise itself: the animated
    // sprite's names its clip, and a module's own animation source can too.
    final extras = widget.plugin.scope.extras;
    for (final c in entity.components) {
      final definition = widget.plugin.scope.definitions.definitionFor(c);
      final summary = definition == null
          ? null
          : extras.forType(definition.type)?.summary;
      if (summary != null) return summary(c);
    }
    return 'no anim';
  }

  Future<void> _scanAssetFileCount() async {
    final dir = Directory('${Directory.current.path}/assets');
    if (!await dir.exists()) return;
    int count = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) count++;
    }
    if (!mounted) return;
    setState(() => _assetFileCount = count);
  }

  Future<void> _loadPersistedSettings() async {
    final scope = widget.plugin.scope;
    await scope.prefs.load();
    scope.theme.select(scope.prefs.settings.value.themePreset.name);
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

  @override
  void dispose() {
    for (final stop in _stopWatchingDock) {
      stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.plugin.debuggerController,
      builder: (context, _) {
        final controller = widget.plugin.debuggerController;
        final liveMetrics = DockMetricsSnapshot.fromController(controller);

        final refreshMs = widget
            .plugin
            .scope
            .prefs
            .settings
            .value
            .metricRefreshMs
            .clamp(33, 2000)
            .round();
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final shouldSample =
            _lastMetricSampleMs == 0 ||
            nowMs - _lastMetricSampleMs >= refreshMs;

        if (shouldSample) {
          _lastMetricSampleMs = nowMs;
          _displayMetrics = liveMetrics;
          widget.plugin.scope.chrome.recordPerfSample(
            liveMetrics.performance,
            liveMetrics.memory,
          );
        }

        final sampledMetrics = shouldSample
            ? liveMetrics
            : (_displayMetrics ?? liveMetrics);
        final snapshot = sampledMetrics.snapshot;
        final performance = sampledMetrics.performance;
        final logs = widget.plugin.logService.entries.value;

        final warningCount = logs
            .where((entry) => entry.level == DebuggerLogLevel.warning)
            .length;
        final errorCount = logs
            .where((entry) => entry.level == DebuggerLogLevel.error)
            .length;
        final detailMaxHeight =
            widget.maxDetailHeight - OverlayLayout.compactDockPanelHeight - 40;
        final settingsPanelHeight = detailMaxHeight
            .clamp(260.0, 460.0)
            .toDouble();
        final settingsOpen = _dock.isOpen(DockController.settingsId);
        final openDock = _dock.openId.value;
        final openDockHeight = openDock == null || settingsOpen
            ? 0.0
            : _dock.heightOf(openDock, fallback: _defaultHeightOf(openDock));
        final dockHeight =
            OverlayLayout.compactDockPanelHeight +
            openDockHeight +
            (settingsOpen ? settingsPanelHeight + 12.0 : 0.0);

        return SignalBuilder<OverlayUiSettings>(
          signal: widget.plugin.scope.prefs.settings,
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
                        height: OverlayLayout.compactDockPanelHeight,
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
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: <Widget>[
                                      _StatusMetricButton(
                                        label: StatusMetricId.fps.label,
                                        icon: StatusMetricId.fps.icon,
                                        value:
                                            '${performance.currentFps} fps • ${performance.lastUpdateMs.toStringAsFixed(1)} ms',
                                        accent: settings.themeColor,
                                        isSelected: _dock.isOpen('fps'),
                                        onTap: _togglePerformancePanel,
                                        settings: settings,
                                      ),
                                      _StatusSeparator(settings: settings),
                                      _StatusMetricButton(
                                        label: StatusMetricId.entities.label,
                                        icon: StatusMetricId.entities.icon,
                                        value: '${snapshot.entityCount}',
                                        accent: const Color(0xFF7DE6B1),
                                        isSelected: _dock.isOpen('entities'),
                                        onTap: _toggleEcsPanel,
                                        settings: settings,
                                      ),
                                      _StatusSeparator(settings: settings),
                                      _StatusMetricButton(
                                        label: StatusMetricId.logs.label,
                                        icon: StatusMetricId.logs.icon,
                                        value: errorCount > 0
                                            ? '${logs.length} total • $errorCount err'
                                            : '${logs.length} total • $warningCount warn',
                                        accent: const Color(0xFFD9A7FF),
                                        isSelected: _dock.isOpen('logs'),
                                        onTap: _toggleLogsPanel,
                                        settings: settings,
                                      ),
                                      _StatusSeparator(settings: settings),
                                      _StatusMetricButton(
                                        label: StatusMetricId.assets.label,
                                        icon: StatusMetricId.assets.icon,
                                        value: '$_assetFileCount files',
                                        accent: const Color(0xFF7DD8E0),
                                        isSelected: _dock.isOpen('assets'),
                                        onTap: _toggleAssetsPanel,
                                        settings: settings,
                                      ),
                                      _StatusSeparator(settings: settings),
                                      _StatusMetricButton(
                                        label: StatusMetricId.timeline.label,
                                        icon: StatusMetricId.timeline.icon,
                                        value: _timelineLabel(),
                                        accent: const Color(0xFF7DE6B1),
                                        isSelected: _dock.isOpen('timeline'),
                                        onTap: _toggleTimelinePanel,
                                        settings: settings,
                                      ),
                                      for (final dock
                                          in widget.plugin.scope.docks) ...[
                                        _StatusSeparator(settings: settings),
                                        _StatusMetricButton(
                                          label: dock.label,
                                          icon: dock.icon,
                                          value:
                                              dock.badge?.call(
                                                widget.plugin.scope,
                                              ) ??
                                              '',
                                          accent: settings.themeColor,
                                          isSelected: _dock.isOpen(dock.id),
                                          onTap: () => _dock.toggle(dock.id),
                                          settings: settings,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const _MinimizedSnackChip(),
                              const SizedBox(width: 8),
                              InputSetupButton(
                                settings: settings,
                                onPressed: () =>
                                    widget
                                        .plugin
                                        .scope
                                        .chrome
                                        .inputSetupOpen
                                        .value = !widget
                                        .plugin
                                        .scope
                                        .chrome
                                        .inputSetupOpen
                                        .value,
                              ),
                              _EditorSettingsButton(
                                anchorKey: _settingsAnchorKey,
                                settings: settings,
                                isSelected: settingsOpen,
                                onPressed: _toggleSettings,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_dock.isOpen('logs'))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: OverlayLayout.compactDockPanelHeight,
                        child: DockLogsPanel(
                          log: widget.plugin.logService,
                          controller: controller,
                          height: _dock.heightOf('logs', fallback: 280),
                          onResize: (dy) => _resize('logs', dy, 280),
                          onClose: _toggleLogsPanel,
                          settings: settings,
                        ),
                      ),
                    if (_dock.isOpen('assets'))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: OverlayLayout.compactDockPanelHeight,
                        child: DockAssetsPanel(
                          height: _dock.heightOf('assets', fallback: 280),
                          onResize: (dy) => _resize('assets', dy, 280),
                          onClose: _toggleAssetsPanel,
                          settings: settings,
                        ),
                      ),
                    if (_dock.isOpen('timeline'))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: OverlayLayout.compactDockPanelHeight,
                        child: DockTimelinePanel(
                          height: _dock.heightOf('timeline', fallback: 300),
                          onResize: (dy) => _resize('timeline', dy, 300),
                          onClose: _toggleTimelinePanel,
                          settings: settings,
                          plugin: widget.plugin,
                        ),
                      ),
                    if (_dock.isOpen('fps'))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: OverlayLayout.compactDockPanelHeight,
                        child: DockPerformancePanel(
                          controller: controller,
                          height: _dock.heightOf('fps', fallback: 280),
                          onResize: (dy) => _resize('fps', dy, 280),
                          onClose: _togglePerformancePanel,
                          settings: settings,
                        ),
                      ),
                    if (_dock.isOpen('entities'))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: OverlayLayout.compactDockPanelHeight,
                        child: DockEcsPanel(
                          controller: controller,
                          height: _dock.heightOf('entities', fallback: 280),
                          onResize: (dy) => _resize('entities', dy, 280),
                          onClose: _toggleEcsPanel,
                          settings: settings,
                        ),
                      ),
                    for (final dock in widget.plugin.scope.docks)
                      if (_dock.isOpen(dock.id))
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: OverlayLayout.compactDockPanelHeight,
                          child: SizedBox(
                            height: _dock.heightOf(
                              dock.id,
                              fallback: dock.defaultHeight,
                            ),
                            child: dock.build(
                              context,
                              DockContext(
                                scope: widget.plugin.scope,
                                height: _dock.heightOf(
                                  dock.id,
                                  fallback: dock.defaultHeight,
                                ),
                                onResize: (dy) =>
                                    _resize(dock.id, dy, dock.defaultHeight),
                                onClose: _dock.close,
                              ),
                            ),
                          ),
                        ),
                    if (settingsOpen)
                      Positioned(
                        left: _detailLeftForKey(
                          _settingsAnchorKey,
                          math.min(
                            420,
                            math.max(280, widget.maxDetailWidth - 24),
                          ),
                        ),
                        bottom: OverlayLayout.compactDockPanelHeight + 12,
                        child: SizedBox(
                          width: math.min(
                            420,
                            math.max(280, widget.maxDetailWidth - 24),
                          ),
                          child: EditorSettingsPanel(
                            initial: widget.plugin.scope.prefs.settings.value,
                            prefs: widget.plugin.scope.prefs,
                            sections: widget.plugin.scope.settingsSections,
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

// ── Minimized snackbar chip ───────────────────────────────────────────────────

class _MinimizedSnackChip extends StatelessWidget {
  const _MinimizedSnackChip();

  @override
  Widget build(BuildContext context) {
    final controller = EditorMessenger.of(context);
    return SignalBuilder2<EditorSnackBarEntry?, bool>(
      signal1: controller.current,
      signal2: controller.isMinimized,
      builder: (context, entry, minimized, _) {
        if (entry == null || !minimized) {
          return const SizedBox.shrink();
        }
        final accent = entry.type.accentColor;
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: controller.expand,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 200),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: accent.withValues(alpha: 0.28)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(entry.type.iconData, size: 11, color: accent),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        entry.title ?? entry.message,
                        style: const TextStyle(
                          fontSize: 11,
                          color: EditorTheme.textSecondary,
                          height: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    GestureDetector(
                      onTap: controller.dismiss,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.close_rounded,
                          size: 10,
                          color: EditorTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusMetricButton extends StatelessWidget {
  const _StatusMetricButton({
    required this.label,
    required this.icon,
    required this.value,
    required this.accent,
    required this.isSelected,
    required this.onTap,
    required this.settings,
  });

  final String label;
  final IconData icon;
  final String value;
  final Color accent;
  final bool isSelected;
  final VoidCallback onTap;
  final OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
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
                      Icon(icon, size: 11, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        label,
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

class _EditorSettingsButton extends StatelessWidget {
  const _EditorSettingsButton({
    required this.anchorKey,
    required this.settings,
    required this.isSelected,
    required this.onPressed,
  });

  final GlobalKey anchorKey;
  final OverlayUiSettings settings;
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

  final OverlayUiSettings settings;

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
