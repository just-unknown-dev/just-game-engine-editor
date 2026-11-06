part of 'just_game_editor_plugin.dart';

/// The world while authoring: the runtime systems that run, the game's
/// focus and time, the 3-D scene aids and the collider outlines.
extension PluginAuthoring on JustGameEditorPlugin {
  // Systems that must not run on the scene being edited:
  //
  // * A timeline writes to the fields it animates. While authoring those
  //   fields are the scene being edited, so timelines only run in a
  //   play-test (whose changes are thrown away) — the Timeline dock
  //   previews by itself.
  // * Tile collision builds bodies from the maps. While authoring they
  //   would be rebuilt on every stroke for nothing; they are built when
  //   play starts, and destroyed with the play-test.
  // * Sound plays only in a play-test. Authoring, the game's AudioSystem
  //   would start every source on load, and mark it played in the scene
  //   being edited; when a play-test stops, what it played stops with it.
  //
  // Tile animation runs either way — on the game's clock in a play-test,
  // on the wall clock while authoring, when the game's time stands still.
  void _syncRuntimeSystems(double dt) {
    if (!engine.isInitialized) return;
    final run = !isAuthoring.value;
    for (final system in engine.world.systems) {
      if (system is TimelineSystem) system.isActive = run;
      if (system is MapCollisionSystem && system.isActive != run) {
        system.isActive = run;
        if (!run) system.clearGenerated();
      }
      if (system is AudioSystem && system.isActive != run) {
        system.isActive = run;
        if (!run) system.stopAll();
      }
      if (system is LevelMapSystem) {
        system.advanceClock = run;
        if (!run) system.clockMs += dt * 1000;
      }
    }
    // Shift+L's unlit view: only while authoring.
    BuiltInLighting2DContributions.syncUnlit(scope, authoring: !run);
    scope.mapDocs.pollAssets();
    // Only the layer being painted at full strength, while painting.
    scope.tiles.syncHighlight(
      engine.world,
      active:
          !run &&
          scope.activeWorkspace.value == null &&
          designer.value?.controller.activeTool?.group == ToolGroups.tiles,
    );
  }

