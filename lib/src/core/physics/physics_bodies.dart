import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../state/play_snapshot.dart';

/// What the editor knows of a scene's physics bodies, 2-D and 3-D alike:
/// a body is an entity with a collider (`Collider2D`, `Collider3D`) or a
/// component on a collision layer (`RigidBody2D`, `RigidBody3D`,
/// `CharacterBody2D`, `CharacterBody3D` — anything with a `layer` field of
/// the physics-layer kind), so the Physics Layers dock, its counts and its
/// highlight see every one.
abstract final class PhysicsBodies {
  /// The collision layer [entity]'s body is on — its rigid or character
  /// body's — 0 for a collider alone; null when it has no body.
  static int? layerOf(jge.Entity entity, jge.ComponentDefinitionRegistry definitions) {
    var body = false;
    int? layer;
    for (final c in entity.components) {
      final definition = definitions.definitionFor(c);
      if (definition == null) continue;
      if (definition.type == 'Collider2D' || definition.type == 'Collider3D') body = true;
      for (final f in definition.fields) {
        if (f.kind == jge.FieldTypes.physicsLayer) {
          layer ??= (f.read(c) as num?)?.toInt();
          body = true;
        }
      }
    }
    return body ? jge.PhysicsLayers.clampLayer(layer ?? 0) : null;
  }

  /// Whether an author placed [entity]: not a level map's body, not one
  /// the game made while it played.
  static bool isAuthored(jge.Entity entity) =>
      !PlaySnapshot.isGenerated(entity) && !entity.hasComponent<jge.MapBodyComponent>();

  /// The bodies an author placed in [world], by the layer they are on.
  static List<List<jge.Entity>> byLayer(jge.World world, jge.ComponentDefinitionRegistry definitions) {
    final out = List.generate(jge.PhysicsLayers.count, (_) => <jge.Entity>[]);
    for (final e in world.entities) {
      if (!isAuthored(e)) continue;
      final layer = layerOf(e, definitions);
      if (layer != null) out[layer].add(e);
    }
    return out;
  }
}
