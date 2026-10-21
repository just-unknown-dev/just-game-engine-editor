import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_debugger/just_debugger.dart';

/// One frame, as the profiler keeps it.
class FrameSample {
  const FrameSample({
    required this.frame,
    required this.ms,
    required this.fps,
    required this.systems,
    required this.entities,
  });

  final int frame;

  /// Time the update took.
  final double ms;
  final int fps;

  /// Milliseconds per system, this frame.
  final Map<String, double> systems;
  final int entities;

  Map<String, dynamic> toJson() => {
    'frame': frame,
    'ms': ms,
    'fps': fps,
    'entities': entities,
    'systems': systems,
  };
}

/// A system's cost over the captured window.
class SystemStat {
  const SystemStat({
    required this.name,
    required this.selected,
    required this.average,
    required this.max,
    required this.share,
  });

  final String name;

  /// In the selected frame (the latest, when none is).
  final double selected;
  final double average;
  final double max;

  /// Of all system time in the window, 0–1.
  final double share;
}

/// The last few hundred frames, held so they can be looked at: paused,
/// scrubbed, and broken down by system.
class FrameCapture extends ChangeNotifier {
  FrameCapture({this.capacity = 600});

  final int capacity;
  final List<FrameSample> _samples = [];

  /// Frame time that counts as on budget: 16.7 ms is 60 fps.
  double budgetMs = 1000 / 60;

  bool _paused = false;
  int? _selected;

  List<FrameSample> get samples => _samples;
  bool get paused => _paused;

  set paused(bool value) {
    if (_paused == value) return;
    _paused = value;
    if (!value) _selected = null;
    notifyListeners();
  }

  /// Index into [samples] of the frame being inspected; null follows the
  /// newest.
  int? get selectedIndex => _selected;

  FrameSample? get selected => _samples.isEmpty
      ? null
      : _samples[(_selected ?? _samples.length - 1).clamp(
          0,
          _samples.length - 1,
        )];

  /// Looks at one frame. Looking is pausing: the frame must hold still.
  void select(int index) {
    if (_samples.isEmpty) return;
    _paused = true;
    _selected = index.clamp(0, _samples.length - 1);
    notifyListeners();
  }

  /// Takes a frame from the debugger. Ignored while paused, and when the
  /// frame has not advanced (the game is frozen, in the editor).
  void add(PerformanceDebuggerSnapshot performance, {int entities = 0}) {
    if (_paused) return;
    if (_samples.isNotEmpty && _samples.last.frame == performance.frameNumber) {
      return;
    }
    _samples.add(
      FrameSample(
        frame: performance.frameNumber,
        ms: performance.lastUpdateMs,
        fps: performance.currentFps,
        systems: Map.unmodifiable(performance.systemTimesMs),
        entities: entities,
      ),
    );
    if (_samples.length > capacity) {
      _samples.removeRange(0, _samples.length - capacity);
    }
    notifyListeners();
  }

  void clear() {
    _samples.clear();
    _selected = null;
    notifyListeners();
  }

  /// Frames over [budgetMs].
  int get spikes => _samples.where((s) => s.ms > budgetMs).length;

  double get averageMs => _samples.isEmpty
      ? 0
      : _samples.fold(0.0, (a, s) => a + s.ms) / _samples.length;

  double get worstMs =>
      _samples.fold(0.0, (worst, s) => s.ms > worst ? s.ms : worst);

  /// Every system seen in the window, costliest on average first.
  List<SystemStat> get systemStats {
    final totals = <String, double>{};
    final maxes = <String, double>{};
    for (final s in _samples) {
      for (final e in s.systems.entries) {
        totals[e.key] = (totals[e.key] ?? 0) + e.value;
        if (e.value > (maxes[e.key] ?? 0)) maxes[e.key] = e.value;
      }
    }
    final all = totals.values.fold(0.0, (a, b) => a + b);
    final now = selected?.systems ?? const <String, double>{};
    final n = _samples.isEmpty ? 1 : _samples.length;
    return [
      for (final name in totals.keys)
        SystemStat(
          name: name,
          selected: now[name] ?? 0,
          average: totals[name]! / n,
          max: maxes[name] ?? 0,
          share: all <= 0 ? 0 : totals[name]! / all,
        ),
    ]..sort((a, b) => b.average.compareTo(a.average));
  }

  String toJsonText() => const JsonEncoder.withIndent(' ').convert({
    'budgetMs': budgetMs,
    'frames': [for (final s in _samples) s.toJson()],
  });
}
