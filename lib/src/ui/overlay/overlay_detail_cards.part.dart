part of 'editor_overlay.dart';

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

enum _PerformanceTab { performance, runtime, profiling }

class _DockPerformancePanel extends StatefulWidget {
  const _DockPerformancePanel({
    required this.controller,
    required this.height,
    required this.onResize,
    required this.onClose,
    required this.settings,
  });

  final JustDebuggerController controller;
  final double height;
  final ValueChanged<double> onResize;
  final VoidCallback onClose;
  final _OverlayUiSettings settings;

  @override
  State<_DockPerformancePanel> createState() => _DockPerformancePanelState();
}

class _DockPerformancePanelState extends State<_DockPerformancePanel> {
  _PerformanceTab _tab = _PerformanceTab.performance;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return SizedBox(
          height: widget.height,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xF41B1B1B),
                border: Border(
                  left: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
                  right: BorderSide(
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 12,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  _PanelResizeHandle(onDrag: widget.onResize),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: widget.settings.themeColor.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.bolt_rounded,
                            size: 11,
                            color: widget.settings.themeColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Performance',
                          style: TextStyle(
                            fontSize: 11 * widget.settings.effectiveTextScale,
                            fontWeight: FontWeight.w600,
                            color: EditorTheme.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close_rounded),
                          color: EditorTheme.textSecondary,
                          iconSize: 14,
                          splashRadius: 14,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildTabStrip(),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(10),
                      child: switch (_tab) {
                        _PerformanceTab.performance => _PerformanceDetailContent(
                          controller: widget.controller,
                          settings: widget.settings,
                        ),
                        _PerformanceTab.runtime => _RuntimeDetailContent(
                          controller: widget.controller,
                          settings: widget.settings,
                        ),
                        _PerformanceTab.profiling => _ProfilingDetailContent(
                          controller: widget.controller,
                          settings: widget.settings,
                        ),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabStrip() {
    return Container(
      height: 28,
      color: const Color(0xFF141414),
      child: Row(
        children: [
          _buildTab(
            _PerformanceTab.performance,
            Icons.bolt_rounded,
            'Performance',
          ),
          _buildTab(
            _PerformanceTab.runtime,
            Icons.monitor_heart_rounded,
            'Runtime',
          ),
          _buildTab(
            _PerformanceTab.profiling,
            Icons.insights_rounded,
            'Profiling',
          ),
        ],
      ),
    );
  }

  Widget _buildTab(_PerformanceTab tab, IconData icon, String label) {
    final isActive = _tab == tab;
    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? EditorTheme.primaryMuted : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11,
              color: isActive
                  ? EditorTheme.primaryMuted
                  : EditorTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? EditorTheme.textPrimary
                    : EditorTheme.textMuted,
              ),
            ),
          ],
        ),
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

class _DockEcsPanel extends StatelessWidget {
  const _DockEcsPanel({
    required this.controller,
    required this.height,
    required this.onResize,
    required this.onClose,
    required this.settings,
  });

