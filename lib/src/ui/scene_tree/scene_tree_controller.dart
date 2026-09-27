/// What the scene tree is showing and doing: what is open, what is being
/// searched for, and where the list is scrolled to.
///
/// Apart from the widget so that revealing a row, expanding a subtree or
/// remembering what was open across a reload can be read and tested
/// without pumping a panel.
library;

import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'scene_tree_model.dart';

/// How tall one row is. The list is built by index, so it has to be told.
const double kSceneTreeRowHeight = 26;

class SceneTreeController {
  SceneTreeController({required this.world});

  final jge.World Function() world;

  /// Which rows are open, by entity.
  final Signal<Set<jge.EntityId>> expanded = Signal(
    <jge.EntityId>{},
    debugLabel: 'treeExpanded',
  );

  /// What the tree is narrowed to.
  /// The map layers that are open, by map and layer: what is on them
  /// listed.
  final Signal<Set<(jge.EntityId, int)>> expandedLayers = Signal(
    <(jge.EntityId, int)>{},
    debugLabel: 'treeExpandedLayers',
  );

  /// The map layer row clicked last, as (map, layer id), drawn selected
  /// the way an entity row is — until an entity is selected or the empty
  /// part of the tree is clicked. The layer being painted is the
  /// designer's, and outlasts it.
  final Signal<(jge.EntityId, int)?> pickedLayer = Signal(
    null,
    debugLabel: 'treePickedLayer',
  );

  final Signal<TreeFilter> filter = Signal(
    TreeFilter.none,
    debugLabel: 'treeFilter',
  );

  /// The entity being renamed in place, if any.
  final Signal<jge.EntityId?> renaming = Signal(
    null,
    debugLabel: 'treeRenaming',
  );

  /// Why a rename was refused, shown under the box.
  final Signal<String?> renameError = Signal(
    null,
    debugLabel: 'treeRenameError',
  );

  final ScrollController scroll = ScrollController();

  /// What the list was last built as, so the keyboard knows what is above
  /// and below a row without rebuilding it.
  SceneTree rows = SceneTree.empty;

  void dispose() {
    expanded.dispose();
    expandedLayers.dispose();
    pickedLayer.dispose();
    colors.dispose();
    filter.dispose();
    renaming.dispose();
    renameError.dispose();
    scroll.dispose();
  }

  // ── Opening and shutting ─────────────────────────────────────────────

  bool isExpanded(jge.EntityId id) => expanded.value.contains(id);

  void toggle(jge.EntityId id) => isExpanded(id) ? collapse(id) : expand(id);

  void expand(jge.EntityId id) => expanded.value = {...expanded.value, id};

  void collapse(jge.EntityId id) =>
      expanded.value = {...expanded.value}..remove(id);

  /// Opens [id] and everything under it — what Alt-clicking a chevron
  /// means everywhere else.
  void expandSubtree(jge.EntityId id) {
    final next = {...expanded.value};
    void walk(jge.EntityId at) {
      next.add(at);
      final children = world()
          .getEntity(at)
          ?.getComponent<jge.ChildrenComponent>();
      for (final child in children?.childIds ?? const <jge.EntityId>[]) {
        walk(child);
      }
    }

    walk(id);
    expanded.value = next;
  }

  void collapseAll() {
    expanded.value = <jge.EntityId>{};
    expandedLayers.value = <(jge.EntityId, int)>{};
  }

  /// Opens or shuts [layerId] of the map on [mapId].
  void toggleLayer(jge.EntityId mapId, int layerId) {
    final key = (mapId, layerId);
    final next = {...expandedLayers.value};
    if (!next.remove(key)) next.add(key);
    expandedLayers.value = next;
  }

  void expandAll() {
    expanded.value = {
      for (final entity in world().entities)
        if (entity.getComponent<jge.ChildrenComponent>()?.childIds.isNotEmpty ??
            false)
          entity.id,
    };
  }

  /// Opens everything above [id] so the row is on screen, and scrolls to
  /// it.
  ///
  /// Called whenever the selection changes anywhere — the viewport, the UI
  /// mode, the Problems dock — because a tree that does not follow the
  /// selection makes the reader hunt for what they just clicked.
  void reveal(jge.EntityId id) {
    final next = {...expanded.value};
    final layers = {...expandedLayers.value};
    var entity = world().getEntity(id);
    var guard = 0;
    while (entity != null && guard++ < 64) {
      final parentId = entity.getComponent<jge.ParentComponent>()?.parentId;
      if (parentId == null) break;
      next.add(parentId);
      // On a layer of a map: that layer's row is opened too.
      final onLayer = entity.getComponent<jge.LayerComponent>()?.mapLayer;
      if (onLayer != null) layers.add((parentId, onLayer));
      entity = world().getEntity(parentId);
    }
    if (next.length != expanded.value.length) expanded.value = next;
    if (layers.length != expandedLayers.value.length) {
      expandedLayers.value = layers;
    }
    _scrollTo = id;
  }

