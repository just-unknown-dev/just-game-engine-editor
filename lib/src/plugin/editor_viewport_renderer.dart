part of 'just_game_editor_plugin.dart';

/// Drawing the viewport: the editor's view, the split panes and their
/// labels, and what the editor draws over the world.
extension PluginRendering on JustGameEditorPlugin {
  /// Draws the editor over the world: called from [renderOverlay], which
  /// the engine calls after [engine.world.render], while the editor is
  /// shown. Gizmos, markers and aids are drawn through the editor's view,
  /// in world space, on top of every entity.
  ///
  /// [size] is the actual canvas size [RenderingEngine] just rendered with —
  /// used here (rather than the separately-tracked [ViewportInput.canvasSize], which is
  /// only updated via a post-frame callback from pointer-event plumbing and
  /// can drift/lag a frame behind) so gizmo/marker positions always match
  /// where entities were actually drawn.
  void _render(Canvas canvas, Size size) {
    if (!_isInitialized || !isVisible.value) return;
    if (size == Size.zero) return;
    final split = activeSplit;
    if (split != null) {
      _renderPanes(canvas, size, split);
      return;
    }
    _renderView(canvas, size, preview: true);
  }

  /// [splitViews] while they are what the viewport shows; null otherwise.
  @internal
  SplitViews? get activeSplit =>
      splitViews.on.value &&
          isAuthoring.value &&
          sceneState.editingMode == SceneMode.threeD &&
          scope.sceneView is OrbitFlyEditorView
      ? splitViews
      : null;

  /// Splits the 3-D viewport four ways, or joins it again.
  @internal
  void toggleSplitViews() {
    if (sceneState.editingMode != SceneMode.threeD) return;
    splitViews.toggle();
  }

  /// Each pane of [split] in its quarter of the canvas: its own picture of
  /// the scene, and over it the editor's aids seen through it. The game's
  /// camera preview is not drawn over them.
  void _renderPanes(Canvas canvas, Size size, SplitViews split) {
    split.layout(size);
    final background = Paint()..color = engine.rendering.backgroundColor;
    canvas.drawRect(Offset.zero & size, Paint()..color = EditorTheme.border);
    for (final pane in split.panes) {
      canvas
        ..save()
        ..clipRect(pane.rect)
        ..translate(pane.rect.left, pane.rect.top);
      scope.throughPane(pane, () {
        final paneSize = pane.rect.size;
        canvas.drawRect(Offset.zero & paneSize, background);
        pane.frame.update(
          pane.view.camera,
          paneSize,
          interpolation: engine.rendering.interpolation,
        );
        for (final renderer in engine.rendering.sceneRenderers) {
          if (renderer.enabled) renderer.render(canvas, pane.frame);
        }
        _renderView(canvas, paneSize, preview: false);
      });
      _paintPaneLabel(canvas, pane, active: identical(pane, split.active));
      canvas.restore();
    }
    // No game camera preview over the four views: it drew the level a
    // fifth time each frame, over panes that show it four times already.
  }

  /// What has been typed during a gizmo drag, beside the gizmo.
  void _paintTyped(Canvas canvas, Offset at, String text) {
    final label = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: EditorTheme.textBright,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromLTWH(
      at.dx + 16,
      at.dy + 16,
      label.width + 12,
      label.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()..color = EditorTheme.panelBg.withValues(alpha: 0.9),
    );
    label
      ..paint(canvas, box.topLeft + const Offset(6, 3))
      // Its paragraph is native memory, let go of now rather than when the
      // collector gets to it: this is laid out every frame of a typed drag.
      ..dispose();
  }

