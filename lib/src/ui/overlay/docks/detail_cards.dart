import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_debugger/just_debugger.dart';

import 'package:just_editor_core/host.dart';
import '../docks/panel_parts.dart';
import '../shared/shared_widgets.dart';

class DetailSectionCard extends StatefulWidget {
  const DetailSectionCard({
    super.key,
    required this.sectionId,
    required this.title,
    required this.child,
    required this.settings,
  });

  final String sectionId;
  final String title;
  final Widget child;
  final OverlayUiSettings settings;

  @override
  State<DetailSectionCard> createState() => _DetailSectionCardState();
}

class _DetailSectionCardState extends State<DetailSectionCard> {
  bool _collapsed = false;

  String get _prefKey => 'editor.overlay.sectionCollapsed.${widget.sectionId}';

  @override
  void initState() {
    super.initState();
  }

  bool _loadedCollapsed = false;

  // The scope comes from an inherited widget, which initState may not read.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedCollapsed) {
      _loadedCollapsed = true;
      _loadCollapsed();
    }
  }

  Future<void> _loadCollapsed() async {
    final collapsed = await EditorScopeProvider.of(
      context,
    ).prefs.readBool(_prefKey, fallback: false);
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
    await EditorScopeProvider.of(context).prefs.writeBool(_prefKey, _collapsed);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceDark,
        borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: _toggleCollapsed,
            borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 10,
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

/// The Profiler's Details view: performance, runtime and profiling, one at a
/// time, picked with a segmented switch like any other choice in the editor.
/// It lives inside the dock panel, which gives it its frame and its height.
class DockPerformancePanel extends StatefulWidget {
  const DockPerformancePanel({
    super.key,
    required this.controller,
    required this.settings,
  });

  final JustDebuggerController controller;
  final OverlayUiSettings settings;

  @override
  State<DockPerformancePanel> createState() => _DockPerformancePanelState();
}

class _DockPerformancePanelState extends State<DockPerformancePanel> {
  _PerformanceTab _tab = _PerformanceTab.performance;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: EditorSegmented<_PerformanceTab>(
              value: _tab,
              options: const [
                (_PerformanceTab.performance, 'Performance'),
                (_PerformanceTab.runtime, 'Runtime'),
                (_PerformanceTab.profiling, 'Profiling'),
              ],
              onChanged: (tab) => setState(() => _tab = tab),
            ),
          ),
        ),
        Divider(height: 1, color: EditorTheme.border),
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
  );
}

class _PerformanceDetailContent extends StatelessWidget {
  const _PerformanceDetailContent({
    required this.controller,
    required this.settings,
  });

