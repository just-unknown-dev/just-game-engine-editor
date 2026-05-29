part of 'editor_overlay.dart';

class _DockMetricsSnapshot {
  const _DockMetricsSnapshot({
    required this.snapshot,
    required this.performance,
    required this.memory,
    required this.health,
    required this.logs,
  });

  final EcsDebuggerSnapshot snapshot;
  final PerformanceDebuggerSnapshot performance;
  final MemoryDebuggerSnapshot memory;
  final DebuggerHealth health;
  final List<DebuggerLogEntry> logs;

  factory _DockMetricsSnapshot.fromController(
    JustDebuggerController controller,
  ) {
    return _DockMetricsSnapshot(
      snapshot: controller.snapshot,
      performance: controller.performance,
      memory: controller.memory,
      health: controller.health,
      logs: List<DebuggerLogEntry>.unmodifiable(controller.logs),
    );
  }
}
