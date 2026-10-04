import 'package:just_game_engine/just_game_engine.dart';

import 'unknown_components.dart';

/// Encodes and decodes components for one editor, through the engine's
/// definition registry.
///
/// The same registry the shipped game loads with, so the editor and the game
/// cannot disagree about what a saved level means. A component with no
/// definition is not saved — the save path warns instead of silently writing
/// something the game would then refuse to load. A *saved* component with no
/// definition is the other way round: it came from the file, so it is kept
/// ([UnknownComponents]) and written back as it was.
class SceneCodec {
  const SceneCodec(this.definitions);

  /// Where component definitions come from.
  final ComponentDefinitionRegistry definitions;

  /// Encodes [component], or null if it has no definition.
  Map<String, dynamic>? encode(Component component) =>
      definitions.encode(component);

  /// Decodes [json], or null if its type is unknown.
  Component? decode(Map<String, dynamic> json) => definitions.decode(json);

  /// Whether [component] would be saved.
  bool canEncode(Component component) =>
      component is UnknownComponents || definitions.canEncode(component);

  /// Decodes an entity's saved components, in order.
  ///
  /// What no definition can read is not dropped: it is gathered, verbatim,
  /// into one [UnknownComponents] so that [encodeAll] writes it back.
  List<Component> decodeAll(Iterable<dynamic> json) {
    final out = <Component>[];
    final unknown = <Map<String, dynamic>>[];
    for (final item in json) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final component = decode(map);
      if (component != null) {
        out.add(component);
      } else {
        unknown.add(map);
      }
    }
    if (unknown.isNotEmpty) out.add(UnknownComponents(unknown));
    return out;
  }

  /// Encodes [components] as a scene file stores them: the ones with a
  /// definition through it, the [UnknownComponents] exactly as they were
  /// read, and runtime-only state not at all.
  List<Map<String, dynamic>> encodeAll(Iterable<Component> components) => [
    for (final c in components)
      if (c is UnknownComponents)
        for (final entry in c.entries) Map<String, dynamic>.of(entry)
      else
        ?encode(c),
  ];

  /// Encodes [entities] the way a scene file stores them.
  ///
  /// Destroyed entities are gone from the world already; a switched-off
  /// one is saved with `enabled: false`, because being off is part of
  /// the scene. Components with no definition are skipped — runtime-only
  /// state such as a physics body handle.
  List<Map<String, dynamic>> encodeEntities(
    List<Entity> entities, {
    List<EntityId>? rootOrder,
  }) => encodeInOrder(
    inTreeOrder(
      entities.where((e) => e.isAlive).toList(),
      rootOrder: rootOrder,
    ),
  );

  /// Encodes [ordered] as it stands, one record per entity in the same
  /// order — for a caller that must keep each record beside its entity
  /// (see [inTreeOrder] for the order a file wants).
  List<Map<String, dynamic>> encodeInOrder(List<Entity> ordered) {
    final names = {for (final e in ordered) e.id: e.name ?? 'entity_${e.id}'};
    return [
      for (final e in ordered)
        {
          'name': e.name,
          // Left out when it is on, which is nearly always.
          if (!e.isActive) 'enabled': false,
          'parentName': switch (e.getComponent<ParentComponent>()?.parentId) {
            final id? => names[id],
            null => null,
          },
          'components': encodeAll(e.components),
        },
    ];
  }

  /// [entities] with each parent before its children, and siblings in the
  /// order their parent lists them.
  ///
  /// The order a scene file is written in *is* the sibling order: loading
  /// rebuilds each `ChildrenComponent` by walking the file. So a row whose
  /// buttons were dragged into a new order keeps it by being written in
  /// it.
  static List<Entity> inTreeOrder(
    List<Entity> entities, {
    List<EntityId>? rootOrder,
  }) {
    final byId = {for (final e in entities) e.id: e};
    final out = <Entity>[];
    final placed = <EntityId>{};

    void walk(Entity entity) {
      if (!placed.add(entity.id)) return;
      out.add(entity);
      final children = entity.getComponent<ChildrenComponent>();
      if (children == null) return;
      for (final id in children.childIds) {
        final child = byId[id];
        if (child != null) walk(child);
      }
    }

    // The roots in the order the editor holds them, so rearranging the top
    // level is a real edit and not a redraw.
    for (final id in rootOrder ?? const <EntityId>[]) {
      final entity = byId[id];
      if (entity == null) continue;
      final parentId = entity.getComponent<ParentComponent>()?.parentId;
      if (parentId == null || !byId.containsKey(parentId)) walk(entity);
    }
    for (final entity in entities) {
      final parentId = entity.getComponent<ParentComponent>()?.parentId;
      // A root, or a child whose parent is not being saved.
      if (parentId == null || !byId.containsKey(parentId)) walk(entity);
    }
    // A child its parent forgot to list, and anything in a parent loop.
    for (final entity in entities) {
      walk(entity);
    }
    return out;
  }

  /// The definition [component] is saved and inspected through, or null.
  ComponentDefinition? definitionFor(Component component) =>
      definitions.definitionFor(component);
}