  final JustDebuggerController controller;
  final double height;
  final ValueChanged<double> onResize;
  final VoidCallback onClose;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SizedBox(
          height: height,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xF41B1B1B),
                border: Border(
                  left: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
                  right: BorderSide(
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 12,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  _PanelResizeHandle(onDrag: onResize),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF7DE6B1,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.hub_rounded,
                            size: 11,
                            color: Color(0xFF7DE6B1),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'ECS',
                          style: TextStyle(
                            fontSize: 11 * settings.effectiveTextScale,
                            fontWeight: FontWeight.w600,
                            color: EditorTheme.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded),
                          color: EditorTheme.textSecondary,
                          iconSize: 14,
                          splashRadius: 14,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(10),
                      child: _EcsDetailContent(
                        controller: controller,
                        settings: settings,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
                ? <Widget>[
                    ...health.messages.map((message) {
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
                            Tooltip(
                              message: 'Copy warning',
                              child: InkWell(
                                onTap: () {
                                  Clipboard.setData(
                                    ClipboardData(text: message),
                                  );
                                  EditorMessenger.of(context).showSnackBar(
                                    const EditorSnackBarEntry(
                                      message: 'Warning copied',
                                      type: EditorSnackBarType.success,
                                      duration: Duration(milliseconds: 1500),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.content_copy_rounded,
                                    size: 12,
                                    color: EditorTheme.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (health.messages.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final allMessages = health.messages.join('\n');
                              Clipboard.setData(
                                ClipboardData(text: allMessages),
                              );
                              EditorMessenger.of(context).showSnackBar(
                                const EditorSnackBarEntry(
                                  message: 'All warnings copied',
                                  type: EditorSnackBarType.success,
                                  duration: Duration(milliseconds: 1500),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_all_rounded, size: 12),
                            label: const Text('Copy All'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: EditorTheme.buttonBg,
                              foregroundColor: EditorTheme.textPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ),
                  ]
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

class _ProfilingDetailContent extends StatelessWidget {
  const _ProfilingDetailContent({
    required this.controller,
    required this.settings,
  });

  final JustDebuggerController controller;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final performance = controller.performance;
    final memory = controller.memory;
    final samples = List<_PerfHistorySample>.unmodifiable(_perfHistory);
    final fpsValues = samples.map((s) => s.fps).toList(growable: false);
    final minFps = fpsValues.isEmpty ? 0 : fpsValues.reduce(math.min);
    final maxFps = fpsValues.isEmpty ? 0 : fpsValues.reduce(math.max);
    final avgFps = fpsValues.isEmpty
        ? 0
        : (fpsValues.reduce((a, b) => a + b) / fpsValues.length).round();
    final cpuValues = samples
        .map((s) => s.cpuUsagePercent)
        .toList(growable: false);
    final rssValues = samples
        .map((s) => s.rssBytes.toDouble())
        .toList(growable: false);

    final allTimings = performance.systemTimesMs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxSystemMs = allTimings.isEmpty ? 0.0 : allTimings.first.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DetailSectionCard(
          sectionId: 'profiling_fps_history',
          title: 'FPS History',
          settings: settings,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: <Widget>[
                  _DetailStatTile(label: 'Min', value: '$minFps', settings: settings),
                  _DetailStatTile(label: 'Avg', value: '$avgFps', settings: settings),
                  _DetailStatTile(label: 'Max', value: '$maxFps', settings: settings),
                  _DetailStatTile(
                    label: 'Samples',
                    value: '${samples.length}',
                    settings: settings,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 80,
                width: double.infinity,
                child: CustomPaint(
                  painter: _HistoryLineChartPainter(
                    values: fpsValues.map((v) => v.toDouble()).toList(
                      growable: false,
                    ),
                    color: settings.themeColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'profiling_cpu_usage',
          title: 'CPU Usage',
          settings: settings,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: <Widget>[
                  _DetailStatTile(
                    label: 'Current',
                    value: samples.isEmpty
                        ? '--'
                        : '${samples.last.cpuUsagePercent.toStringAsFixed(0)}%',
                    settings: settings,
                  ),
                  _DetailStatTile(
                    label: 'Min',
                    value: cpuValues.isEmpty
                        ? '--'
                        : '${cpuValues.reduce(math.min).toStringAsFixed(0)}%',
                    settings: settings,
                  ),
                  _DetailStatTile(
                    label: 'Avg',
                    value: cpuValues.isEmpty
                        ? '--'
                        : '${(cpuValues.reduce((a, b) => a + b) / cpuValues.length).toStringAsFixed(0)}%',
                    settings: settings,
                  ),
                  _DetailStatTile(
                    label: 'Max',
                    value: cpuValues.isEmpty
                        ? '--'
                        : '${cpuValues.reduce(math.max).toStringAsFixed(0)}%',
                    settings: settings,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 80,
                width: double.infinity,
                child: CustomPaint(
                  painter: _HistoryLineChartPainter(
                    values: cpuValues,
                    color: const Color(0xFFFFC86B),
                    referenceValue: 100.0,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'profiling_memory_usage',
          title: 'Memory Usage',
          settings: settings,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: <Widget>[
                  _DetailStatTile(
                    label: 'Current',
                    value: samples.isEmpty
                        ? '--'
                        : _formatBytes(samples.last.rssBytes),
                    settings: settings,
                  ),
                  _DetailStatTile(
                    label: 'Min',
                    value: rssValues.isEmpty
                        ? '--'
                        : _formatBytes(rssValues.reduce(math.min).round()),
                    settings: settings,
                  ),
                  _DetailStatTile(
                    label: 'Avg',
                    value: rssValues.isEmpty
                        ? '--'
                        : _formatBytes(
                            (rssValues.reduce((a, b) => a + b) /
                                    rssValues.length)
                                .round(),
                          ),
                    settings: settings,
                  ),
                  _DetailStatTile(
                    label: 'Max',
                    value: rssValues.isEmpty
                        ? '--'
                        : _formatBytes(rssValues.reduce(math.max).round()),
                    settings: settings,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 80,
                width: double.infinity,
                child: CustomPaint(
                  painter: _HistoryLineChartPainter(
                    values: rssValues,
                    color: const Color(0xFF7DD8E0),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'profiling_all_systems',
          title: 'All System Timings',
          settings: settings,
          child: allTimings.isEmpty
              ? const Text(
                  'No system timing data reported.',
                  style: TextStyle(fontSize: 10, color: EditorTheme.textSecondary),
                )
              : Column(
                  children: allTimings.map((entry) {
                    final ratio = maxSystemMs <= 0
                        ? 0.0
                        : (entry.value / maxSystemMs).clamp(0.0, 1.0);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
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
                          const SizedBox(height: 3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 4,
                              backgroundColor: Colors.white.withValues(alpha: 0.06),
                              valueColor: AlwaysStoppedAnimation(settings.themeColor),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(growable: false),
                ),
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'profiling_system_memory',
          title: 'System Memory',
          settings: settings,
          child: memory.hasSystemMemoryStats
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: <Widget>[
                        _DetailStatTile(
                          label: 'Total',
                          value: _formatBytes(memory.totalPhysicalMemoryBytes),
                          settings: settings,
                        ),
                        _DetailStatTile(
                          label: 'Free',
                          value: _formatBytes(memory.freePhysicalMemoryBytes),
                          settings: settings,
                        ),
                        _DetailStatTile(
                          label: 'Used',
                          value: _formatBytes(memory.usedPhysicalMemoryBytes),
                          settings: settings,
                        ),
                        _DetailStatTile(
                          label: 'Available',
                          value:
                              '${(memory.availabilityRatio * 100).toStringAsFixed(1)}%',
                          settings: settings,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (1 - memory.availabilityRatio).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: AlwaysStoppedAnimation(
                          memory.availabilityRatio < 0.15
                              ? EditorTheme.warning
                              : const Color(0xFFFFC86B),
                        ),
                      ),
                    ),
                  ],
                )
              : const Text(
                  'System-wide memory stats are not available on this platform.',
                  style: TextStyle(fontSize: 10, color: EditorTheme.textSecondary),
                ),
        ),
      ],
    );
  }
}

/// Generic rolling line/area chart used by every history graph in the
/// Profiling tab (FPS, CPU load proxy, RSS). [referenceValue], if set, draws
/// a dashed-style horizontal marker (e.g. the 100% budget line for CPU).
class _HistoryLineChartPainter extends CustomPainter {
  const _HistoryLineChartPainter({
    required this.values,
    required this.color,
    this.referenceValue,
  });

  final List<double> values;
  final Color color;
  final double? referenceValue;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      _drawEmptyState(canvas, size);
      return;
    }

    final maxValue = values.reduce(math.max);
    final minValue = values.reduce(math.min);
    final effectiveMax = referenceValue != null
        ? math.max(maxValue, referenceValue!)
        : maxValue;
    final range = (effectiveMax - minValue).clamp(1.0, double.infinity);
    final top = effectiveMax + range * 0.15;
    final bottom = (minValue - range * 0.15).clamp(0.0, double.infinity);
    final span = (top - bottom).clamp(1.0, double.infinity);

    double xFor(int i) => size.width * i / (values.length - 1);
    double yFor(double v) =>
        size.height - ((v - bottom) / span) * size.height;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (int i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (referenceValue != null) {
      final refY = yFor(referenceValue!);
      canvas.drawLine(
        Offset(0, refY),
        Offset(size.width, refY),
        Paint()
          ..color = EditorTheme.warning.withValues(alpha: 0.4)
          ..strokeWidth = 1,
      );
    }

    final linePath = Path();
    final fillPath = Path();
    for (int i = 0; i < values.length; i++) {
      final x = xFor(i);
      final y = yFor(values[i]);
      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(xFor(values.length - 1), size.height);
    fillPath.close();

    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'Collecting samples…',
        style: TextStyle(fontSize: 10, color: EditorTheme.textMuted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(_HistoryLineChartPainter old) =>
      old.values != values ||
      old.color != color ||
      old.referenceValue != referenceValue;
}
