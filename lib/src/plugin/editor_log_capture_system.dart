import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';

/// Captures ECS runtime changes and forwards them into the editor log stream.
///
/// Cheap every frame: it reads the world's counts ([World.entityCount], the
/// system list), never walks the entities. A change in the systems is
/// logged as it happens; a change in how many entities there are at most
/// once every [entityInterval] — a game spawning bullets would otherwise
/// write a line four times a second into the session log, for the whole
/// session.
class EditorLogCaptureSystem extends System {
  EditorLogCaptureSystem(this._logService);

  final EditorLogService _logService;

  /// How often, at most, a change in the number of entities is logged.
  static const Duration entityInterval = Duration(seconds: 5);

  int? _lastEntityCount;
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

    final totalEntities = world.entityCount;
    final systemCount = world.systems.length;
    final systemsChanged = _lastSystemCount != systemCount;
    if (!systemsChanged && _lastEntityCount == totalEntities) return;

    final now = DateTime.now();
    final wait = systemsChanged
        ? const Duration(milliseconds: 250)
        : entityInterval;
    // Too soon: said with the next line, when there is one.
    if (now.difference(_lastEmission) < wait) return;

    _lastEmission = now;
    _lastEntityCount = totalEntities;
    _lastSystemCount = systemCount;

    _logService.log(
      'World snapshot changed: $totalEntities entities, '
      '$systemCount systems.',
      source: 'runtime',
      category: 'ecs',
      level: DebuggerLogLevel.info,
    );
  }
}
