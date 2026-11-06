part of 'just_game_editor_plugin.dart';

/// Showing and hiding the editor: what it suspends and gives the game
/// while hidden, and where the keyboard's focus goes.
extension PluginVisibility on JustGameEditorPlugin {
  void _setVisible(bool visible, {bool syncFocus = true}) {
    final opening = visible && !isVisible.value;
    final shouldShowStatusPanel = visible && !isStatusPanelVisible.value;
    final shouldHideStatusPanel = !visible && isStatusPanelVisible.value;
    if (isVisible.value == visible &&
        !shouldShowStatusPanel &&
        !shouldHideStatusPanel) {
      return;
    }
    final closing = !visible && isVisible.value;
    isVisible.value = visible;
    if (isVisible.value) {
      isStatusPanelVisible.value = true;
      _attachDebuggerIfReady();
      // Only when it really opens: open already (its status panel shown
      // again), the game's own scale was kept then, and the 0 there now is
      // the editor's.
      if (opening) {
        _holdGameTime();
        _restoreHiddenLevel();
      }
    } else {
      isStatusPanelVisible.value = false;
      // Closing the editor mid-play-test would otherwise leave play-spawned
      // entities and a stale play state behind.
      if (playController.isRunning) stop();
      if (closing) _keepHiddenLevel();
      _detachDebugger();
      // What the game ran at before the editor stopped it; untouched when
      // the editor never did (it opened and closed before the engine
      // started).
      final kept = _preEditorTimeScale;
      if (kept != null && engine.isInitialized) engine.time.timeScale = kept;
      _preEditorTimeScale = null;
    }
    if (kDebugMode) {
      debugPrint(
        '[JustGameEditor] editor ${isVisible.value ? 'opened' : 'closed'} '
        '(toggle: ${toggleKey.keyLabel.isEmpty ? toggleKey.debugName : toggleKey.keyLabel})',
      );
    }
    logService.log(
      'Editor ${isVisible.value ? 'opened' : 'closed'}.',
      source: 'editor',
      category: 'visibility',
      mirrorToDebugger: false,
    );
    if (syncFocus) _syncFocus();
  }

  /// Hidden over an open scene, the editor's world is the game's: its
  /// systems run on the level as they do in a play-test — bodies fall,
  /// timelines move platforms, pickups are taken. So the level is kept as
  /// authored first, as Play keeps it: a save meanwhile (autosave, or
  /// Ctrl+S once shown) writes it, and showing the editor puts it back
  /// ([_restoreHiddenLevel]).
  void _keepHiddenLevel() {
    // Kept already: one that could not be put back is the level still.
    if (_hiddenSnapshot != null) return;
    if (!sceneState.hasScene || !engine.isInitialized) return;
    // With nothing previewed, as Play takes it.
    scope.restoreAuthoredState();
    try {
      _hiddenSnapshot = PlaySnapshot.capture(
        engine.world,
        scope.codec,
        rootOrder: sceneState.rootOrder(engine.world),
      );
    } on Object catch (error, stack) {
      // Nothing kept: autosave waits until the editor is shown again.
      scope.log.log(
        'Hiding the editor could not keep the level as authored: $error. '
        'Nothing is saved while it is hidden.',
        source: 'editor',
        category: 'scene',
        level: DebuggerLogLevel.error,
        details: '$stack',
      );
    }
  }

  /// Puts back the level [_keepHiddenLevel] kept, as Stop does: what the
  /// game made goes, what it destroyed comes back, and every entity is as
  /// it was authored.
  ///
  /// One that cannot be put back is kept, as a failed Stop keeps its
  /// snapshot: a save still writes the level as authored, and the log says
  /// to open the scene again.
  void _restoreHiddenLevel() {
    final snapshot = _hiddenSnapshot;
    if (snapshot == null || !engine.isInitialized) {
      _hiddenSnapshot = null;
      return;
    }
    try {
      snapshot.restoreInto(engine.world, onRecreated: sceneState.entityRebuilt);
    } on Object catch (error, stack) {
      scope.log.log(
        'Showing the editor could not put the level back as it was: '
        '$error. A save still writes it as authored; open the scene again '
        'to go on editing it.',
        source: 'editor',
        category: 'scene',
        level: DebuggerLogLevel.error,
        details: '$stack',
      );
      return;
    }
    _hiddenSnapshot = null;
    PlayController.reselectLiving(sceneState, engine.world);
    sceneState.refresh();
    _refreshPrefabsChangedMeanwhile();
  }

  /// See [detach].
  void _suspend() {
    if (!_isInitialized || _suspended) return;
    _suspended = true;
    // No focus to hand anywhere: the widget is gone.
    _setVisible(false, syncFocus: false);
    _releaseEngine();
    try {
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    } catch (_) {
      // The keyboard singleton is unavailable if no binding was initialized.
    }
    _presence?.stop();
    _presence = null;
  }

  /// Put back on an engine after [detach].
  void _resume() {
    if (!_suspended) return;
    _suspended = false;
    _presence ??= EditorPresence.start();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  /// Hands back what the editor's per-frame syncs set on the engine, as the
  /// game has it with no editor: what runs only in a play-test runs, no
  /// collider outlines, no 3-D aids, no view of the editor's over the
  /// scene's, the game's own draw rate.
  void _releaseEngine() {
    scope.viewOverride = null;
    if (!engine.isInitialized) return;
    _syncRuntimeSystems(0);
    _removeColliderOutlines();
    final graphics = engine.services.maybe<g3.Graphics3D>();
    if (graphics != null && graphics.isStarted) {
      final renderer = graphics.sceneRenderer;
      if (identical(renderer.aids, sceneAids) ||
          identical(renderer.aids, _playAids)) {
        renderer.aids = null;
      }
    }
    if (_drawingHeld) {
      engine.rendering.drawInterval = _gameDrawInterval;
      _gameDrawInterval = null;
      _drawingHeld = false;
    }
  }

  void _syncFocus() {
    if (isVisible.value) {
      gameFocusScopeNode.unfocus(disposition: UnfocusDisposition.scope);
      if (!editorFocusNode.hasFocus) editorFocusNode.requestFocus();
      return;
    }
    if (editorFocusNode.hasFocus) editorFocusNode.unfocus();
    gameFocusScopeNode.requestFocus();
  }
}
