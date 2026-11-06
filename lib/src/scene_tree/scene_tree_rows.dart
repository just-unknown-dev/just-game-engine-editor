part of 'scene_tree_panel.dart';

/// The scene tree's rows, built only when what they show changed.
extension _SceneTreeRows on _SceneTreePanelState {
  /// What the rows show of the scene, as one number: cheap next to
  /// building them.
  int _shapeOf() {
    var shape = Object.hashAll(_sceneState.rootOrder(_world));
    for (final e in _world.entities) {
      if (!e.isAlive) continue;
      final layer = e.getComponent<jge.LayerComponent>();
      shape = Object.hash(
        shape,
        e.id,
        e.name,
        e.isActive,
        e.getComponent<jge.ParentComponent>()?.parentId,
        Object.hashAll(
          e.getComponent<jge.ChildrenComponent>()?.childIds ?? const [],
        ),
        Object.hashAll([for (final c in e.components) c.runtimeType]),
        layer?.layerId,
        layer?.layer,
        Object.hashAllUnordered(e.tags),
      );
    }
    return shape;
  }

  /// After a scene revision: the shape looked at now when entities came
  /// or went (or were switched on or off, or gained or lost a component),
  /// or after a still moment; otherwise once the cooling is over.
  void _followRows() {
    final entities = _world.queryVersion(const []);
    if (entities != _entitiesSeen || _shapeCooling == null) {
      _checkShape();
    } else {
      _shapeOwed = true;
    }
    _rowsLater?.cancel();
    _rowsLater = Timer(_SceneTreePanelState._problemsQuiet, () {
      _rowsLater = null;
      if (mounted) _rowsTick.value = _rowsTick.value + 1;
    });
  }

  /// Works out what the rows show, and when it changed builds them again
  /// and gathers the chips; cools for [_SceneTreePanelState._shapeEvery].
  void _checkShape() {
    if (!mounted) return;
    _shapeOwed = false;
    _entitiesSeen = _world.queryVersion(const []);
    _shapeCooling?.cancel();
    _shapeCooling = Timer(_SceneTreePanelState._shapeEvery, () {
      _shapeCooling = null;
      if (mounted && _shapeOwed) _checkShape();
    });
    final shape = _shapeOf();
    if (shape == _shapeSeen) return;
    _shapeSeen = shape;
    _rowsTick.value = _rowsTick.value + 1;
    // The chips list what the scene has — kinds, layers, tags — which is
    // what the shape is made of.
    _chipsSoon();
  }

  void _gatherChips() {
    _chipsOwed = false;
    _chipsTick.value = _chipsTick.value + 1;
    _chipsCooling?.cancel();
    _chipsCooling = Timer(_SceneTreePanelState._chipsEvery, () {
      _chipsCooling = null;
      if (mounted && _chipsOwed) _gatherChips();
    });
  }

  Widget _rowList(
    SceneTree tree,
    Map<int, int> Function(jge.Entity map) countsOn,
  ) {
    return DragTarget<List<jge.Entity>>(
      // Dropped past the last row: out of everything, to the top level —
      // but not while the Level Designer keeps to its Level Map: the top
      // level is outside it.
      onWillAcceptWithDetails: (_) => _reaches(null),
      onAcceptWithDetails: (details) {
        if (_dragOver != null) return;
        widget.entities.reparentAll(details.data, null);
      },
      builder: (context, candidates, _) => Stack(
        children: [
          Positioned.fill(
            child: EditorScrollbar(
              controller: _tree.scroll,
              builder: (_, _) => ListView.builder(
                key: _listKey,
                controller: _tree.scroll,
                padding: EdgeInsets.zero,
                itemCount: tree.length,
                itemExtent: kSceneTreeRowTileHeight,
                itemBuilder: (context, index) => _row(tree, index, countsOn),
              ),
            ),
          ),
          // A drag let go of below the last row moves to the top level.
          // It always did; nothing said so, and nothing showed it was
          // about to happen.
          if (candidates.isNotEmpty && _dragOver == null)
            Positioned(
              left: 0,
              right: 0,
              top: tree.length * kSceneTreeRowTileHeight,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: EditorTheme.dragOverBg,
                    border: Border.all(color: EditorTheme.primaryBright),
                  ),
                  child: Text(
                    'Move to the top level',
                    style: TextStyle(
                      color: EditorTheme.primaryBright,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _cancelPendingRename() {
    _renameAfterDoubleClick?.cancel();
    _renameAfterDoubleClick = null;
    _renamePendingFor = null;
  }

  void _onRowPointerUp(
    PointerUpEvent event,
    jge.Entity entity,
    SceneTree tree,
  ) {
    if (_pressedOn != entity.id || !_pressedPrimary) return;
    _pressedOn = null;
    _rowTookIt = true;
    // Out of reach: not selected, renamed or focused. Nor is the click
    // one on empty space — the selection stays as it was.
    if (!_sceneState.canSelect(entity)) return;
    // A drag that happens to end here is not a click.
    // Only a press that wandered right off the row is not a click.
    // Dragging takes a deliberate hold now, so nothing else here needs
    // to second-guess what the pointer was doing: a click that moved a
    // little is still a click, and used to be thrown away as a drag.
    if ((event.position - _pressedAt).distance > kSceneTreeRowTileHeight * 2) {
      return;
    }
    // A click anywhere else takes the name being typed: pulling the
    // focus off the box is what commits it. The click then goes on to
    // mean what it would have meant anyway.
    final wasSelected = _sceneState.selectedEntity.value?.id == entity.id;
    // A click on another row: a rename armed for the last one is not for
    // this one.
    if (_renamePendingFor != entity.id) _cancelPendingRename();
    if (_tree.renaming.value != null) {
      _keys.requestFocus();
      _clickedId = null;
      _clickedAt = event.timeStamp;
      _select(entity, tree, control: false, shift: false);
      return;
    }

    // Device time, not wall-clock: a test advances its own clock, and
    // `DateTime.now()` would not move with it.
    final sinceLast = event.timeStamp - _clickedAt;
    final twice =
        _clickedId == entity.id &&
        sinceLast < _SceneTreePanelState._doubleClick;
    _clickedId = entity.id;
    _clickedAt = event.timeStamp;

    if (twice) {
      // The second of a pair: focus, and take back the rename the first
      // one was about to start.
      _cancelPendingRename();
      widget.onFocusEntity?.call(entity);
      return;
    }

    // A click on a row that was *already* selected means rename — but
    // only once it is clear no second click is coming, or a double click
    // would rename and focus both. A row selected by making it, or from
    // the viewport, is selected without having been clicked, so it takes
    // a click of its own first.
    final plain =
        !EditorKeys.primaryPressed && !HardwareKeyboard.instance.isShiftPressed;
    if (wasSelected && plain) {
      _cancelPendingRename();
      _renamePendingFor = entity.id;
      _renameAfterDoubleClick = Timer(_SceneTreePanelState._doubleClick, () {
        _renameAfterDoubleClick = null;
        _renamePendingFor = null;
        // Still the one selected: the box opens on the row the keys act
        // on, never on one the selection has left.
        if (mounted && _sceneState.selectedEntity.value?.id == entity.id) {
          _startRename(entity);
        }
      });
      return;
    }
    _select(
      entity,
      tree,
      // Cmd+click on a Mac, where Ctrl+click is the context click.
      control: EditorKeys.primaryPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );
  }
}
