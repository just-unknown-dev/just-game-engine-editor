library;

import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';

extension JustGameEngineDebuggerIntegration on Engine {
  JustDebuggerController createDebuggerController({
    bool overlayVisible = true,
    Duration interval = const Duration(milliseconds: 250),
    EcsComponentUsageProvider? componentUsageProvider,
    EcsSystemTimesProvider? systemTimesProvider,
    PerformanceStatsProvider? performanceStatsProvider,
    MemoryStatsProvider? memoryStatsProvider,
    bool attachImmediately = true,
  }) {
    final controller = JustDebuggerController(overlayVisible: overlayVisible);

    if (attachImmediately) {
      attachDebugger(
        controller,
        interval: interval,
        componentUsageProvider: componentUsageProvider,
        systemTimesProvider: systemTimesProvider,
        performanceStatsProvider: performanceStatsProvider,
        memoryStatsProvider: memoryStatsProvider,
      );
    }

    return controller;
  }

  /// Feeds [controller] from this engine every [interval].
  ///
  /// One refresh asks each provider in turn, and each reads the same world:
  /// what they share — the world's statistics, the engine's, the count of
  /// each kind of component — is read once per refresh, not once per
  /// provider. The editor binds it only while it is shown
  /// (`JustDebuggerController.stopBinding` otherwise), since nothing else
  /// reads it.
  void attachDebugger(
    JustDebuggerController controller, {
    Duration interval = const Duration(milliseconds: 250),
    EcsComponentUsageProvider? componentUsageProvider,
    EcsSystemTimesProvider? systemTimesProvider,
    PerformanceStatsProvider? performanceStatsProvider,
    MemoryStatsProvider? memoryStatsProvider,
    bool fireImmediately = true,
  }) {
    final reads = _DebuggerReads(this);
    controller.bindToSources(
      // Asked first on every refresh: a new refresh, read afresh.
      statsProvider: () {
        reads.begin();
        final worldStats = reads.worldStats;
        final perfStats = reads.performanceStats;
        return <String, dynamic>{
          ...worldStats,
          'frame': perfStats['frame'] ?? 0,
          'deltaTime': perfStats['deltaTime'] ?? 0.0,
          'engineLastUpdateMs': perfStats['lastUpdateMs'] ?? 0.0,
          'budgetRemainingMs': perfStats['budgetRemainingMs'] ?? 0.0,
          'isOverBudget': perfStats['isOverBudget'] ?? false,
        };
      },
      componentUsageProvider: componentUsageProvider ?? reads.componentUsage,
      systemTimesProvider: systemTimesProvider ?? reads.systemTimes,
      performanceStatsProvider:
          performanceStatsProvider ??
          () => <String, dynamic>{
            ...reads.performanceStats,
            // Polled on a timer, which may outlive the engine.
            'currentFPS': isInitialized ? gameLoop.currentFPS : 0,
            'systemTimesMs': reads.systemTimes(),
          },
      memoryStatsProvider: memoryStatsProvider ?? reads.memoryStats,
      memoryCleanupAction: () async {
        final cleanup = MemoryProfiler.cleanupGlobalResources(
          clearReleasedObjects: true,
        );

        try {
          if (isInitialized) await cache.clearAll();
        } catch (_) {}

        controller.log(
          'Released ${cleanup.releasedPools} pools and '
          '${cleanup.clearedArenas} arenas.',
          category: 'memory',
        );

        reads.begin();
        final stats = reads.memoryStats();
        final counters = Map<String, int>.from(
          stats['counters'] as Map<String, int>? ?? const <String, int>{},
        );
        counters['releasedPools'] = cleanup.releasedPools;
        counters['clearedArenas'] = cleanup.clearedArenas;
        counters['clearedCaches'] = cleanup.clearedCaches + 1;
        stats['counters'] = counters;
        return stats;
      },
      interval: interval,
      fireImmediately: fireImmediately,
    );

    controller.log(
      'Just Debugger attached to Just Game Engine.',
      category: 'runtime',
    );
  }