  void _paintPaneLabel(Canvas canvas, ViewPane pane, {required bool active}) {
    final label = TextPainter(
      text: TextSpan(
        text: pane.kind.label,
        style: TextStyle(
          color: active ? EditorTheme.primary : EditorTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label
      ..paint(canvas, const Offset(8, 6))
      ..dispose();
    if (active) {
      canvas.drawRect(
        (Offset.zero & pane.rect.size).deflate(0.5),
        Paint()
          ..color = EditorTheme.primary.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke,
      );
    }
  }

  // ── The pointer, through the pane it is over ─────────────────────────

  /// Runs [handle] with [event] as [pane] sees it: its position in the
  /// pane, the pane's view as the editor's, the canvas the pane's size.
  T _inPane<T>(
    ViewPane pane,
    PointerEvent event,
    T Function(PointerEvent) handle,
  ) {
    final shift = Matrix4.translationValues(-pane.rect.left, -pane.rect.top, 0);
    final local = event.transformed(
      event.transform == null ? shift : (shift..multiply(event.transform!)),
    );
    final canvas = viewport.canvasSize;
    viewport.updateCanvasSize(pane.rect.size);
    _inPaneDepth++;
    try {
      return scope.throughPane(pane, () => handle(local));
    } finally {
      _inPaneDepth--;
      viewport.updateCanvasSize(canvas);
    }
  }

  /// Between gestures the editor's view is the pane last used, so a key —
  /// F, the pad's views, flying — works in it; with no split, its own.
  void _syncSplit() {
    final split = activeSplit;
    final pane = split?.active ?? split?.panes.last;
    scope.viewOverride = pane?.view;
  }

  void _renderView(Canvas canvas, Size size, {required bool preview}) {
    final camera = scope.editorView..viewportSize = size;
    // In space (a 3-D scene) the 2-D aids — the pixel grid, camera rigs,
    // collider outlines — have nothing to say; the ground grid and the
    // 3-D gizmo take their place.
    final flat = camera.isPlanar;

    if (isGridVisible.value) {
      if (flat) {
        scope.grid.paintGrid(canvas, camera, size, cellSize: gridSize.value);
      } else {
        // On the plane the 3-D designer builds on — the ground, unless it
        // was moved or turned — in the move step.
        paintPlaneGrid(
          canvas,
          camera,
          plane: designer.value?.workingPlane ?? scope.designer3D.plane,
          step: sceneState.moveStep3D,
        );
      }
    }

    // Between the grid and the gizmos: level overlays sit above the grid so
    // they read as part of the level, and below the gizmo handles so those
    // stay visible and grabbable on top of everything.
    designer.value?.paint(canvas, size, camera);

    // The designer draws the camera rigs as one of its overlays; with it
    // closed the base editor draws them itself. Each gizmo as the mode now
    // shows it.
    if (flat && designer.value == null && showsGizmo(GizmoKind.cameras)) {
      CameraRigPainter.paint(
        DesignerCanvas(canvas: canvas, size: size, camera: camera),
        engine.world,
        brain: scope.cameraBrain,
        isSelected: (entity) =>
            sceneState.selectedEntity.value?.id == entity.id ||
            sceneState.isInMultiSelection(entity.id),
        isShown: _gizmosShownFor,
      );
    }

    // Cameras, spawn points and whatever else a module marks.
    final icons = showsGizmo(GizmoKind.icons);
    for (final marker in icons ? scope.markers : const <EditorMarker>[]) {
      final where = marker.where;
      _gizmoPainter.paintMarkers(
        canvas,
        marker,
        [
          for (final e in engine.world.query([
            TransformComponent,
            ...marker.components,
          ]))
            if (_gizmosShownFor(e) && (where == null || where(e))) e,
        ],
        camera,
        size,
      );
    }

    // What the modules draw over the level: a light's reach, a frustum.
    // The 3-D Collision view mode is for its colliders, gizmos or not.
    if (scope.viewportOverlays.isNotEmpty) {
      final hidden = scope.hiddenOverlays.value;
      final overlayContext = ViewportOverlayContext(
        canvas: canvas,
        size: size,
        view: camera,
        scope: scope,
        // Every viewport overlay is a gizmo.
        isShown: _gizmosShownFor,
      );
      final collisionView =
          !flat &&
          isAuthoring.value &&
          scope.designer3D.viewMode.value == View3DMode.collision;
      for (final overlay in scope.viewportOverlays) {
        final forced = collisionView && overlay is Collider3DOverlay;
        if (!forced &&
            (!showsGizmo(overlay.gizmoKind) || hidden.contains(overlay.id))) {
          continue;
        }
        if (!overlay.dimensions.allows(sceneState.editingMode)) continue;
        overlay.paint(overlayContext);
      }
    }

    // The points of the selection that can be dragged.
    final handles = selectionHandles;
    if (handles.isNotEmpty) {
      paintViewportHandles(
        canvas,
        handles,
        camera.isPlanar
            ? (p) => camera.worldToScreen(Offset(p.x, p.y))
            : camera.projectToScreen,
        activeIndex: viewport.handleDrags?.activeIndex ?? -1,
      );
    }

    // A tag or physics layer hovered in the inspector: what has it. Asked
    // for there, so shown with the gizmos hidden too; not in a play-test.
    final highlighted = isAuthoring.value ? scope.highlightedTag.value : null;
    if (highlighted != null) {
      final world = engine.world;
      _gizmoPainter.paintTagHighlight(
        canvas,
        [
          ...world.allTagged(highlighted).where(_isDrawn),
          // Where something with the tag will be once the game spawns it.
          for (final spawner in scope.tags.spawnersGiving(highlighted))
            ...SpawnPoints.of(world, spawner.id).where(_isDrawn),
        ],
        highlighted,
        scope.tags.colorOf(highlighted),
        camera,
        size,
      );
    }

    final layer = isAuthoring.value ? scope.highlightedLayer.value : null;
    if (layer != null) {
      final layers = scope.physicsLayers.value;
      _gizmoPainter.paintHighlight(
        canvas,
        [
          for (final e in PhysicsBodies.byLayer(
            engine.world,
            scope.definitions,
          )[layer])
            if (_isDrawn(e)) e,
        ],
        layers.labelOf(layer),
        layers.colorOf(layer),
        camera,
        size,
      );
    }

    // A collider being edited, over everything in the level.
    final collider = Collider2DEditSession.of(scope);
    if (flat && isAuthoring.value) collider.paint(canvas, camera);

    if (preview) {
      _paintGamePreview(canvas, size, engine.camera.mainCamera);
    }

    final selected = sceneState.selectedEntity.value;
    if (selected == null || !selected.isActive) return;
    // Its handles are the ones to take hold of: no gizmo over them.
    if (collider.isEditing(selected)) return;
    // The 2-D designer's select tool draws its own resize and rotate
    // handles, and claims every press — the base gizmo would be a second set
    // of handles that cannot be grabbed. The 3-D one leaves the gizmo be.
    if (flat &&
        designer.value?.controller.toolId.value == BuiltInTools.select &&
        isAuthoring.value) {
      return;
    }
    final outline = showsGizmo(GizmoKind.selection);
    final mode = shownTransformMode;
    if (mode == null) {
      // No handles (a play-test, or a selection none can move): its
      // outline alone, when the mode shows it. In space the renderer
      // outlines it.
      if (flat && outline) {
        _gizmoPainter.paintSelectionOutline(canvas, selected, camera, size);
      }
      return;
    }
    if (!flat) {
      final gizmo = Gizmo3DPainter.of(
        selected,
        camera,
        local: sceneState.localGizmo,
        pivot: viewport.gizmoPivot(),
      );
      if (gizmo != null) {
        paintGizmo3D(canvas, gizmo, mode: mode, active: viewport.activeHandle);
        final typed = viewport.typedLabel;
        if (typed != null) _paintTyped(canvas, gizmo.origin, typed);
      }
      return;
    }
    _gizmoPainter.paintGizmos(
      canvas,
      selected,
      camera,
      size,
      mode: mode,
      allows: transformModesAvailable,
      outline: outline,
    );
  }
}
