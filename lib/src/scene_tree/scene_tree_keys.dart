part of 'scene_tree_panel.dart';

/// The scene tree's keys, and renaming a row.
extension _SceneTreeKeys on _SceneTreePanelState {
  // ── Renaming ─────────────────────────────────────────────────────────

  void _startRename(jge.Entity entity) {
    _tree.renameError.value = null;
    _tree.renaming.value = entity.id;
  }

  void _cancelRename() {
    _tree.renameError.value = null;
    _tree.renaming.value = null;
  }

  void _commitRename(jge.Entity entity, String name) {
    if (widget.entities.renameEntity(entity, name)) {
      _cancelRename();
      return;
    }
    // Left open, saying why: a name silently refused is a name the author
    // thinks they changed.
    _tree.renameError.value = name.trim().isEmpty
        ? 'It needs a name'
        : 'Something else is already called that';
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_tree.renaming.value != null) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final tree = _tree.rows;
    final selected = _sceneState.selectedEntity.value;
    final index = selected == null ? -1 : tree.indexOf(selected.id);
    final alt = HardwareKeyboard.instance.isAltPressed;
    final control = EditorKeys.primaryPressed;

    // Selects the row at [at], or the first that can be selected from it
    // going [step] (1 down, -1 up): past a level map's layer rows and what
    // is out of reach, the keys walk the entities that can be selected.
    // The way is the key's, not worked out from the row selected now:
    // Home searches down from the top, End up from the bottom.
    void moveTo(int at, {required int step}) {
      if (at < 0 || at >= tree.length) return;
      while (at >= 0 &&
          at < tree.length &&
          (tree.rows[at].isMapItem ||
              !_sceneState.canSelect(tree.rows[at].entity))) {
        at += step;
      }
      if (at < 0 || at >= tree.length) return;
      _sceneState
        ..clearMultiSelection()
        ..selectEntity(tree.rows[at].entity);
      _tree.scrollToIndex(at);
    }

    switch (key) {
      case LogicalKeyboardKey.arrowDown:
        if (alt && selected != null) {
          widget.entities.nudgeOrder(selected, up: false);
        } else {
          moveTo(index < 0 ? 0 : index + 1, step: 1);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (alt && selected != null) {
          widget.entities.nudgeOrder(selected, up: true);
        } else {
          moveTo(index < 0 ? tree.length - 1 : index - 1, step: -1);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (index < 0) return KeyEventResult.handled;
        final row = tree.rows[index];
        if (row.hasChildren && !row.isExpanded) {
          _tree.expand(row.id);
        } else if (row.hasChildren) {
          moveTo(index + 1, step: 1);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        if (index < 0) return KeyEventResult.handled;
        final row = tree.rows[index];
        if (row.hasChildren && row.isExpanded) {
          _tree.collapse(row.id);
        } else {
          // Up to the parent, which is the row above at one less depth.
          for (var i = index - 1; i >= 0; i--) {
            if (tree.rows[i].depth < row.depth) {
              moveTo(i, step: -1);
              break;
            }
          }
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        moveTo(0, step: 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        moveTo(tree.length - 1, step: -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f2:
      case LogicalKeyboardKey.enter:
        if (selected != null) _startRename(selected);
        return KeyEventResult.handled;
      case _ when EditorKeys.isDeleteKey(key):
        widget.entities.deleteSelection(widget.scope.history);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _sceneState.clearSelection();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyD when control:
        widget.entities.duplicateSelection(
          widget.scope.history,
          gridSize: _sceneState.gridSize.value,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyG when control:
        if (HardwareKeyboard.instance.isShiftPressed) {
          // Only a group comes apart: an entity of its own that happens to
          // hold others (a player and its weapon) is not one.
          if (selected != null && widget.entities.isGroup(selected)) {
            widget.entities.ungroup(selected);
          }
        } else {
          widget.entities.groupSelection();
        }
        return KeyEventResult.handled;
    }

    // Anything else printable jumps to the next row starting with it.
    final character = event.character;
    if (!control &&
        character != null &&
        character.length == 1 &&
        character.trim().isNotEmpty) {
      final id = _tree.jumpTo(character, now: DateTime.now());
      if (id != null) moveTo(tree.indexOf(id), step: 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
