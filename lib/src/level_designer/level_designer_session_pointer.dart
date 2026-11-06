part of 'level_designer_session.dart';

/// The designer's pointer routing and navigation.
extension LevelDesignerSessionPointer on LevelDesignerSession {
  /// Whether a right-button press should go to the active tool rather than
  /// open the context menu: only when the tool asks for it, and never with
  /// Shift held, so the menu is always one chord away.
  @internal
  bool claimsSecondary() =>
      (controller.activeTool?.acceptsSecondaryButton ?? false) &&
      !_readModifiers().shift;

  /// Counts [time]'s press into the run before it. Without a time — a
  /// press made by code — every press is a first one.
  int _countClick(Duration? time, Offset at, ToolButton button) {
    final last = _lastPressAt;
    final again =
        time != null &&
        last != null &&
        button == _lastPressButton &&
        time - last <= LevelDesignerSession.doubleClickTime &&
        (at - (_lastPressAt2 ?? at)).distance <=
            LevelDesignerSession.doubleClickSlop;
    final count = again ? _gestureClicks + 1 : 1;
    _lastPressAt = time;
    _lastPressAt2 = at;
    _lastPressButton = button;
    return count;
  }

  ToolContext _context(
    Offset worldPosition,
    double gridSize, {
    Offset? screen,
    Size? canvasSize,
  }) {
    final zoom = camera.zoom;
    final view = camera;
    final modifiers = _readModifiers();
    return ToolContext(
      space: view.isPlanar || screen == null
          ? null
          : SpaceContext(
              view: view,
              screen: screen,
              surfaceOf: (ignore) => surfaceAt(view, screen, ignore: ignore),
              plane: workingPlane,
              moveStep: sceneState.moveStep3D,
              snapping: controller.snapEnabled.value && !modifiers.control,
            ),
      unitsPerPixel: zoom > 0 ? 1 / zoom : 1,
      world: world,
      controller: controller,
      worldPosition: worldPosition,
      screenPosition: screen,
      canvasSize: canvasSize ?? camera.viewportSize,
      camera: camera,
      gridSize: gridSize,
      snapStep: scope.prefs.settings.value.moveStep,
      modifiers: modifiers,
      snapper: snapper,
      stateOf: stateOf,
      grid: scope.grid,
      button: _gestureButton,
      clickCount: _gestureClicks,
    );
  }

  /// In 3-D: the plane the designer builds on — the scope's, moved to the
  /// base of the selection while it follows the selection.
  @internal
  WorkingPlane get workingPlane {
    final state = scope.designer3D;
    if (!state.followSelection.value) return state.plane;
    return state.planeAt(selectionEntities());
  }

  /// In 3-D: the surface under [screen] on [view] — the nearest shown
  /// thing's, by its real shape where a pick test knows it, else the
  /// ground — leaving out [ignore].
  @internal
  SurfacePoint surfaceAt(
    EditorView view,
    Offset screen, {
    Set<jge.Entity> ignore = const {},
  }) => RayEntityPicker(tests: () => scope.pickTests).placementAt(
    view,
    screen,
    world.entities.where(
      (e) =>
          e.isActive && controller.isShownInViewport(e) && !ignore.contains(e),
    ),
  );

  /// Takes up the Move, Scale or Rotate mode just chosen: those are the
  /// select tool's gizmos, so it is picked up — unless tiles are selected
  /// with Select tiles, whose selection takes the same gizmos.
  @internal
  void adoptTransformMode() {
    final tool = controller.toolId.value;
    if (tool == BuiltInTools.select) return;
    if (tool == TileTools.select && scope.tiles.selection.value.isNotEmpty) {
      return;
    }
    setTool(BuiltInTools.select);
  }

  /// Switches to whichever tool claims [shortcut], if any; whether one did.
  @internal
  bool selectToolByShortcut(String shortcut) {
    final tool = tools.byShortcut(shortcut);
    if (tool == null) return false;
    setTool(tool.id);
    return true;
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  /// Centres and zooms the view on the selection (F).
  @internal
  void frameSelection() {
    final entities = selectionEntities();
    if (entities.isEmpty) {
      controller.setStatus('Nothing selected to frame');
      return;
    }
    _frame(SelectionOps.boundsOf(entities));
  }

  /// Centres and zooms the view on everything visible (Shift+F).
  @internal
  void frameAll() => _frame(
    SelectionOps.boundsOf([
      for (final e in world.query([jge.TransformComponent]))
        if (e.isActive && controller.isShownInViewport(e)) e,
    ]),
  );

  void _frame(Rect? bounds) {
    if (bounds == null) return;
    final cam = camera;
    cam.setPosition(bounds.center);
    final viewport = cam.viewportSize;
    if (viewport.isEmpty) return;
    // A margin so the edges are not flush with the viewport, and a ceiling
    // so framing a lone marker does not zoom in until it fills the screen.
    const margin = 1.25;
    final zoom = math.min(
      viewport.width / (math.max(bounds.width, 64) * margin),
      viewport.height / (math.max(bounds.height, 64) * margin),
    );
    cam.setZoom(zoom.clamp(cam.minZoom, math.min(cam.maxZoom, 4.0)));
  }

  /// Saves the current view in [slot] (Ctrl+1-9): in 3-D the orbit, its
  /// turn and its lens.
  @internal
  void storeBookmark(int slot) {
    final view = camera;
    if (view is OrbitFlyEditorView) {
      _bookmarks3D[slot] = view.pose;
    } else {
      _bookmarks[slot] = _CameraBookmark(camera.position, camera.zoom);
    }
    controller.setStatus('View saved to $slot');
  }

  /// Returns to the view saved in [slot] (1-9).
  @internal
  void recallBookmark(int slot) {
    final view = camera;
    if (view is OrbitFlyEditorView) {
      final pose = _bookmarks3D[slot];
      if (pose == null) {
        controller.setStatus(_noBookmark(slot));
        return;
      }
      view.pose = pose;
      return;
    }
    final bookmark = _bookmarks[slot];
    if (bookmark == null) {
      controller.setStatus(_noBookmark(slot));
      return;
    }
    camera
      ..setPosition(bookmark.position)
      ..setZoom(bookmark.zoom);
  }

  /// What the status bar says when [slot] has no view: with the keys that
  /// save one, as they are bound now — `Cmd+3` on a Mac.
  String _noBookmark(int slot) {
    final keys = scope.commands.bindingsFor('designer.bookmark.store.$slot');
    return keys.isEmpty
        ? 'No view saved in $slot'
        : 'No view saved in $slot - ${keys.first.shortcut} saves one';
  }
}
