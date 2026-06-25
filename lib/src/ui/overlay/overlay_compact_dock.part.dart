part of 'editor_overlay.dart';

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
  bool _isLogsPanelOpen = false;
  double _logsPanelHeight = 280.0;

  GlobalKey _anchorKeyFor(_StatusMetricId metric) {
    return _anchorKeys.putIfAbsent(metric, GlobalKey.new);
  }

  void _selectMetric(_StatusMetricId metric) {
    setState(() {
      _isSettingsOpen = false;
      _isLogsPanelOpen = false;
      _selectedMetric = _selectedMetric == metric ? null : metric;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedMetric = null;
      _isSettingsOpen = false;
      _isLogsPanelOpen = false;
    });
  }

  void _updateSettings(_OverlayUiSettings settings) {
    _overlayUiSettingsSignal.value = settings;
    _persistSettings(settings);
  }

  void _toggleSettings() {
    setState(() {
      _selectedMetric = null;
      _isLogsPanelOpen = false;
      _isSettingsOpen = !_isSettingsOpen;
    });
  }

  void _toggleLogsPanel() {
    setState(() {
      _selectedMetric = null;
      _isSettingsOpen = false;
      _isLogsPanelOpen = !_isLogsPanelOpen;
    });
  }

  void _onLogsPanelResize(double dy) {
    setState(() {
      _logsPanelHeight = (_logsPanelHeight - dy).clamp(
        120.0,
        (widget.maxDetailHeight * 0.75).clamp(120.0, 600.0),
      );
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
        final logs = EditorLogService.instance.entries;
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
            (_isLogsPanelOpen ? _logsPanelHeight : 0.0) +
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
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
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
                                        isSelected: _isLogsPanelOpen,
                                        onTap: (_) => _toggleLogsPanel(),
                                        settings: settings,
                                      ),
                                      const SizedBox(width: 8),
                                      _EditorSettingsButton(
                                        anchorKey: _settingsAnchorKey,
                                        settings: settings,
                                        isSelected: _isSettingsOpen,
                                        onPressed: _toggleSettings,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_isLogsPanelOpen)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: _CompactStatusDock._panelHeight,
                        child: _DockLogsPanel(
                          controller: controller,
                          height: _logsPanelHeight,
                          onResize: _onLogsPanelResize,
                          onClose: _toggleLogsPanel,
                          settings: settings,
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
