part of 'scene_tree_panel.dart';

/// Selecting in the scene tree, and dropping rows onto others.
extension _SceneTreeDragDrop on _SceneTreePanelState {
  // ── Selecting ────────────────────────────────────────────────────────

  void _select(
    jge.Entity entity,
    SceneTree tree, {
    required bool control,
    required bool shift,
  }) {
    _keys.requestFocus();
    if (control) {
      _sceneState.toggleMultiSelect(entity);
      return;
    }
    if (shift) {
      final anchor = _sceneState.selectedEntity.value;
      if (anchor != null) {
        // Over what is on screen, which is what "between these two" means
        // to whoever is looking at it.
        final from = tree.indexOf(anchor.id);
        final to = tree.indexOf(entity.id);
        if (from >= 0 && to >= 0) {
          final lo = from < to ? from : to;
          final hi = from < to ? to : from;
          _sceneState.selectRange([
            for (var i = lo; i <= hi; i++) tree.rows[i].entity,
          ], anchor: anchor);
          return;
        }
      }
    }
    _sceneState
      ..clearMultiSelection()
      ..selectEntity(entity);
  }

  /// What a drag from [entity] carries: the selection when it is part of
  /// it, otherwise just itself.
  List<jge.Entity> _dragSelection(jge.Entity entity) {
    final selection = widget.entities.selectionEntities;
    return selection.any((e) => e.id == entity.id) ? selection : [entity];
  }

  // ── Dropping ─────────────────────────────────────────────────────────

  /// What a drop means, as one undoable step.
  ///
  /// Dropping *into* and dropping *between* are the same move with a
  /// different destination, so both go through one command: a drag that
  /// moved three things undoes as one drag.
  /// Whether this row could take [dragged] at all, wherever on it the
  /// pointer happens to be.
  bool _canAccept(List<jge.Entity> dragged, jge.Entity onto) =>
      !dragged.any((e) => e.id == onto.id) && _sceneState.canSelect(onto);

  /// What a drop at [zone] on [onto] actually means.
  ///
  /// Beside something whose parent is out of reach would take what is
  /// dropped out of reach too — beside the Level Map, while designing, is
  /// the top level, outside it — so there the edges mean into it.
  DropZone _zoneFor(jge.Entity onto, DropZone zone) {
    if (zone != DropZone.onto && !_reaches(_parentOf(onto))) {
      return DropZone.onto;
    }
    return zone;
  }

  jge.Entity? _parentOf(jge.Entity entity) {
    final id = entity.getComponent<jge.ParentComponent>()?.parentId;
    return id == null ? null : _world.getEntity(id);
  }

  /// Whether what is put under [parent] — or at the top level, for none —
  /// is still within reach.
  bool _reaches(jge.Entity? parent) => parent == null
      ? _sceneState.selectable.value == null
      : _sceneState.canSelect(parent);

  /// Whether [dragged] may land on [onto] the way the pointer is over it.
  bool _canDrop(List<jge.Entity> dragged, jge.Entity onto, DropZone zone) =>
      _canAccept(dragged, onto) && _zoneFor(onto, zone) == zone;

  void _drop(List<jge.Entity> dragged, jge.Entity onto, DropZone zone) {
    if (!_canDrop(dragged, onto, zone)) return;
    if (zone == DropZone.onto) {
      widget.entities.reparentAll(dragged, onto);
      _tree.expand(onto.id);
      return;
    }

    final parentId = onto.getComponent<jge.ParentComponent>()?.parentId;
    final parent = parentId == null ? null : _world.getEntity(parentId);
    final siblings = parent == null
        ? _sceneState.rootOrder(_world)
        : parent.getComponent<jge.ChildrenComponent>()?.childIds ??
              const <jge.EntityId>[];
    // Beside something on a map layer is on that layer too.
    final mapLayer = parent?.hasComponent<jge.LevelMapComponent>() ?? false
        ? onto.getComponent<jge.LayerComponent>()?.mapLayer
        : null;
    var at = siblings.indexOf(onto.id);
    if (at < 0) {
      widget.entities.reparentAll(dragged, parent, mapLayer: mapLayer);
      return;
    }
    if (zone == DropZone.below) at++;
    // Anything already above the line leaves a gap behind it when it
    // moves, so the line itself shifts up by that many.
    final above = dragged.where((e) {
      final index = siblings.indexOf(e.id);
      return index >= 0 && index < at;
    }).length;
    widget.entities.reparentAll(
      dragged,
      parent,
      index: at - above,
      mapLayer: mapLayer,
    );
  }

  /// The swatches, and the way back to no mark at all.
  Future<void> _pickColor(
    BuildContext context,
    jge.Entity entity,
    Offset at,
  ) async {
    final chosen = await showEditorMenu<int>(context, at, [
      for (var i = 0; i < SceneTreeController.swatches.length; i++)
        editorMenuItem(
          i,
          _SceneTreePanelState._colorNames[i],
          icon: Icons.square_rounded,
          iconColor: SceneTreeController.swatches[i],
        ),
      editorMenuDivider(),
      editorMenuItem(-1, 'No colour', icon: Icons.format_color_reset),
    ]);
    if (chosen == null) return;
    for (final e in _dragSelection(entity)) {
      _tree.setColor(e.id, chosen < 0 ? null : chosen);
    }
  }

  /// `12 entities`, or what is picked when more than one thing is.
  ///
  /// Counted from the world rather than from the rows, which are a frame
  /// behind at this point in the build — except under a filter, where
  /// what is shown is the interesting number.
  String _countLabel() {
    final picked = _sceneState.multiSelectedIds.value.length;
    if (picked > 1) return '$picked selected';
    final count = _tree.filter.value.isEmpty
        ? _world.entities.where((e) => e.isAlive).length
        : _tree.rows.length;
    return count == 1 ? '1 entity' : '$count entities';
  }
}
