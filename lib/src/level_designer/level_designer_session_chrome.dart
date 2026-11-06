part of 'level_designer_session.dart';

/// What the designer shows: visibility, the rulers and minimap.
extension LevelDesignerSessionChrome on LevelDesignerSession {
  // ── Visibility ────────────────────────────────────────────────────────────

  /// Hides the selection in the viewport (H). Editor-only.
  @internal
  void hideSelection() {
    final ids = [for (final e in selectionEntities()) e.id];
    if (ids.isEmpty) return;
    controller.setEntitiesHidden(ids, hidden: true);
    sceneState.clearSelection();
    controller.setStatus('Hidden ${ids.length} - Alt+H shows everything');
  }

  /// Hides everything except the selection (Shift+H), to work on it alone.
  ///
  /// What holds the selection stays shown, and what it holds: hiding an
  /// entity hides everything under it, so hiding the Level Map — or the
  /// group a thing is in — would hide the very thing being isolated.
  @internal
  void isolateSelection() {
    final keep = {for (final e in selectionEntities()) e.id};
    if (keep.isEmpty) return;
    controller.view.isolate(world, keep);
    controller.setStatus('Isolated ${keep.length} - Alt+H shows everything');
  }

  /// Shows every hidden entity (Alt+H).
  @internal
  void unhideAll() => controller.hiddenEntities.value = <jge.EntityId>{};

  /// Locks the selection against picking (L).
  @internal
  void lockSelection() {
    final ids = [for (final e in selectionEntities()) e.id];
    if (ids.isEmpty) return;
    controller.setEntitiesLocked(ids, locked: true);
    sceneState.clearSelection();
    controller.setStatus('Locked ${ids.length} - Alt+L unlocks everything');
  }

  /// Unlocks every locked entity (Alt+L).
  @internal
  void unlockAll() => controller.lockedEntities.value = <jge.EntityId>{};

  /// Selects everything that can be picked (Ctrl+A) — what is on the
  /// level's map, never the map itself, as a marquee does: it is under
  /// everything, and moving it moves all of it.
  @internal
  void selectAll() {
    final all = [
      for (final e in world.query([jge.TransformComponent]))
        if (e.isActive &&
            controller.isPickable(e) &&
            !Select2DTool.isWholeMap(world, e))
          e,
    ];
    sceneState.clearSelection();
    if (all.isNotEmpty) sceneState.selectRange(all, anchor: all.first);
  }

  /// Selects everything like what is selected (Shift+G): the same model,
  /// the same kind of shape, or the same name but its number.
  @internal
  void selectSimilar() {
    final picked = selectionEntities();
    if (picked.isEmpty) {
      controller.setStatus('Select something first');
      return;
    }
    final kinds = {for (final e in picked) _kindOf(e)};
    final like = [
      for (final e in world.query([jge.TransformComponent]))
        if (e.isActive &&
            controller.isPickable(e) &&
            kinds.contains(_kindOf(e)))
          e,
    ];
    sceneState.clearSelection();
    if (like.isNotEmpty) sceneState.selectRange(like, anchor: like.first);
    controller.setStatus('Selected ${like.length} like it');
  }

  /// What [entity] is like: its model, the kind of shape it is, else its
  /// name without the number on the end.
  String _kindOf(jge.Entity entity) {
    final model = entity.getComponent<g3.ModelComponent>()?.model;
    if (model != null && model.isNotEmpty) return 'model:$model';
    final shape = entity.getComponent<g3.Primitive3DComponent>();
    if (shape != null) return 'shape:${shape.shapeName}';
    final name = entity.name ?? '';
    return 'name:${name.replaceFirst(RegExp(r'[ _]?\d+$'), '')}';
  }

  /// Replaces the selection with the active prefab (Shift+R).
  @internal
  void replaceSelection() {
    final prefab = controller.activePrefab;
    final entities = selectionEntities();
    if (prefab == null || entities.isEmpty) return;
    if (prefab.instanceOf != null) {
      // A prefab file places an instance of itself; it builds nothing to
      // swap in, and an empty swap would only delete the selection.
      controller.setStatus(
        '${prefab.name} is a prefab file: place it with Draw (B), it '
        'cannot replace what is selected',
      );
      return;
    }
    ops.replaceWith(entities, prefab);
  }

  /// Whether an overlay (rulers, minimap, a module's) owns the pointer.
  @internal
  bool get hasChromeGesture => _chromeOverlay != null;

