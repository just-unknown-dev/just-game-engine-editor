import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';

/// The authored scene, captured when play starts and put back when it stops.
///
/// Play runs the real systems on the real entities, so platforms move,
/// bodies fall and pickups disappear. Without this, stopping left all of that
/// in place and the next save wrote it into the level — including the player
/// play had spawned.
class PlaySnapshot {
  PlaySnapshot._(
    this._records,
    this.entities,
    this._existing,
    this.existing,
    this.codec,
  );

  /// Captures every authored entity in [world], through [codec].
  factory PlaySnapshot.capture(World world, SceneCodec codec) {
    // In the order a scene file is written — parents first — and encoded in
    // that same order, so each record stays beside the entity it was taken
    // from. Taking the entities in world order and the records in file order
    // paired them wrongly as soon as the two differed (an entity made late
    // but placed early), and stopping play then gave every entity after it
    // its neighbour's name, components and place in the tree.
    final ordered = SceneCodec.inTreeOrder(authored(world));
    final encoded = codec.encodeInOrder(ordered);
    final indexOf = <EntityId, int>{
      for (var i = 0; i < ordered.length; i++) ordered[i].id: i,
    };
    final records = <_Record>[];
    for (var i = 0; i < ordered.length; i++) {
      final entity = ordered[i];
      final parentId = entity.getComponent<ParentComponent>()?.parentId;
      final parentIndex = parentId == null ? null : indexOf[parentId];
      records.add(
        _Record(
          entity: entity,
          json: encoded[i],
          parentIndex: parentIndex,
          // Parented to something play does not put back (a generated
          // entity): that link is left alone.
          outsideParent: parentId != null && parentIndex == null,
        ),
      );
    }
    final alive = world.entities.where((e) => e.isAlive).toList();
    return PlaySnapshot._(
      records,
      // What a save writes: prefab instances folded back into what they
      // change, worked out now, before play moves anything.
      codec.collapseMarked(codec.encodeForSave(ordered)),
      Set<Entity>.identity()..addAll(alive),
      // Everything that was there when play began — a transform query
      // left every piece of interface out, and the tree then listed a
      // HUD as something the running game had spawned.
      {for (final e in alive) e.id},
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

  final List<_Record> _records;

  /// Ids of the authored entities, in the order they were captured.
  List<EntityId> get ids => [for (final r in _records) r.entity.id];

  /// The authored entities encoded exactly as a scene file stores them —
  /// which is also what a save during play writes: an instance of a prefab
  /// one entry, not one per entity it made.
  final List<Map<String, dynamic>> entities;

  /// Every entity that existed when play started, authored or not. Only
  /// entities outside this set are removed on restore.
  ///
  /// Held by identity: ids are handed out again once an entity is
  /// destroyed, so an id alone could keep something play made.
  final Set<Entity> _existing;

  /// The ids of [_existing], for the scene tree's runtime divider.
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
    final restored = <Entity>[];
    for (final record in _records) {
      final name = record.json['name'] as String?;
      final componentsJson = (record.json['components'] as List)
          .cast<Map<String, dynamic>>();
      final spec = EntitySpec(
        name: name,
        componentsJson: componentsJson,
        codec: codec,
      );
      var entity = record.entity;
      if (world.isEntityAlive(entity)) {
        spec.applyTo(entity);
      } else {
        entity = world.createEntityWithComponents(spec.decode(), name: name);
      }
      // On again unless the scene says it is switched off: play may
      // have disabled it, but being off is the author's choice.
      entity.isActive = record.json['enabled'] != false;
      restored.add(entity);
    }

    final kept = Set<Entity>.identity()..addAll(restored);
    for (final e in world.entities.toList()) {
      if (!kept.contains(e) && !_existing.contains(e)) {
        // An authored entity parented under a play-spawned one survives.
        world.destroyEntity(e, withChildren: false);
      }
    }

    _relink(world, restored, kept);
    // Every link was made anew: work out each child's offset from where the
    // restored world transforms put it.
    world.transformHierarchy.propagate();
    return restored.length;
  }

  /// Rebuilds every restored entity's place in the tree from the records.
  ///
  /// `applyTo` leaves an entity's links as they are, so this is the only
  /// place they are put back: a parent the record has is set (and made where
  /// the entity has none — its offset follows from the restored
  /// transforms); one it lacks is removed; and each parent lists its
  /// restored children in record order —
  /// the order a save writes them in — followed by any child play did not
  /// own that still hangs from it.
  void _relink(World world, List<Entity> restored, Set<Entity> kept) {
    for (var i = 0; i < _records.length; i++) {
      final record = _records[i];
      final entity = restored[i];
      final parentIndex = record.parentIndex;
      if (parentIndex != null) {
        final link = _savedLink(record) ?? ParentComponent();
        link.parentId = restored[parentIndex].id;
        entity.addComponent(link);
      } else if (!record.outsideParent &&
          entity.hasComponent<ParentComponent>()) {
        entity.removeComponentByType(ParentComponent);
      }
    }

    final childrenOf = <int, List<Entity>>{};
    for (var i = 0; i < _records.length; i++) {
      final parentIndex = _records[i].parentIndex;
      if (parentIndex != null) {
        (childrenOf[parentIndex] ??= []).add(restored[i]);
      }
    }
    for (var i = 0; i < restored.length; i++) {
      final parent = restored[i];
      final previous = parent.getComponent<ChildrenComponent>()?.childIds;
      final ids = [
        for (final child in childrenOf[i] ?? const <Entity>[]) child.id,
        // Children play did not put back — a generated collision body —
        // that are still here and still point at this parent.
        for (final id in previous ?? const <EntityId>[])
          if (world.getEntity(id) case final other?
              when !kept.contains(other) &&
                  other.getComponent<ParentComponent>()?.parentId == parent.id)
            id,
      ];
      if (ids.isEmpty) {
        if (previous != null) {
          parent.removeComponentByType(ChildrenComponent);
        }
        continue;
      }
      final children = parent.getComponent<ChildrenComponent>();
      if (children == null) {
        parent.addComponent(ChildrenComponent()..childIds.addAll(ids));
      } else {
        children.childIds
          ..clear()
          ..addAll(ids);
      }
    }
  }

  /// The parent link the record was saved with — its local offset and turn —
  /// or null where it saved none.
  ParentComponent? _savedLink(_Record record) {
    for (final json
        in (record.json['components'] as List).cast<Map<String, dynamic>>()) {
      if (json['type'] != 'ParentComponent') continue;
      final decoded = codec.decode(json);
      if (decoded is ParentComponent) return decoded;
    }
    return null;
  }
}

/// One authored entity as play found it.
class _Record {
  const _Record({
    required this.entity,
    required this.json,
    required this.parentIndex,
    required this.outsideParent,
  });

  /// The entity the record was taken from, by identity.
  final Entity entity;

  /// The entity as a scene file stores it.
  final Map<String, dynamic> json;

  /// The record index of its parent, or null for a root.
  final int? parentIndex;

  /// Whether its parent is something the snapshot does not hold.
  final bool outsideParent;
}