  /// Opens [layerId] of the map on [mapId], and the map.
  void expandLayer(jge.EntityId mapId, int layerId) {
    if (!expanded.value.contains(mapId)) expand(mapId);
    final key = (mapId, layerId);
    if (!expandedLayers.value.contains(key)) {
      expandedLayers.value = {...expandedLayers.value, key};
    }
  }

  /// The row a scroll is owed to, taken once the list has been built with
  /// it in.
  jge.EntityId? takeScrollTarget() {
    final target = _scrollTo;
    _scrollTo = null;
    return target;
  }

  jge.EntityId? _scrollTo;

  /// Brings the row at [index] into view, if it is not already.
  void scrollToIndex(int index) {
    if (!scroll.hasClients || index < 0) return;
    final position = scroll.position;
    final top = index * kSceneTreeRowHeight;
    final bottom = top + kSceneTreeRowHeight;
    if (top < position.pixels) {
      position.jumpTo(top.clamp(0.0, position.maxScrollExtent));
    } else if (bottom > position.pixels + position.viewportDimension) {
      position.jumpTo(
        (bottom - position.viewportDimension).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  // ── Type to jump ─────────────────────────────────────────────────────

  String _typed = '';
  DateTime _typedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// The row a letter jumps to, or null.
  ///
  /// Letters typed close together build a word, as a file list does;
  /// leaving off for a moment starts again.
  jge.EntityId? jumpTo(String letter, {required DateTime now}) {
    if (now.difference(_typedAt).inMilliseconds > 900) _typed = '';
    _typedAt = now;
    _typed += letter.toLowerCase();
    for (final row in rows.rows) {
      final name = (row.entity.name ?? '').toLowerCase();
      if (name.startsWith(_typed)) return row.id;
    }
    // Nothing starts with the whole word: take the last letter as a fresh
    // start rather than doing nothing.
    if (_typed.length > 1) {
      _typed = letter.toLowerCase();
      for (final row in rows.rows) {
        if ((row.entity.name ?? '').toLowerCase().startsWith(_typed)) {
          return row.id;
        }
      }
    }
    return null;
  }

  // ── Colour labels ────────────────────────────────────────────────────

  /// The swatches a row can be marked with. Eight, so the menu is one
  /// glance, and fixed, so a level's colours mean the same thing in
  /// every scene of it.
  static const List<Color> swatches = [
    Color(0xFFE05A5A),
    Color(0xFFE08A3C),
    Color(0xFFE0C63C),
    Color(0xFF6BC46B),
    Color(0xFF4FB3C4),
    Color(0xFF5A7FE0),
    Color(0xFFA96BD8),
    Color(0xFF9E9E9E),
  ];

  /// Which rows are marked, and with which swatch.
  final Signal<Map<jge.EntityId, int>> colors = Signal(
    <jge.EntityId, int>{},
    debugLabel: 'treeColors',
  );

  Color? colorOf(jge.EntityId id) {
    final index = colors.value[id];
    return index == null || index < 0 || index >= swatches.length
        ? null
        : swatches[index];
  }

  /// Marks [id] with [index], or clears it when [index] is null.
  void setColor(jge.EntityId id, int? index) {
    final next = {...colors.value};
    if (index == null) {
      next.remove(id);
    } else {
      next[id] = index;
    }
    colors.value = next;
  }

  // ── Saved with the scene ─────────────────────────────────────────────

  /// What to write into the scene's `editor` section: which rows were
  /// open, by name, because ids are handed out again on the next load.
  Map<String, Object?> toEditorData() => {
    'expanded': [for (final id in expanded.value) ?world().getEntity(id)?.name],
    'colors': {
      for (final entry in colors.value.entries)
        ?world().getEntity(entry.key)?.name: entry.value,
    },
  };

  /// Restores what [toEditorData] saved.
  void restoreEditorData(Map<String, Object?>? data) {
    final marked = data?['colors'];
    if (marked is Map) {
      colors.value = {
        for (final entity in world().entities)
          if (entity.name != null && marked['${entity.name}'] is int)
            entity.id: marked['${entity.name}'] as int,
      };
    }
    final names = data?['expanded'];
    if (names is! List) return;
    final wanted = {for (final name in names) '$name'};
    expanded.value = {
      for (final entity in world().entities)
        if (entity.name != null && wanted.contains(entity.name)) entity.id,
    };
  }
}