  OverlayPointerContext _chromeContext(
    Offset screen,
    Size canvasSize,
    double gridSize,
  ) => OverlayPointerContext(
    screen: screen,
    canvasSize: canvasSize,
    area: controller.visibleViewport(canvasSize),
    camera: camera,
    world: world,
    controller: controller,
    history: history,
    modifiers: _readModifiers(),
    gridSize: gridSize,
  );

  /// Offers a press to the interactive overlays, topmost first, before any
  /// tool sees it. Screen-space chrome sits on top of the level, so it gets
  /// first refusal.
  @internal
  bool onChromePointerDown(
    Offset screen,
    Size canvasSize, {
    double gridSize = 0,
  }) {
    final context = _chromeContext(screen, canvasSize, gridSize);
    for (final overlay in overlays.all.reversed) {
      if (overlay is! InteractiveOverlay) continue;
      if (!isOverlayDrawn(overlay)) continue;
      if (overlay.onPointerDown(context)) {
        _chromeOverlay = overlay;
        return true;
      }
    }
    return false;
  }

  /// Continues the overlay's drag.
  @internal
  void onChromePointerMove(Offset screen, Size canvasSize, double gridSize) =>
      _chromeOverlay?.onPointerMove(
        _chromeContext(screen, canvasSize, gridSize),
      );

  /// Ends the overlay's drag.
  @internal
  void onChromePointerUp(
    Offset screen,
    Size canvasSize, {
    double gridSize = 0,
  }) {
    _chromeOverlay?.onPointerUp(_chromeContext(screen, canvasSize, gridSize));
    _chromeOverlay = null;
  }

  /// The designer in use, ruler guides and camera bookmarks, for the scene
  /// file's `editor` section. Authoring aids, not level content: the game never reads them.
  @internal
  Map<String, dynamic> editorData() => {
    'designer': ?scope.activeDesigner.value,
    'guides': [
      for (final g in controller.guides.value)
        {'vertical': g.isVertical, 'position': g.position},
    ],
    'bookmarks': {
      for (final entry in _bookmarks.entries)
        '${entry.key}': entry.value.toJson(),
    },
    if (_bookmarks3D.isNotEmpty)
      'bookmarks3d': {
        for (final entry in _bookmarks3D.entries)
          '${entry.key}': entry.value.toJson(),
      },
    'modules': {
      for (final module in scope.modules.all)
        module.id: ?module.saveEditorData(this),
    },
  };

  /// Restores what [editorData] saved. Tolerates a missing or partial section
  /// — every scene saved before this existed has none.
  @internal
  void restoreEditorData(Map<String, dynamic>? data) {
    // The designer the level was authored in, first: what follows is
    // restored into it.
    final designer = data?['designer'];
    scope.selectDesigner(designer is String ? designer : null);
    _bookmarks.clear();
    _bookmarks3D.clear();
    final byModule = data?['modules'];
    for (final module in scope.modules.all) {
      final saved = byModule is Map ? byModule[module.id] : null;
      if (saved is Map) {
        module.restoreEditorData(this, saved.cast<String, Object?>());
      }
    }
    final guides = <DesignerGuide>[];
    if (data != null) {
      final savedGuides = data['guides'];
      final guideList = savedGuides is List ? savedGuides : const [];
      for (final g in guideList.whereType<Map>()) {
        final position = g['position'];
        if (position is! num) continue;
        guides.add(
          DesignerGuide(
            isVertical: g['vertical'] == true,
            position: position.toDouble(),
          ),
        );
      }
      final saved3D = data['bookmarks3d'];
      if (saved3D is Map) {
        for (final entry in saved3D.entries) {
          final slot = int.tryParse('${entry.key}');
          final value = entry.value;
          if (slot == null || value is! Map) continue;
          try {
            _bookmarks3D[slot] = View3DPose.fromJson(
              value.cast<String, dynamic>(),
            );
          } on Object {
            // A malformed bookmark is not worth failing a scene load over.
          }
        }
      }
      final saved = data['bookmarks'];
      if (saved is Map) {
        for (final entry in saved.entries) {
          final slot = int.tryParse('${entry.key}');
          final value = entry.value;
          if (slot == null || value is! Map) continue;
          try {
            _bookmarks[slot] = _CameraBookmark.fromJson(
              value.cast<String, dynamic>(),
            );
          } on Object {
            // A malformed bookmark is not worth failing a scene load over.
          }
        }
      }
    }
    controller.guides.value = guides;
  }
}
