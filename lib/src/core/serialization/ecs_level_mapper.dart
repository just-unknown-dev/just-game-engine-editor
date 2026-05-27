import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

// ── Snapshot types ────────────────────────────────────────────────────────────
//
// These mirror the game-app's LevelData hierarchy without depending on it
// directly. A game app can convert EditorLevelSnapshot → its own LevelData
// by reading the typed lists below.

class EditorPlatformSnapshot {
  const EditorPlatformSnapshot({
    required this.position,
    required this.width,
    required this.height,
    this.entityName,
  });

  final Offset position;
  final double width;
  final double height;
  final String? entityName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'position': {'x': position.dx, 'y': position.dy},
    'width': width,
    'height': height,
    if (entityName != null) 'entityName': entityName,
  };
}

class EditorEnemySnapshot {
  const EditorEnemySnapshot({
    required this.position,
    required this.type,
    this.entityName,
  });

  final Offset position;
  final String type;
  final String? entityName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'position': {'x': position.dx, 'y': position.dy},
    'type': type,
    if (entityName != null) 'entityName': entityName,
  };
}

class EditorCollectibleSnapshot {
  const EditorCollectibleSnapshot({
    required this.position,
    required this.type,
    this.entityName,
  });

  final Offset position;
  final String type;
  final String? entityName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'position': {'x': position.dx, 'y': position.dy},
    'type': type,
    if (entityName != null) 'entityName': entityName,
  };
}

class EditorHazardSnapshot {
  const EditorHazardSnapshot({
    required this.position,
    required this.width,
    required this.height,
    this.entityName,
  });

  final Offset position;
  final double width;
  final double height;
  final String? entityName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'position': {'x': position.dx, 'y': position.dy},
    'width': width,
    'height': height,
    if (entityName != null) 'entityName': entityName,
  };
}

class EditorCheckpointSnapshot {
  const EditorCheckpointSnapshot({
    required this.position,
    required this.respawnPosition,
    this.entityName,
  });

  final Offset position;
  final Offset respawnPosition;
  final String? entityName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'position': {'x': position.dx, 'y': position.dy},
    'respawnPosition': {'x': respawnPosition.dx, 'y': respawnPosition.dy},
    if (entityName != null) 'entityName': entityName,
  };
}

class EditorGenericEntitySnapshot {
  const EditorGenericEntitySnapshot({
    required this.entityId,
    required this.position,
    required this.componentTypes,
    this.entityName,
  });

  final int entityId;
  final Offset position;
  final List<String> componentTypes;
  final String? entityName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'entityId': entityId,
    'position': {'x': position.dx, 'y': position.dy},
    'componentTypes': componentTypes,
    if (entityName != null) 'entityName': entityName,
  };
}

/// Full ECS-driven snapshot of the current live level.
class EditorLevelSnapshot {
  const EditorLevelSnapshot({
    required this.levelId,
    required this.capturedAt,
    this.bounds,
    this.platforms = const [],
    this.enemies = const [],
    this.collectibles = const [],
    this.hazards = const [],
    this.checkpoints = const [],
    this.generic = const [],
    this.entityCount = 0,
  });

  final String levelId;
  final DateTime capturedAt;
  final Rect? bounds;

  final List<EditorPlatformSnapshot> platforms;
  final List<EditorEnemySnapshot> enemies;
  final List<EditorCollectibleSnapshot> collectibles;
  final List<EditorHazardSnapshot> hazards;
  final List<EditorCheckpointSnapshot> checkpoints;

  /// Entities that could not be categorised by name tag.
  final List<EditorGenericEntitySnapshot> generic;

  final int entityCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': 1,
    'format': 'just_game_engine_editor_level_snapshot',
    'levelId': levelId,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'entityCount': entityCount,
    if (bounds != null)
      'bounds': {
        'left': bounds!.left,
        'top': bounds!.top,
        'width': bounds!.width,
        'height': bounds!.height,
      },
    'platforms': platforms.map((p) => p.toJson()).toList(),
    'enemies': enemies.map((e) => e.toJson()).toList(),
    'collectibles': collectibles.map((c) => c.toJson()).toList(),
    'hazards': hazards.map((h) => h.toJson()).toList(),
    'checkpoints': checkpoints.map((cp) => cp.toJson()).toList(),
    'generic': generic.map((g) => g.toJson()).toList(),
  };
}

// ── Categorisation helpers ────────────────────────────────────────────────────

/// Extracts a rough entity category from an entity name or null.
///
/// Returns one of `'platform'`, `'enemy'`, `'collectible'`, `'hazard'`,
/// `'checkpoint'`, `'player'`, or `null` if no recognisable tag is found.
String? _categorise(String? name) {
  if (name == null) return null;
  final lower = name.toLowerCase();
  if (lower.contains('platform')) return 'platform';
  if (lower.contains('enemy') ||
      lower.contains('walker') ||
      lower.contains('jumper') ||
      lower.contains('shooter') ||
      lower.contains('flyer') ||
      lower.contains('boss')) {
    return 'enemy';
  }
  if (lower.contains('coin') ||
      lower.contains('collect') ||
      lower.contains('powerup') ||
      lower.contains('healthpack')) {
    return 'collectible';
  }
  if (lower.contains('hazard') || lower.contains('spike')) {
    return 'hazard';
  }
  if (lower.contains('checkpoint')) {
    return 'checkpoint';
  }
  if (lower.contains('player')) {
    return 'player';
  }
  return null;
}

