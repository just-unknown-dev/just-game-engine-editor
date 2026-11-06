part of 'just_game_editor_plugin.dart';

/// The Level Designer in the editor: opening and closing it, the gizmos
/// and transform modes it shows, the grid, and what is drawn while it is
/// open.
extension PluginDesigner on JustGameEditorPlugin {
  /// Changes the grid size from the Level Designer.
  ///
  /// Writes through to [sceneState], the plugin's own copy and the saved
  /// settings, so the designer's control and the settings dialog never
  /// disagree about what the grid is — and the next settings change does not
  /// put the old size back.
  @internal
  void setGridSize(double size) {
    if (size <= 0 || size == gridSize.value) return;
    gridSize.value = size;
    sceneState.setGridSnapping(enabled: _gridSnappingEnabled, gridSize: size);
    final prefs = scope.prefs;
    if (prefs.settings.value.gridSize != size) {
      prefs.update(prefs.settings.value.copyWith(gridSize: size));
    }
  }

  /// Which mode's gizmos apply now: a play-test (running or paused), the
  /// Level Designer, or the editor; null with the editor closed. Each
  /// keeps its own ([gizmoSettings]).
  ///
  /// Worked out on each read, not a `Computed`: it reads the designer only
  /// outside a play-test, and a `Computed` reading one whose signals change
  /// like that keeps the old ones, so it stopped hearing the designer open.
  @internal
  GizmoMode? get gizmoMode {
    if (!isVisible.value) return null;
    if (!isAuthoring.value) return GizmoMode.play;
    return designer.value == null ? GizmoMode.editor : GizmoMode.designer;
  }

  /// Whether the mode now shows its gizmos at all: the Gizmos button.
  @internal
  bool get areGizmosVisible {
    final mode = gizmoMode;
    return mode != null && gizmoSettings.value.of(mode).shown;
  }

  /// Whether gizmos of [kind] are drawn now: markers, camera frames, what
  /// the modules draw over the level, the collider outlines, the
  /// selection's outline, the designer's aids — each as the mode now has
  /// it. The selection's handles, and what a tool in use draws, are not
  /// gizmos and stay.
  @internal
  bool showsGizmo(GizmoKind kind) {
    final mode = gizmoMode;
    return mode != null && gizmoSettings.value.of(mode).shows(kind);
  }

  /// Shows the mode's gizmos if hidden, hides them if shown; the other
  /// modes keep theirs.
  @internal
  void toggleGizmos() {
    final mode = gizmoMode;
    if (mode == null) return;
    scope.prefs.change((s) => s.copyWith(gizmos: s.gizmos.toggled(mode)));
  }

  /// Whether the Level Designer workspace is currently open.
  @internal
  bool get isLevelDesignerOpen => designer.value != null;

  // ── Move, Scale, Rotate ───────────────────────────────────────────────────

  /// What the Move, Scale and Rotate toolbar can act on now. Nothing
  /// during a play-test. With Select tiles in hand, the tiles it has
  /// selected; otherwise what is selected — in the designer all of it, in
  /// the editor the one entity its gizmo is on.
  @internal
  Set<TransformMode> get transformModesAvailable {
    if (!isAuthoring.value) return TransformModes.none;
    final session = designer.value;
    if (session != null) {
      if (session.controller.toolId.value == TileTools.select) {
        return scope.tiles.selection.value.isEmpty
            ? TransformModes.none
            : TransformModes.tiles;
      }
      return TransformModes.forEntities(
        engine.world,
        session.selectionEntities(),
      );
    }
    // A piece of a map turns its tiles, which only the designer does.
    final selected = sceneState.selectedEntity.value;
    return selected == null
        ? TransformModes.none
        : TransformModes.forEntities(engine.world, [
            selected,
          ], turnsPieces: false);
  }

  /// Whether the gizmos are in hand: always in the editor; in the designer
  /// with the select tool — which All, Move, Scale and Rotate are — or with
  /// Select tiles and tiles selected.
  @internal
  bool get isTransformToolInHand {
    final session = designer.value;
    if (session == null) return true;
    final tool = session.controller.toolId.value;
    return tool == BuiltInTools.select ||
        (tool == TileTools.select && scope.tiles.selection.value.isNotEmpty);
  }

  /// The gizmo the selection shows: the mode chosen when it can take it,
  /// else Move; null when nothing selected can take any.
  @internal
  TransformMode? get shownTransformMode => TransformModes.shown(
    scope.view.transformMode.value,
    transformModesAvailable,
  );

  /// Picks Move, Scale or Rotate — the toolbar's buttons, W, E and R. In
  /// the designer the select tool comes with it, whose gizmos they are.
  @internal
  void chooseTransformMode(TransformMode mode) {
    scope.view.transformMode.value = mode;
    if (isAuthoring.value) designer.value?.adoptTransformMode();
  }

  /// Opens the Level Designer, creating its session if needed.
  @internal
  void openLevelDesigner() {
    if (designer.value != null || !sceneState.hasScene) return;
    designer.value = LevelDesignerSession(
      scope: scope,
      uniqueName: entities.uniqueName.call,
      camera: () => scope.editorView,
      splitViews: () => splitViews,
      onDuplicate: duplicateSelection,
      onDelete: deleteSelection,
      onArray: (count, step) => arraySelection(count: count, step: step),
      onArray3D: arraySelection3D,
      showsGizmo: showsGizmo,
    )..restoreEditorData(sceneIO.editorData);
    // Its panel is a tab of the right panel: the one to see on opening.
    scope.chrome.rightPanelTab.value = EditorChromeState.levelTab;
    _updateRenderFilter();
  }

  /// Hides what the editor has hidden — the eye in the scene tree, and
  /// the designer's layers and isolated selection — without touching the
  /// entities. Only while authoring: a play-test shows the level as it
  /// ships.
  ///
  /// The eye used to work only with the Level Designer open, because
  /// this filter was installed only then; everywhere else the engine
  /// drew the world and knew nothing of it.
  void _updateRenderFilter() {
    // The engine may already be gone: an app closing disposes it first.
    if (!engine.isInitialized) return;
    final render = engine.world.getSystem<RenderSystem>();
    if (render == null) return;
    render.shouldRender = _isDrawn;
  }

  /// Whether [entity]'s gizmos (its marker, camera frame, collider outline,
  /// what a module draws for it) may be drawn: as [_isDrawn], but in the
  /// Level Designer what is off the Level Map too. Out of reach and out of
  /// sight while designing, its gizmos still show once the designer's are
  /// asked for, which is what the Gizmos button there is for.
  bool _gizmosShownFor(Entity entity) {
    if (!isAuthoring.value) return true;
    final session = designer.value;
    return session == null
        ? !scope.view.isHiddenIn(entity)
        : session.controller.showsGizmosOf(entity);
  }

  /// Closes the Level Designer and releases its state.
  ///
  /// History is dropped rather than retained: its commands hold references to
  /// entities in this scene, and replaying one after a scene change would
  /// write into destroyed entities.
  @internal
  void closeLevelDesigner() {
    final session = designer.value;
    if (session == null) return;
    sceneIO.editorData = session.editorData();
    designer.value = null;
    scope.chrome.rightPanelTab.value = EditorChromeState.inspectorTab;
    _updateRenderFilter();
    session.dispose();
  }

  /// Toggles the Level Designer workspace.
  @internal
  void toggleLevelDesigner() =>
      isLevelDesignerOpen ? closeLevelDesigner() : openLevelDesigner();
}
