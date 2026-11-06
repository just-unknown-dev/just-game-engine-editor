part of 'just_game_editor_plugin.dart';

/// The open scene's session: leaving it, autosave, the last session
/// opened again, and what a play-test changed in the authored scene.
extension PluginScenes on JustGameEditorPlugin {
  /// Gets the open scene ready to be replaced by [opening]; whether it may
  /// be. True at once with no scene open.
  ///
  /// Unsaved changes are asked about through [askToLeaveScene] — saved,
  /// discarded, or kept by staying — and without anyone to ask the scene
  /// is not left. A save that fails or is refused keeps it open too. Then a
  /// play-test running in it stops (its snapshot is this scene's: a save
  /// after the open would write it into the other scene's file), and
  /// anything showing something other than the scene as authored — a
  /// timeline preview — puts it back.
  @internal
  Future<bool> leaveScene({required String opening}) async {
    final leaving = sceneState.activeScene.value;
    if (leaving == null) return true;
    if (sceneState.isDirty.value) {
      final ask = askToLeaveScene;
      if (ask == null) {
        scope.log.log(
          'Did not open $opening: ${leaving.name} has unsaved changes. Save '
          'it, or close it, first.',
          source: 'editor',
          category: 'scene',
          level: DebuggerLogLevel.warning,
        );
        return false;
      }
      final choice = await ask(leaving.name, opening);
      // The question took a while: the scene may have gone, or be saving.
      if (choice == null ||
          !identical(sceneState.activeScene.value, leaving) ||
          sceneIO.isBusy) {
        return false;
      }
      if (choice == UnsavedChoice.save) {
        try {
          if (!await saveScene()) return false;
        } catch (error) {
          scope.log.log(
            'Did not open $opening: ${leaving.name} could not be saved: '
            '$error',
            source: 'editor',
            category: 'scene',
            level: DebuggerLogLevel.error,
          );
          return false;
        }
      }
    }
    if (playController.isRunning) playController.stop();
    scope.restoreAuthoredState();
    return true;
  }

  /// Counts what the scene about to open asks to load, for the loader:
  /// sprites, atlases, tile maps and the rest read through [spriteAssets],
  /// and 3-D models. What was loading before it is left out.
  AssetTally Function() _countSceneAssets() {
    final files = spriteAssets.loads..restart();
    final models = <String>{};
    return () {
      var done = files.finished;
      var total = files.started;
      final graphics = engine.graphics3D;
      if (graphics != null && graphics.isStarted) {
        final cache = graphics.models;
        bool arrived(String path) =>
            cache.errorOf(path) != null || cache.get(path) != null;
        // The cache keeps the last scene's models too: a model is this
        // scene's once it is seen loading. The renderer asks for them as
        // it draws, so after the open.
        for (final path in List.of(cache.paths)) {
          if (!arrived(path)) models.add(path);
        }
        total += models.length;
        done += models.where(arrived).length;
      }
      return (done: done, total: total);
    };
  }

  /// Autosaves when the settings' interval has gone by. Timed by the clock
  /// on each update rather than a timer: nothing to cancel, and nothing
  /// runs while the editor is not.
  void _autosaveTick() {
    final interval = scope.prefs.settings.value.autosaveInterval;
    if (interval == null) {
      _nextAutosave = null;
      return;
    }
    final now = DateTime.now();
    final due = _nextAutosave ??= now.add(interval);
    if (now.isBefore(due)) return;
    _nextAutosave = now.add(interval);
    unawaited(autosave());
  }

  /// Autosaves the open scene as the settings say — a backup, or the scene
  /// saved — if it has unsaved changes. Waits, returning false, while a
  /// timeline preview shows, an open or save is under way (from the first
  /// question an open asks), or something is being dragged. True when
  /// something was written.
  @internal
  Future<bool> autosave() async {
    if (_autosaving ||
        !sceneState.hasScene ||
        !sceneState.isDirty.value ||
        sceneIO.isBusy ||
        _saving ||
        // Changes the author may just have chosen to discard.
        _openingScene ||
        scope.isAuthoredStateHeld ||
        // Mid-gesture the level is half-edited (tiles lifted off their
        // layer to be moved, an entity halfway along a gizmo drag): the
        // next autosave saves it whole.
        (designer.value?.hasActiveGesture ?? false) ||
        viewport.isDragging ||
        // Hidden, the game runs on the level: only the level kept as
        // authored is saved, and with none kept nothing is.
        (!isVisible.value && _hiddenSnapshot == null)) {
      return false;
    }
    _autosaving = true;
    try {
      final settings = scope.prefs.settings.value;
      if (settings.autosaveMode == AutosaveMode.save) {
        return await saveScene();
      }
      return await sceneIO.backup(
        asAuthored: _authoredWhilePlaying,
        editorData: designer.value?.editorData() ?? sceneIO.editorData,
        keep: settings.backupsToKeep,
      );
    } catch (error) {
      scope.log.log(
        'Autosave failed: $error',
        source: 'editor',
        category: 'scene',
        level: DebuggerLogLevel.warning,
      );
      return false;
    } finally {
      _autosaving = false;
    }
  }

  void _rememberScene() {
    // Another scene, or none: the level kept while the editor is hidden
    // was the one left, and is not put back over this one.
    _hiddenSnapshot = null;
    // Closed: the map files it was editing go back to what is on disk —
    // closed without saving, their edits are not this session's any more,
    // and the next scene's save must not write them.
    if (!sceneState.hasScene) scope.mapDocs.discardUnsaved();
    final name = sceneState.activeScene.value?.name ?? '';
    unawaited(scope.prefs.set(RecentScenes.lastScene, name));
    // The Scenes list's Recent, and the start card's Reopen.
    if (name.isNotEmpty) unawaited(RecentScenes.touch(scope.prefs, name));
  }

  // Opening another scene shuts the designer and opens it again: it ends
  // as it was, and so does what is remembered.
  void _rememberDesigner() => unawaited(
    scope.prefs.set(
      JustGameEditorPlugin._designerOpenPref,
      isLevelDesignerOpen,
    ),
  );

  /// Opens the scene that was open when the editor was last closed — and
  /// the Level Designer, if it was open on it — as the settings ask. Once,
  /// after the settings are loaded, and only with no scene open yet.
  @internal
  Future<void> reopenLastSession() async {
    if (_reopened) return;
    _reopened = true;
    final settings = scope.prefs.settings.value;
    if (!settings.reopenLastScene || sceneState.hasScene) return;
    final name = scope.prefs.get(RecentScenes.lastScene);
    final designerWasOpen = scope.prefs.get(
      JustGameEditorPlugin._designerOpenPref,
    );
    if (name.isEmpty || !scope.scenes.listSceneNames().contains(name)) return;
    await openScene(name);
    if (settings.reopenDesigner &&
        designerWasOpen &&
        sceneState.activeScene.value?.name == name &&
        !isLevelDesignerOpen) {
      openLevelDesigner();
    }
  }

  /// What a save writes while the game runs on the level: the level as it
  /// was when Play was pressed, or when the editor was hidden. Null
  /// otherwise, when the world is the level.
  List<Map<String, dynamic>>? get _authoredWhilePlaying =>
      playController.isRunning
      ? playController.snapshot?.entities
      : _hiddenSnapshot?.entities;
}
