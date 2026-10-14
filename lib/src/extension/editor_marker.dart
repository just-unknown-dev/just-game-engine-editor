import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

/// A small icon the viewport draws at every entity of a kind, selected or
/// not, so things with nothing to draw can be found at a glance: a camera,
/// a spawn point, a light.
///
/// The editor brings [cameras] and [spawnPoints]; a module adds its own
/// (`EditorModule.markers`).
final class EditorMarker {
  /// A marker for entities with a transform and every one of [components]
  /// (and that [where] accepts, when given).
  const EditorMarker({
    required this.id,
    required this.components,
    required this.icon,
    required this.color,
    this.label,
    this.where,
  });

  /// Names it.
  final String id;

  /// What an entity must have, besides a transform.
  final List<Type> components;

  /// Drawn at the entity.
  final IconData icon;

  /// Its colour.
  final Color color;

  /// Text under the icon, or null for none.
  final String? Function(jge.Entity entity)? label;

  /// A further test, or null to take every entity with [components].
  final bool Function(jge.Entity entity)? where;

  /// Virtual cameras.
  static const EditorMarker cameras = EditorMarker(
    id: 'camera',
    components: [jge.VirtualCameraComponent],
    icon: Icons.videocam_rounded,
    color: Color(0xFF40E0D0),
  );

  /// Spawn points, labelled with their spawner.
  static final EditorMarker spawnPoints = EditorMarker(
    id: 'spawn',
    components: const [jge.SpawnComponent],
    icon: Icons.person_pin_circle_rounded,
    color: const Color(0xFFFFB74D),
    label: (e) => e.getComponent<jge.SpawnComponent>()?.spawner,
  );

  /// The editor's own.
  static List<EditorMarker> get builtIn => [cameras, spawnPoints];
}
