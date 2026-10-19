import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart';

import 'package:just_editor_core/host.dart';
import 'package:just_editor_core/io.dart';
import '../shared/dock_widgets.dart';
import 'frame_capture.dart';

/// A stable colour for a system's name, so it is the same in the bar, the
/// table, and the next frame.
Color systemColor(String name) {
  const palette = [
    Color(0xFF7DE6B1),
    Color(0xFF7DD8E0),
    Color(0xFFFFC86B),
    Color(0xFFD9A7FF),
    Color(0xFFF5746F),
    Color(0xFF6FA8F5),
    Color(0xFFE6C36B),
    Color(0xFF9BE37D),
  ];
  return palette[name.hashCode.abs() % palette.length];
}

/// The Profiler: frame time over the last few hundred frames, and what each
/// system cost in the frame being looked at.
class ProfilerDock extends StatefulWidget {
  const ProfilerDock({
    super.key,
    required this.scope,
    required this.dock,
    required this.capture,
    this.details,
  });

  final EditorScope scope;
  final DockContext dock;

  /// Owned by whoever made the dock, so a capture outlives a tab switch.
  final FrameCapture capture;

  /// The runtime and history pages, shown under "Details".
  final WidgetBuilder? details;

  @override
  State<ProfilerDock> createState() => _ProfilerDockState();
}

class _ProfilerDockState extends State<ProfilerDock> {
  FrameCapture get _capture => widget.capture;
  bool _showDetails = false;

  /// A new frame arrives every frame: the dock is drawn again a few times
  /// a second for them, not sixty.
  Timer? _redraw;

  @override
  void initState() {
    super.initState();
    _capture.addListener(_changed);
    // One picked here stays; otherwise the settings' target rate.
    _capture.budgetMs =
        widget.dock.memory?.read<double>('budgetMs') ??
        widget.scope.prefs.settings.value.frameBudgetMs;
  }

  @override
  void dispose() {
    _capture.removeListener(_changed);
    _redraw?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // Paused, a click looks at a frame: that shows at once.
    if (_capture.paused) {
      _redraw?.cancel();
      _redraw = null;
      setState(() {});
      return;
    }
    _redraw ??= Timer(const Duration(milliseconds: 100), () {
      _redraw = null;
      if (mounted) setState(() {});
    });
  }

  void _setBudget(double ms) {
    setState(() => _capture.budgetMs = ms);
    widget.dock.memory?.write('budgetMs', ms);
  }