  /// A press on the play-test's view, which takes the game's presses while
  /// it plays: a game that looks with the mouse
  /// (`input.lockPointerOnClick`) holds it, as it would outside the editor.
  /// Escape, Pause and Stop let go.
  @internal
  void pressedPlayingGame(PointerDownEvent event) {
    if (playController.state.value != EditorPlayState.playing) return;
    if (event.kind != PointerDeviceKind.mouse ||
        (event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }
    if (engine.isInitialized) engine.input.lockPointerForClick();
  }

  /// Gives the keyboard to the game.
  ///
  /// The game hears keys only while its own focus node is the primary focus,
  /// and nothing else hands that back: type a value in the inspector, press
  /// Play, and the keys kept going to the text field — the player stood
  /// still until the editor was restarted. Called when a play-test starts or
  /// resumes, and when the viewport is pressed during one (the editor's
  /// viewport absorbs the press the game would otherwise refocus on).
  @internal
  void focusGame() {
    FocusNode? game;
    for (final node in gameFocusScopeNode.descendants) {
      final context = node.context;
      if (context == null || node.onKeyEvent == null) continue;
      if (context.findAncestorWidgetOfExactType<GameWidget>() != null) {
        game = node;
        break;
      }
    }
    if (game == null) {
      // No game view to find: at least stop a text field eating the keys.
      if (JustGameEditorPlugin._isTypingInTextField) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
      return;
    }
    if (!game.hasPrimaryFocus) game.requestFocus();
  }

  void _syncSceneAids() {
    if (!engine.isInitialized) return;
    final graphics = engine.services.maybe<g3.Graphics3D>();
    if (graphics == null || !graphics.isStarted) return;
    final renderer = graphics.sceneRenderer;
    if (!isVisible.value || sceneState.editingMode != SceneMode.threeD) {
      renderer.aids = null;
      return;
    }
    if (!isAuthoring.value) {
      renderer.aids = showsGizmo(GizmoKind.selection) ? _playAids : null;
      return;
    }
    final state = scope.designer3D;
    renderer.aids = sceneAids
      ..viewMode = switch (state.viewMode.value) {
        View3DMode.lit => g3.Render3DViewMode.lit,
        View3DMode.unlit || View3DMode.collision => g3.Render3DViewMode.unlit,
        View3DMode.wireframe => g3.Render3DViewMode.wireframe,
      }
      // The outline is a gizmo: shown as the mode's say.
      ..highlighted = state.outline.value && showsGizmo(GizmoKind.selection)
          ? () => selectionEntities
          : null
      ..sliceY = state.sliceOn.value ? state.sliceY.value : null;
    sceneAids.skippedViews.clear();
    if (activeSplit != null) sceneAids.skippedViews.add(engine.rendering.view);
  }

  /// The engine's 2-D collider outlines: drawn while the mode now shows
  /// colliders (in a play-test or the Level Designer only once asked
  /// for), never with the editor closed; not for what the eye or a hidden
  /// layer hid. Only for a game with 2-D physics ([Physics2DSystem]), drawn
  /// through the camera its [RenderSystem] draws through.
  void _syncColliderOutlines() {
    if (!engine.isInitialized) return;
    final world = engine.world;
    final shown =
        showsGizmo(GizmoKind.colliders) && world.hasSystem<Physics2DSystem>();
    final outlines = _colliderOutlines;
    if (shown == (outlines != null && world.systems.contains(outlines))) {
      return;
    }
    if (shown) {
      final render = world.getSystem<RenderSystem>();
      world.addSystem(
        _colliderOutlines = Collider2DDebuggerSystem(
          camera: render != null ? render.camera : engine.camera.mainCamera,
          outlineFilter: _gizmosShownFor,
        ),
      );
    } else {
      _removeColliderOutlines();
    }
  }

  /// Takes [_colliderOutlines] off the game's world.
  void _removeColliderOutlines() {
    final outlines = _colliderOutlines;
    if (outlines == null) return;
    _colliderOutlines = null;
    if (engine.isInitialized && engine.world.systems.contains(outlines)) {
      engine.world.removeSystem(outlines);
    }
  }

  /// Switches the 3-D view between perspective and orthographic (pad 5).
  @internal
  void toggleOrthographic() {
    if (scope.editorView case final OrbitFlyEditorView view) {
      view.orthographic = !view.orthographic;
    }
  }

  /// While the editor is open and authoring (Play not pressed),
  /// [engine.time.timeScale] is held at 0, every frame, so the game
  /// underneath stands still: nothing the game does (a pause menu setting
  /// its time back to 1, say) can start the simulation on the level being
  /// edited.
  ///
  /// It used to go to 1 whenever the selected entity's sprite animation was
  /// playing — which every animated sprite is from its first frame — and
  /// then the whole world ran: bodies fell (with no tile collision while
  /// authoring), platforms moved, and the next save wrote where they had
  /// got to. Previews run by themselves now (the Timeline dock ticks its
  /// own clock), so nothing needs the game's time. Skipped outside pure
  /// authoring — [play]/[pause]/[stop] own timeScale once a play-test has
  /// started.
  void _holdTimeWhileAuthoring() {
    if (!engine.isInitialized) return;
    if (playController.isRunning) return;
    _holdGameTime();
  }

  /// Stops the game's clock, keeping what it ran at to give back when the
  /// editor closes — taken the first time the engine is there to ask, so an
  /// editor opened before the engine started still gives back the game's
  /// own scale, not a guess.
  void _holdGameTime() {
    if (!engine.isInitialized) return;
    _preEditorTimeScale ??= engine.time.timeScale;
    engine.time.timeScale = 0.0;
  }
}
