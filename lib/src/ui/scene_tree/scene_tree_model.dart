/// What the scene tree shows, worked out once instead of in `build`.
///
/// The old panel walked the world, built a children map, sorted roots and
/// decided depths every time anything at all changed, inside the widget
/// that drew them. Everything a row needs is settled here, where it can be
/// read and tested without a widget in sight, and the panel is left to
/// draw a flat list.
library;

import 'package:just_game_engine/just_game_engine.dart' as jge;

/// What the tree is narrowed to.
class TreeFilter {
  const TreeFilter({
    this.text = '',
    this.componentType = '',
    this.tag = '',
    this.layer = '',
    this.problems = false,
  });

  /// Matched, case-insensitively, against an entity's name *or* the name
  /// of a component it carries — typing "spawn" finds the spawn points
  /// whatever they happen to be called.
  final String text;

  /// A component's definition type — `SpriteComponent`.
  final String componentType;

  final String tag;
  final String layer;

  /// Only entities something is wrong with.
  final bool problems;

  static const TreeFilter none = TreeFilter();

  bool get isEmpty =>
      text.trim().isEmpty &&
      componentType.isEmpty &&
      tag.isEmpty &&
      layer.isEmpty &&
      !problems;

  TreeFilter copyWith({
    String? text,
    String? componentType,
    String? tag,
    String? layer,
    bool? problems,
  }) => TreeFilter(
    text: text ?? this.text,
    componentType: componentType ?? this.componentType,
    tag: tag ?? this.tag,
    layer: layer ?? this.layer,
    problems: problems ?? this.problems,
  );

  /// Whether [entity] is one of the things being looked for.
  bool matches(jge.Entity entity, {Set<jge.EntityId> withProblems = const {}}) {
    final wanted = text.trim().toLowerCase();
    if (wanted.isNotEmpty) {
      final name = (entity.name ?? '').toLowerCase();
      final byComponent = entity.components.any(
        (c) => c.runtimeType.toString().toLowerCase().contains(wanted),
      );
      if (!name.contains(wanted) && !byComponent) return false;
    }
    if (componentType.isNotEmpty) {
      final has = entity.components.any(
        (c) => c.runtimeType.toString() == componentType,
      );
      if (!has) return false;
    }
    if (tag.isNotEmpty) {
      if (entity.getComponent<jge.TagComponent>()?.tag != tag) return false;
    }
    if (layer.isNotEmpty) {
      if (entity.getComponent<jge.LayerComponent>()?.layerId != layer) {
        return false;
      }
    }
    if (problems && !withProblems.contains(entity.id)) return false;
    return true;
  }
}

/// A row of the tree that is part of a level map rather than an entity:
/// one of its layers.
sealed class MapTreeItem {
  const MapTreeItem(this.layerId);

  /// The layer, by its id within the map.
  final int layerId;
}

/// A layer of a level map.
class MapLayerTreeItem extends MapTreeItem {
  const MapLayerTreeItem(super.layerId);

  @override
  bool operator ==(Object other) =>
      other is MapLayerTreeItem && other.layerId == layerId;

  @override
  int get hashCode => Object.hash('layer', layerId);
}

/// One line of the tree.
class TreeRow {
  const TreeRow({
    required this.entity,
    required this.depth,
    required this.hasChildren,
    required this.isExpanded,
    this.isMatch = true,
    this.isRuntime = false,
    this.item,
  });

  /// The entity — for a map's layer, the map's.
  final jge.Entity entity;

  /// The map layer this row is, or null for the entity itself.
  final MapTreeItem? item;

  bool get isMapItem => item != null;

  /// How far in it is drawn.
  final int depth;

  final bool hasChildren;
  final bool isExpanded;

  /// Whether it is one of the things a filter was looking for. A row that
  /// is not is only there to hold up one that is, and is drawn faded.
  final bool isMatch;

  /// Whether the game made it while playing, rather than the scene.
  final bool isRuntime;

  jge.EntityId get id => entity.id;

  @override
  String toString() =>
      'TreeRow(${entity.name ?? entity.id}${item == null ? '' : ' $item'}, '
      'depth: $depth${isMatch ? '' : ', context'}'
      '${isRuntime ? ', runtime' : ''})';
}

/// The divider between the scene's entities and the ones a running game
/// made. Not an entity, so the tree carries it as a row with none.
class TreeSection {
  const TreeSection(this.label, this.index);

  final String label;

  /// Where it sits in the row list; the row after it is the first one
  /// under it.
  final int index;
}

