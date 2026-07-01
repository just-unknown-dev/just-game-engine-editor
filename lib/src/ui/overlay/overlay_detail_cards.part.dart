part of 'editor_overlay.dart';

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
      animation: Listenable.merge(<Listenable>[
        controller,
        EditorLogService.instance,
      ]),
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
    final logs = EditorLogService.instance.entries;
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
      _StatusDetailSection.assets => const TextSpan(
        style: TextStyle(fontSize: 9, color: EditorTheme.textMuted),
        children: <InlineSpan>[
          TextSpan(text: 'File system browser'),
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
      _StatusDetailSection.assets => const SizedBox.shrink(),
    };
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
