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

enum _PerformanceTab { performance, runtime }

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
                      child: _tab == _PerformanceTab.performance
                          ? _PerformanceDetailContent(
                              controller: widget.controller,
                              settings: widget.settings,
                            )
                          : _RuntimeDetailContent(
                              controller: widget.controller,
                              settings: widget.settings,
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
