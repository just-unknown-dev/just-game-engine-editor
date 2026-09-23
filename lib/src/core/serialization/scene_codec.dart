import 'package:just_game_engine/just_game_engine.dart';

/// Encodes and decodes components for one editor, through the engine's
/// definition registry.
///
/// The same registry the shipped game loads with, so the editor and the game
/// cannot disagree about what a saved level means. A component with no
/// definition is not saved — the save path warns instead of silently writing
/// something the game would then refuse to load.
class SceneCodec {
  const SceneCodec(this.definitions);

  /// Over the process-wide registry the game registers into at boot.
  static SceneCodec get global =>
      SceneCodec(ComponentDefinitionRegistry.instance);

  /// Where component definitions come from.
  final ComponentDefinitionRegistry definitions;

  /// Encodes [component], or null if it has no definition.
  Map<String, dynamic>? encode(Component component) =>
      definitions.encode(component);

  /// Decodes [json], or null if its type is unknown.
  Component? decode(Map<String, dynamic> json) => definitions.decode(json);

  /// Whether [component] would be saved.
  bool canEncode(Component component) => definitions.canEncode(component);

  /// Encodes [entities] the way a scene file stores them.
  ///
  /// Destroyed entities are gone from the world already; a switched-off
  /// one is saved with `enabled: false`, because being off is part of
  /// the scene. Components with no definition are skipped — runtime-only
  /// state such as a physics body handle.
  List<Map<String, dynamic>> encodeEntities(
    List<Entity> entities, {
    List<EntityId>? rootOrder,
  }) {
    final active = _inTreeOrder(
      entities.where((e) => e.isAlive).toList(),
      rootOrder: rootOrder,
    );
    final names = {for (final e in active) e.id: e.name ?? 'entity_${e.id}'};
    return [
      for (final e in active)
        {
          'name': e.name,
          // Left out when it is on, which is nearly always.
          if (!e.isActive) 'enabled': false,
          'parentName': switch (e.getComponent<ParentComponent>()?.parentId) {
            final id? => names[id],
            null => null,
          },
          'components': e.components
              .map(encode)
              .whereType<Map<String, dynamic>>()
              .toList(),
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
  static List<Entity> _inTreeOrder(
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