  Future<void> _export() async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '.editor_logs/profile_$stamp.json';
    try {
      final file = File('${Directory.current.path}/$path');
      await file.parent.create(recursive: true);
      await file.writeAsString(_capture.toJsonText());
      widget.scope.log.log(
        'Exported ${_capture.samples.length} frames to $path',
        source: 'profiler',
      );
    } catch (e) {
      widget.scope.log.log(
        'Could not export the capture: $e',
        source: 'profiler',
        level: DebuggerLogLevel.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final samples = _capture.samples;
    final selected = _capture.selected;
    return Column(
      children: [
        EditorToolbar(
          children: [
            EditorIconButton(
              icon: _capture.paused
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
              tooltip: _capture.paused
                  ? 'Resume capturing'
                  : 'Pause, to look at a frame',
              isActive: _capture.paused,
              color: EditorTheme.warning,
              onTap: () => _capture.paused = !_capture.paused,
            ),
            EditorIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Clear the capture',
              onTap: samples.isEmpty ? null : _capture.clear,
            ),
            const SizedBox(width: 6),
            Text(
              'Budget',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
            ),
            for (final fps in {
              widget.scope.prefs.settings.value.targetFps.round(),
              60,
              30,
            }.toList()..sort((a, b) => b.compareTo(a)))
              EditorChip(
                label: '$fps fps',
                selected: (_capture.budgetMs - 1000 / fps).abs() < 0.01,
                onTap: () => _setBudget(1000 / fps),
              ),
            const SizedBox(width: 10),
            _Stat('avg', '${_capture.averageMs.toStringAsFixed(2)} ms'),
            _Stat('worst', '${_capture.worstMs.toStringAsFixed(2)} ms'),
            _Stat(
              'over budget',
              '${_capture.spikes}',
              color: _capture.spikes > 0 ? EditorTheme.error : null,
            ),
            _Stat('frames', '${samples.length}'),
            const Spacer(),
            if (widget.details != null)
              EditorChip(
                label: 'Details',
                icon: Icons.insights_rounded,
                selected: _showDetails,
                onTap: () => setState(() => _showDetails = !_showDetails),
              ),
            EditorIconButton(
              icon: Icons.save_alt_rounded,
              tooltip: 'Export the capture to .editor_logs/',
              onTap: samples.isEmpty ? null : _export,
            ),
          ],
        ),
        if (_showDetails && widget.details != null)
          Expanded(child: widget.details!(context))
        else if (samples.isEmpty)
          const Expanded(
            child: EditorEmptyState(
              icon: Icons.speed_rounded,
              title: 'No frames yet',
              hint:
                  'Frames are captured while the game runs. Press Play, then '
                  'pause here and click a frame to see what it cost.',
            ),
          )
        else ...[
          SizedBox(
            height: 92,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _pick(d.localPosition.dx, box.maxWidth),
                child: CustomPaint(
                  size: Size(box.maxWidth, 92),
                  painter: _FrameGraphPainter(
                    samples: List.of(samples),
                    budgetMs: _capture.budgetMs,
                    selected: _capture.selectedIndex,
                  ),
                ),
              ),
            ),
          ),
          if (selected != null) _breakdown(selected),
          Expanded(
            child: DockTable<SystemStat>(
              rows: _capture.systemStats,
              columns: [
                DockColumn(
                  label: 'System',
                  flex: 3,
                  text: (s) => s.name,
                  color: (s) => systemColor(s.name),
                ),
                DockColumn(
                  label: _capture.selectedIndex == null
                      ? 'Last ms'
                      : 'Frame ms',
                  numeric: true,
                  text: (s) => s.selected.toStringAsFixed(3),
                  sortKey: (s) => s.selected,
                ),
                DockColumn(
                  label: 'Avg ms',
                  numeric: true,
                  text: (s) => s.average.toStringAsFixed(3),
                  sortKey: (s) => s.average,
                ),
                DockColumn(
                  label: 'Max ms',
                  numeric: true,
                  text: (s) => s.max.toStringAsFixed(3),
                  sortKey: (s) => s.max,
                  color: (s) => s.max > _capture.budgetMs / 2
                      ? EditorTheme.warning
                      : null,
                ),
                DockColumn(
                  label: 'Share',
                  numeric: true,
                  text: (s) => '${(s.share * 100).toStringAsFixed(1)}%',
                  sortKey: (s) => s.share,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _pick(double x, double width) {
    final n = _capture.samples.length;
    if (n == 0 || width <= 0) return;
    final slot = width / math.max(n, _FrameGraphPainter.minSlots);
    // Bars are right-aligned: the newest frame is at the right edge.
    final fromRight = ((width - x) / slot).floor();
    _capture.select(n - 1 - fromRight);
  }

  /// The selected frame as one bar, a segment per system.
  Widget _breakdown(FrameSample frame) {
    final systems = frame.systems.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = systems.fold(0.0, (a, e) => a + e.value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              'Frame ${frame.frame} · ${frame.ms.toStringAsFixed(2)} ms · '
              '${frame.entities} ent',
              style: TextStyle(
                color: frame.ms > _capture.budgetMs
                    ? EditorTheme.error
                    : EditorTheme.textSecondary,
                fontSize: 10,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 12,
                child: total <= 0
                    ? ColoredBox(color: EditorTheme.surfaceDarker)
                    : Row(
                        children: [
                          for (final e in systems)
                            if (e.value > 0)
                              Expanded(
                                flex: math.max(
                                  1,
                                  (e.value / total * 1000).round(),
                                ),
                                child: Tooltip(
                                  message:
                                      '${e.key}: ${e.value.toStringAsFixed(3)} ms',
                                  child: ColoredBox(color: systemColor(e.key)),
                                ),
                              ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(color: EditorTheme.textMuted),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: color ?? EditorTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      style: const TextStyle(
        fontSize: 10,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// A bar per frame, newest at the right; the budget as a line across.
class _FrameGraphPainter extends CustomPainter {
  _FrameGraphPainter({
    required this.samples,
    required this.budgetMs,
    required this.selected,
  });

  final List<FrameSample> samples;
  final double budgetMs;
  final int? selected;

  /// A short capture does not stretch to fill the width.
  static const int minSlots = 120;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = EditorTheme.surfaceDarker,
    );
    if (samples.isEmpty) return;
    final worst = samples.fold(0.0, (w, s) => math.max(w, s.ms));
    // Room above the budget line, so a frame on budget does not touch the top.
    final top = math.max(worst, budgetMs * 2);
    final slot = size.width / math.max(samples.length, minSlots);
    double y(double ms) =>
        size.height - (ms / top).clamp(0.0, 1.0) * (size.height - 4);

    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final x = size.width - (samples.length - i) * slot;
      final over = s.ms > budgetMs;
      canvas.drawRect(
        Rect.fromLTRB(x, y(s.ms), x + math.max(1, slot - 0.5), size.height),
        Paint()
          ..color = i == selected
              ? EditorTheme.textPrimary
              : over
              ? EditorTheme.error
              : s.ms > budgetMs * 0.75
              ? EditorTheme.warning
              : EditorTheme.success.withValues(alpha: 0.8),
      );
    }

    final line = Paint()
      ..color = EditorTheme.textPrimary.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (final ms in [budgetMs, budgetMs * 2]) {
      if (ms > top) continue;
      canvas.drawLine(Offset(0, y(ms)), Offset(size.width, y(ms)), line);
      final label = TextPainter(
        text: TextSpan(
          text: '${ms.toStringAsFixed(1)} ms',
          style: TextStyle(color: EditorTheme.textMuted, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label
        ..paint(canvas, Offset(4, y(ms) - label.height - 1))
        ..dispose();
    }
  }

  @override
  bool shouldRepaint(_FrameGraphPainter old) =>
      old.samples.length != samples.length ||
      old.selected != selected ||
      old.budgetMs != budgetMs ||
      (samples.isNotEmpty &&
          old.samples.isNotEmpty &&
          old.samples.last.frame != samples.last.frame);
}
