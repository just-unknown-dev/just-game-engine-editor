import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../services/editor_log_service.dart';

/// Captures ECS runtime changes and forwards them into the editor log stream.
class EditorLogCaptureSystem extends System {
  EditorLogCaptureSystem(this._logService);

  final EditorLogService _logService;

  int? _lastEntityCount;
  int? _lastActiveEntityCount;
  int? _lastSystemCount;
  DateTime _lastEmission = DateTime.fromMillisecondsSinceEpoch(0);
  bool _hasLoggedStartup = false;

  @override
  int get priority => SystemPriorities.boundary - 1;

  @override
  List<Type> get requiredComponents => const <Type>[];

  @override
  void update(double deltaTime) {
    if (!_hasLoggedStartup) {
      _hasLoggedStartup = true;
      _logService.log(
        'Runtime ECS log capture is active.',
        source: 'runtime',
        category: 'capture',
      );
    }

    final totalEntities = world.entities.length;
    final activeEntities = world.activeEntities.length;
    final systemCount = world.systems.length;

    final changed =
        _lastEntityCount != totalEntities ||
        _lastActiveEntityCount != activeEntities ||
        _lastSystemCount != systemCount;
    if (!changed) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastEmission) < const Duration(milliseconds: 250)) {
      _lastEntityCount = totalEntities;
      _lastActiveEntityCount = activeEntities;
      _lastSystemCount = systemCount;
      return;
    }

    _lastEmission = now;
    _lastEntityCount = totalEntities;
    _lastActiveEntityCount = activeEntities;
    _lastSystemCount = systemCount;

    _logService.log(
      'World snapshot changed: $totalEntities entities, '
      '$activeEntities active, $systemCount systems.',
      source: 'runtime',
      category: 'ecs',
      level: DebuggerLogLevel.info,
    );
  }
}
