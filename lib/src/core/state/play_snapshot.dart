import 'package:just_game_engine/just_game_engine.dart';

import '../../ui/level_designer/state/editor_commands.dart';
import '../serialization/scene_codec.dart';

/// The authored scene, captured when play starts and put back when it stops.
///
/// Play runs the real systems on the real entities, so platforms move,
/// bodies fall and pickups disappear. Without this, stopping left all of that
/// in place and the next save wrote it into the level — including the player
/// play had spawned.
class PlaySnapshot {
  PlaySnapshot._(this.ids, this.entities, this.existing, this.codec);

  /// Captures every authored entity in [world], through [codec].
  factory PlaySnapshot.capture(World world, SceneCodec codec) {
    final authoredEntities = authored(world);
    return PlaySnapshot._(
      [for (final e in authoredEntities) e.id],
      codec.encodeEntities(authoredEntities),
      {
        // Everything that was there when play began — a transform query
        // left every piece of interface out, and the tree then listed a
        // HUD as something the running game had spawned.
        for (final e in world.entities)
          if (e.isAlive) e.id,
      },
      codec,
    );
  }

  /// The entities a save writes: everything active with a transform.
  /// What the scene file holds: everything in the world.
  ///
  /// Not a list of the components that count, which is what this was —
  /// first transforms only, which lost every piece of interface, then
  /// transforms and canvases and slots, which still lost a label that
  /// carried nothing but its text. The editor's world *is* the scene; a
  /// play-test's spawned entities are kept out by saving the snapshot
  /// taken when play began, not by guessing from components.
  ///
  /// Except what a system generated from other data (a tile map's
  /// collision bodies): that is rebuilt from its source, never saved.
  static List<Entity> authored(World world) =>
      world.entities.where((e) => e.isAlive && !isGenerated(e)).toList();

  /// Whether [entity] was built by a system rather than authored.
  static bool isGenerated(Entity entity) =>
      entity.hasComponent<GeneratedEntityComponent>();

  /// Ids of the authored entities, parallel to [entities].
  final List<EntityId> ids;

  /// The authored entities encoded exactly as a scene file stores them —
  /// which is also what a save during play writes.
  final List<Map<String, dynamic>> entities;

  /// Every entity that existed when play started, authored or not. Only
  /// entities outside this set are removed on restore.
  final Set<EntityId> existing;

  /// The codec the snapshot was taken with; restores decode through it.
  final SceneCodec codec;

  /// Puts [world] back to this snapshot. Returns how many authored entities
  /// were restored.
  ///
  /// In place wherever possible: an entity that survived play keeps its id and
  /// only has its components replaced, so selection, undo history and the
  /// physics body bound to it all stay valid. Only entities play destroyed are
  /// recreated, and only entities play created are removed.
  int restoreInto(World world) {
    final kept = <EntityId>{};
    final byName = <String, Entity>{};

    for (var i = 0; i < ids.length; i++) {
      final json = entities[i];
      final name = json['name'] as String?;
      final componentsJson = (json['components'] as List)
          .cast<Map<String, dynamic>>();
      var entity = world.getEntity(ids[i]);
      if (entity != null && entity.isAlive) {
        EntitySpec(
          name: name,
          componentsJson: componentsJson,
          codec: codec,
        ).applyTo(entity);
        // On again unless the scene says it is switched off: play may
        // have disabled it, but being off is the author's choice.
        entity.isActive = json['enabled'] != false;
      } else {
        entity = world.createEntityWithComponents(
          EntitySpec(
            name: name,
            componentsJson: componentsJson,
            codec: codec,
          ).decode(),
          name: name,
        );
        entity.isActive = json['enabled'] != false;
      }
      kept.add(entity.id);
      if (name != null) byName[name] = entity;
    }

    for (final e in world.entities.toList()) {
      if (!kept.contains(e.id) && !existing.contains(e.id)) {
        world.destroyEntity(e);
      }
    }

    // Parents are stored by name; re-link as openScene does.
    for (final json in entities) {
      final parentName = json['parentName'] as String?;
      final child = byName[json['name'] as String?];
      final parent = parentName == null ? null : byName[parentName];
      if (child == null || parent == null) continue;
      child.getComponent<ParentComponent>()?.parentId = parent.id;
      if (!parent.hasComponent<ChildrenComponent>()) {
        parent.addComponent(ChildrenComponent());
      }
      final children = parent.getComponent<ChildrenComponent>()!;
      if (!children.childIds.contains(child.id)) children.addChild(child.id);
    }

    return ids.length;
  }
}