  final JustDebuggerController controller;
  final OverlayUiSettings settings;

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
            DetailStatTile(
              label: 'FPS',
              value: '${performance.currentFps}',
              settings: settings,
            ),
            DetailStatTile(
              label: 'Update Time',
              value: '${performance.lastUpdateMs.toStringAsFixed(1)} ms',
              settings: settings,
            ),
            DetailStatTile(
              label: 'Budget Left',
              value: '${performance.budgetRemainingMs.toStringAsFixed(1)} ms',
              settings: settings,
            ),
            DetailStatTile(
              label: 'Frame',
              value: '${performance.frameNumber}',
              settings: settings,
            ),
          ],
        ),
        const SizedBox(height: 8),
        DetailSectionCard(
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
                            style: TextStyle(
                              fontSize: 10,
                              color: EditorTheme.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '${entry.value.toStringAsFixed(2)} ms',
                          style: TextStyle(
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
  final OverlayUiSettings settings;

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
            DetailStatTile(
              label: 'App RSS',
              value: formatBytes(memory.rssBytes),
              settings: settings,
            ),
            DetailStatTile(
              label: 'Entities',
              value: '${memory.entityCount}',
              settings: settings,
            ),
            DetailStatTile(
              label: 'Components',
              value: '${memory.componentCount}',
              settings: settings,
            ),
            DetailStatTile(
              label: 'Warnings',
              value: '${health.messages.length}',
              settings: settings,
            ),
          ],
        ),
        const SizedBox(height: 8),
        DetailSectionCard(
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
                      style: TextStyle(
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
        DetailSectionCard(
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
                            Padding(
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
                                style: TextStyle(
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
                : <Widget>[
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
  final OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final performance = controller.performance;
    final memory = controller.memory;
    final samples = List<PerfHistorySample>.unmodifiable(
      EditorScopeProvider.of(context).chrome.perfHistory,
    );
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
        DetailSectionCard(
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
                  DetailStatTile(
                    label: 'Min',
                    value: '$minFps',
                    settings: settings,
                  ),
                  DetailStatTile(
                    label: 'Avg',
                    value: '$avgFps',
                    settings: settings,
                  ),
                  DetailStatTile(
                    label: 'Max',
                    value: '$maxFps',
                    settings: settings,
                  ),
                  DetailStatTile(
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
                    values: fpsValues
                        .map((v) => v.toDouble())
                        .toList(growable: false),
                    color: EditorTheme.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        DetailSectionCard(
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
                  DetailStatTile(
                    label: 'Current',
                    value: samples.isEmpty
                        ? '--'
                        : '${samples.last.cpuUsagePercent.toStringAsFixed(0)}%',
                    settings: settings,
                  ),
                  DetailStatTile(
                    label: 'Min',
                    value: cpuValues.isEmpty
                        ? '--'
                        : '${cpuValues.reduce(math.min).toStringAsFixed(0)}%',
                    settings: settings,
                  ),
                  DetailStatTile(
                    label: 'Avg',
                    value: cpuValues.isEmpty
                        ? '--'
                        : '${(cpuValues.reduce((a, b) => a + b) / cpuValues.length).toStringAsFixed(0)}%',
                    settings: settings,
                  ),
                  DetailStatTile(
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
        DetailSectionCard(
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
                  DetailStatTile(
                    label: 'Current',
                    value: samples.isEmpty
                        ? '--'
                        : formatBytes(samples.last.rssBytes),
                    settings: settings,
                  ),
                  DetailStatTile(
                    label: 'Min',
                    value: rssValues.isEmpty
                        ? '--'
                        : formatBytes(rssValues.reduce(math.min).round()),
                    settings: settings,
                  ),
                  DetailStatTile(
                    label: 'Avg',
                    value: rssValues.isEmpty
                        ? '--'
                        : formatBytes(
                            (rssValues.reduce((a, b) => a + b) /
                                    rssValues.length)
                                .round(),
                          ),
                    settings: settings,
                  ),
                  DetailStatTile(
                    label: 'Max',
                    value: rssValues.isEmpty
                        ? '--'
                        : formatBytes(rssValues.reduce(math.max).round()),
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
        DetailSectionCard(
          sectionId: 'profiling_all_systems',
          title: 'All System Timings',
          settings: settings,
          child: allTimings.isEmpty
              ? Text(
                  'No system timing data reported.',
                  style: TextStyle(
                    fontSize: 10,
                    color: EditorTheme.textSecondary,
                  ),
                )
              : Column(
                  children: allTimings
                      .map((entry) {
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
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: EditorTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${entry.value.toStringAsFixed(2)} ms',
                                    style: TextStyle(
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
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.06,
                                  ),
                                  valueColor: AlwaysStoppedAnimation(
                                    EditorTheme.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: 8),
        DetailSectionCard(
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
                        DetailStatTile(
                          label: 'Total',
                          value: formatBytes(memory.totalPhysicalMemoryBytes),
                          settings: settings,
                        ),
                        DetailStatTile(
                          label: 'Free',
                          value: formatBytes(memory.freePhysicalMemoryBytes),
                          settings: settings,
                        ),
                        DetailStatTile(
                          label: 'Used',
                          value: formatBytes(memory.usedPhysicalMemoryBytes),
                          settings: settings,
                        ),
                        DetailStatTile(
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
              : Text(
                  'System-wide memory stats are not available on this platform.',
                  style: TextStyle(
                    fontSize: 10,
                    color: EditorTheme.textSecondary,
                  ),
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
    double yFor(double v) => size.height - ((v - bottom) / span) * size.height;

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
      text: TextSpan(
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