  /// This frame's performance, as the debugger's poll reads it — for
  /// whatever keeps every frame (the Profiler), not a sample of them.
  PerformanceDebuggerSnapshot framePerformance() {
    final reads = _DebuggerReads(this);
    return PerformanceDebuggerSnapshot.fromStats(<String, dynamic>{
      ...reads.performanceStats,
      'currentFPS': isInitialized ? gameLoop.currentFPS : 0,
      'systemTimesMs': reads.systemTimes(),
    });
  }
}

/// What one refresh of the debugger reads from [engine], each read once.
class _DebuggerReads {
  _DebuggerReads(this.engine);

  final Engine engine;

  Map<String, dynamic>? _world;
  Map<String, dynamic>? _performance;
  Map<String, int>? _usage;

  /// A new refresh: what the last one read is stale.
  void begin() {
    _world = null;
    _performance = null;
    _usage = null;
  }

  /// The world's statistics (`World.stats`, made when read).
  Map<String, dynamic> get worldStats => _world ??= () {
    try {
      return Map<String, dynamic>.from(engine.world.stats);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }();

  /// The engine's performance statistics.
  Map<String, dynamic> get performanceStats => _performance ??= () {
    try {
      return Map<String, dynamic>.from(engine.performanceStats);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }();

  /// How many of each kind of component the active entities carry. Counted
  /// by type, and each type named once — not a name made per component.
  Map<String, int> componentUsage() => _usage ??= () {
    final byType = <Type, int>{};
    try {
      for (final entity in engine.world.activeEntities) {
        for (final component in entity.components) {
          final type = component.runtimeType;
          byType[type] = (byType[type] ?? 0) + 1;
        }
      }
    } catch (_) {
      return const <String, int>{};
    }
    return <String, int>{
      for (final MapEntry(key: type, value: count) in byType.entries)
        type.toString(): count,
    };
  }();

  Map<String, dynamic> memoryStats() {
    final stats = worldStats;
    final usage = componentUsage();
    final systemMemory = MemoryProfiler.captureSystemMemory();

    return <String, dynamic>{
      'entityCount': stats['activeEntities'] ?? 0,
      'componentCount': usage.values.fold<int>(0, (sum, value) => sum + value),
      'usingCacheFallback':
          engine.isInitialized && engine.cache.isUsingMemoryFallback,
      'cleanupAvailable': true,
      'totalPhysicalMemoryBytes': systemMemory.totalPhysicalMemoryBytes,
      'freePhysicalMemoryBytes': systemMemory.freePhysicalMemoryBytes,
      'rssBytes': systemMemory.rssBytes,
      'counters': <String, int>{
        'systems': (stats['systems'] as num?)?.toInt() ?? 0,
        'archetypes': (stats['archetypes'] as num?)?.toInt() ?? 0,
        'pools': _poolCount(),
        'arenas': _arenaCount(),
      },
    };
  }

  static int _poolCount() {
    try {
      return PoolManager.instance.getPoolStats().length;
    } catch (_) {
      return 0;
    }
  }

  static int _arenaCount() {
    try {
      return PoolManager.instance.getArenaStats().length;
    } catch (_) {
      return 0;
    }
  }

  Map<String, double> systemTimes() {
    final worldTimes = _readDoubleMap(worldStats['systemTimesMs']);
    final perfTimes = _readDoubleMap(performanceStats['systemTimesMs']);
    return <String, double>{...perfTimes, ...worldTimes};
  }

  static Map<String, double> _readDoubleMap(Object? source) {
    if (source is! Map) {
      return const <String, double>{};
    }

    final output = <String, double>{};
    source.forEach((key, value) {
      if (value is num) {
        output[key.toString()] = value.toDouble();
      }
    });
    return output;
  }
}