// ── Mapper ────────────────────────────────────────────────────────────────────

/// Maps a live ECS [World] to an [EditorLevelSnapshot].
///
/// The mapper only reads from the engine — it never writes to it — making it
/// safe to call at any point during a frame without affecting the game loop.
///
/// Entity categorisation is performed by matching [Entity.name] against a set
/// of known keywords (see [_categorise]). Game-specific component types
/// (PlatformerComponent, EnemyComponent, etc.) live in the game app and are
/// not referenced here; any entity carrying a [RectangleComponent] is used for
/// size extraction where available.
class EcsLevelMapper {
  const EcsLevelMapper();

  /// Produce a snapshot from all currently active entities in [world].
  ///
  /// Pass [levelId] to tag the snapshot for serialization or diffing.
  EditorLevelSnapshot snapshot(World world, {String levelId = 'current'}) {
    final entities = world.query([TransformComponent]);

    final platforms = <EditorPlatformSnapshot>[];
    final enemies = <EditorEnemySnapshot>[];
    final collectibles = <EditorCollectibleSnapshot>[];
    final hazards = <EditorHazardSnapshot>[];
    final checkpoints = <EditorCheckpointSnapshot>[];
    final generic = <EditorGenericEntitySnapshot>[];

    for (final entity in entities) {
      if (!entity.isActive) continue;

      final transform = entity.getComponent<TransformComponent>();
      if (transform == null) continue;

      final pos = transform.position.toOffset();
      final rect = entity.getComponent<RectangleComponent>();
      final w = rect?.width ?? 64.0;
      final h = rect?.height ?? 64.0;

      final category = _categorise(entity.name);

      switch (category) {
        case 'platform':
          platforms.add(
            EditorPlatformSnapshot(
              position: pos,
              width: w,
              height: h,
              entityName: entity.name,
            ),
          );

        case 'enemy':
          enemies.add(
            EditorEnemySnapshot(
              position: pos,
              type: _inferEnemyType(entity.name),
              entityName: entity.name,
            ),
          );

        case 'collectible':
          collectibles.add(
            EditorCollectibleSnapshot(
              position: pos,
              type: _inferCollectibleType(entity.name),
              entityName: entity.name,
            ),
          );

        case 'hazard':
          hazards.add(
            EditorHazardSnapshot(
              position: pos,
              width: w,
              height: h,
              entityName: entity.name,
            ),
          );

        case 'checkpoint':
          checkpoints.add(
            EditorCheckpointSnapshot(
              position: pos,
              respawnPosition: pos, // TODO: read respawn offset from component
              entityName: entity.name,
            ),
          );

        default:
          // Player and uncategorised entities go into generic list.
          generic.add(
            EditorGenericEntitySnapshot(
              entityId: entity.id,
              position: pos,
              componentTypes: entity.components
                  .map((c) => c.runtimeType.toString())
                  .toList(),
              entityName: entity.name,
            ),
          );
      }
    }

    return EditorLevelSnapshot(
      levelId: levelId,
      capturedAt: DateTime.now(),
      platforms: platforms,
      enemies: enemies,
      collectibles: collectibles,
      hazards: hazards,
      checkpoints: checkpoints,
      generic: generic,
      entityCount: entities.length,
    );
  }

  /// Serialize a snapshot to JSON in a background isolate.
  ///
  /// Uses [compute] so the game-loop / raster threads are not blocked during
  /// large level exports.
  Future<String> snapshotToJson(
    World world, {
    String levelId = 'current',
  }) async {
    final snap = snapshot(world, levelId: levelId);
    return compute<Map<String, dynamic>, String>(
      _encodeSnapshotOnBackground,
      snap.toJson(),
    );
  }
}

// ── Background isolate worker ─────────────────────────────────────────────────

/// Top-level (isolate-safe) encode function.
String _encodeSnapshotOnBackground(Map<String, dynamic> json) {
  return jsonEncode(json);
}

// ── Internal helpers ──────────────────────────────────────────────────────────

String _inferEnemyType(String? name) {
  if (name == null) {
    return 'walker';
  }
  final lower = name.toLowerCase();
  for (final type in ['boss', 'shooter', 'flyer', 'jumper', 'walker']) {
    if (lower.contains(type)) {
      return type;
    }
  }
  return 'walker';
}

String _inferCollectibleType(String? name) {
  if (name == null) {
    return 'coin';
  }
  final lower = name.toLowerCase();
  if (lower.contains('health')) {
    return 'healthpack';
  }
  if (lower.contains('power')) {
    return 'powerup';
  }
  return 'coin';
}