/// The rows to draw, and where the runtime section begins.
class SceneTree {
  const SceneTree({required this.rows, this.runtimeAt});

  final List<TreeRow> rows;

  /// The index the runtime rows start at, or null when there are none.
  final int? runtimeAt;

  bool get isEmpty => rows.isEmpty;
  int get length => rows.length;

  /// Where [id]'s own row is in [rows], or -1.
  int indexOf(jge.EntityId id) =>
      rows.indexWhere((r) => r.id == id && r.item == null);

  /// Where the row of [item] of the map on [id] is, or -1.
  int indexOfItem(jge.EntityId id, MapTreeItem item) =>
      rows.indexWhere((r) => r.id == id && r.item == item);

  static const SceneTree empty = SceneTree(rows: []);
}

abstract final class SceneTreeModel {
  /// The rows for [world].
  ///
  /// [rootOrder] is the order the scene's top level is in — the world
  /// keeps none. [expanded] is which rows are open; under a filter
  /// everything is open, because hiding a match inside a shut parent is
  /// the one thing a search must not do. [authored] is what existed when
  /// play began: anything else is the running game's and is shown apart.
  static SceneTree build({
    required jge.World world,
    required List<jge.EntityId> rootOrder,
    required Set<jge.EntityId> expanded,
    TreeFilter filter = TreeFilter.none,
    Set<jge.EntityId>? authored,
    Set<jge.EntityId> withProblems = const {},
    TreeContents contents = TreeContents.world,
    jge.LevelMapData? Function(jge.Entity entity)? mapOf,
    Set<(jge.EntityId, int)> expandedLayers = const {},
  }) {
    final live = {
      for (final entity in world.entities)
        // Alive, not enabled: an entity switched off is still part of
        // the scene, and is listed struck through. What a system built
        // from other data (a tile map's collision) is not listed at all:
        // there can be hundreds, and none is anything to edit.
        if (entity.isAlive &&
            !entity.hasComponent<jge.GeneratedEntityComponent>())
          entity.id: entity,
    };

    // Children by parent, in the order each parent lists them; anything a
    // parent forgot to list goes after, so nothing is invisible.
    final childrenOf = <jge.EntityId, List<jge.Entity>>{};
    final claimed = <jge.EntityId>{};
    for (final entity in live.values) {
      final ids = entity.getComponent<jge.ChildrenComponent>()?.childIds;
      if (ids == null) continue;
      final kids = <jge.Entity>[];
      for (final id in ids) {
        final child = live[id];
        if (child == null) continue;
        if (child.getComponent<jge.ParentComponent>()?.parentId != entity.id) {
          continue;
        }
        kids.add(child);
        claimed.add(id);
      }
      if (kids.isNotEmpty) childrenOf[entity.id] = kids;
    }
    for (final entity in live.values) {
      final parentId = entity.getComponent<jge.ParentComponent>()?.parentId;
      if (parentId == null || claimed.contains(entity.id)) continue;
      // Named a parent that never listed it — or one that is not here.
      if (!live.containsKey(parentId)) continue;
      (childrenOf[parentId] ??= []).add(entity);
      claimed.add(entity.id);
    }

    // A HUD is edited in the interface editor, not here: in the world's
    // tree a canvas is a leaf, and in the interface editor's tree the
    // canvases are the roots, wherever in the world they hang.
    final canvases = <jge.EntityId>{
      for (final entity in live.values)
        if (entity.getComponent<jge.UiCanvasComponent>() != null) entity.id,
    };
    if (contents == TreeContents.world) {
      for (final id in canvases) {
        childrenOf.remove(id);
      }
    }

    // The roots: what the editor's order says first, then anything else.
    final roots = <jge.Entity>[];
    if (contents == TreeContents.ui) {
      for (final id in rootOrder) {
        if (canvases.contains(id)) roots.add(live[id]!);
      }
      for (final entity in live.values) {
        if (!canvases.contains(entity.id)) continue;
        if (roots.any((r) => r.id == entity.id)) continue;
        roots.add(entity);
      }
    } else {
      for (final id in rootOrder) {
        final entity = live[id];
        if (entity == null || claimed.contains(id)) continue;
        roots.add(entity);
      }
      for (final entity in live.values) {
        if (claimed.contains(entity.id)) continue;
        if (roots.any((r) => r.id == entity.id)) continue;
        roots.add(entity);
      }
    }

    final filtering = !filter.isEmpty;
    // A map's layers answer only to the words searched for.
    final itemsFiltered =
        filtering &&
        filter.componentType.isEmpty &&
        filter.tag.isEmpty &&
        filter.layer.isEmpty &&
        !filter.problems;
    final words = filter.text.trim().toLowerCase();
    bool layerNamed(jge.MapLayerData l) =>
        itemsFiltered &&
        words.isNotEmpty &&
        l.name.toLowerCase().contains(words);
    final matches = <jge.EntityId>{};
    if (filtering) {
      for (final entity in live.values) {
        if (filter.matches(entity, withProblems: withProblems)) {
          matches.add(entity.id);
        } else if (mapOf?.call(entity)?.layers.any(layerNamed) ?? false) {
          matches.add(entity.id);
        }
      }
      // A match is no use without the parents that show where it lives.
      for (final id in Set.of(matches)) {
        var entity = live[id];
        while (entity != null) {
          final parentId = entity.getComponent<jge.ParentComponent>()?.parentId;
          if (parentId == null) break;
          if (!matches.add(parentId)) break;
          entity = live[parentId];
        }
      }
    }

    final rows = <TreeRow>[];
    void walk(jge.Entity entity, int depth, bool runtime) {
      if (filtering && !matches.contains(entity.id)) return;
      final kids = childrenOf[entity.id] ?? const <jge.Entity>[];
      final shown = filtering
          ? [
              for (final child in kids)
                if (matches.contains(child.id)) child,
            ]
          : kids;
      // A map's layers, front first, as the Layers panel lists them, each
      // with what is on it — and under a search, only those holding what
      // was searched for, or named by it.
      final map = mapOf?.call(entity);
      final layerIds = {
        for (final l in map?.layers ?? const <jge.MapLayerData>[]) l.id,
      };
      int? layerOf(jge.Entity child) =>
          child.getComponent<jge.LayerComponent>()?.mapLayer;
      List<jge.Entity> onLayer(int id) => [
        for (final child in shown)
          if (layerOf(child) == id) child,
      ];
      final loose = map == null
          ? shown
          : [
              for (final child in shown)
                if (!layerIds.contains(layerOf(child))) child,
            ];
      final layers = [
        for (final layer
            in (map?.layers ?? const <jge.MapLayerData>[]).reversed)
          if (!filtering || onLayer(layer.id).isNotEmpty || layerNamed(layer))
            layer,
      ];
      // Under a filter everything is open: a match hidden inside a shut
      // parent is a search that found nothing as far as anyone can see.
      final isExpanded = filtering || expanded.contains(entity.id);
      rows.add(
        TreeRow(
          entity: entity,
          depth: depth,
          hasChildren: shown.isNotEmpty || layers.isNotEmpty,
          isExpanded: isExpanded,
          isMatch:
              !filtering || filter.matches(entity, withProblems: withProblems),
          isRuntime: runtime,
        ),
      );
      if (!isExpanded) return;
      for (final layer in layers) {
        final members = onLayer(layer.id);
        final open =
            filtering || expandedLayers.contains((entity.id, layer.id));
        rows.add(
          TreeRow(
            entity: entity,
            depth: depth + 1,
            hasChildren: members.isNotEmpty,
            isExpanded: open,
            isMatch: !filtering || layerNamed(layer),
            isRuntime: runtime,
            item: MapLayerTreeItem(layer.id),
          ),
        );
        if (!open) continue;
        for (final member in members) {
          walk(member, depth + 2, runtime);
        }
      }
      // The map's children on none of its layers, after them.
      for (final child in loose) {
        walk(child, depth + 1, runtime);
      }
    }

    final authoredIds = authored;
    bool isRuntime(jge.Entity entity) =>
        authoredIds != null && !authoredIds.contains(entity.id);

    for (final root in roots) {
      if (isRuntime(root)) continue;
      walk(root, 0, false);
    }

    int? runtimeAt;
    final spawned = [
      for (final root in roots)
        if (isRuntime(root)) root,
    ];
    if (spawned.isNotEmpty) {
      runtimeAt = rows.length;
      for (final root in spawned) {
        walk(root, 0, true);
      }
    }

    return SceneTree(rows: rows, runtimeAt: runtimeAt);
  }
}

/// Which tree this is: the world's, or the interface editor's.
///
/// One model builds both. The world's tree stops at a UI canvas — what is
/// inside a HUD is the interface editor's business — and the interface
/// editor's tree starts there.
enum TreeContents { world, ui }
