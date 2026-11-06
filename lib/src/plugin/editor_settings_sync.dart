part of 'just_game_editor_plugin.dart';

/// The settings the plugin follows: the overlay's, the designer's snap,
/// pausing on an error, drawing under a workspace.
extension PluginSettings on JustGameEditorPlugin {
  /// Takes the grid, snapping and gizmo settings the overlay read from the
  /// preferences; a grid size of 0 or less is taken as 32.
  @internal
  void applyOverlaySettings({
    required bool showGrid,
    required bool gridSnappingEnabled,
    required double gridSize,
    GizmoSettings gizmos = GizmoSettings.defaults,
  }) {
    final nextGridSize = gridSize <= 0 ? 32.0 : gridSize;
    this.showGrid.value = showGrid;
    gizmoSettings.value = gizmos;
    _gridSnappingEnabled = gridSnappingEnabled;
    this.gridSize.value = nextGridSize;
    sceneState.setGridSnapping(
      enabled: _gridSnappingEnabled,
      gridSize: nextGridSize,
    );
  }

  void _followSettings() {
    _syncBackdrop();
    _syncDesignerSnap();
  }

  /// The designer's Snap and Smart are the settings': one switch, wherever
  /// it is flipped — the magnet over the viewport, the Settings, or the
  /// designer's own status bar.
  void _syncDesignerSnap() {
    final controller = designer.value?.controller;
    if (controller == null) return;
    final settings = scope.prefs.settings.value;
    controller.snapEnabled.value = settings.gridSnappingEnabled;
    controller.smartSnap.value = settings.smartSnap;
  }

  /// A logged error pauses a running play-test, when the settings ask.
  void _pauseOnError() {
    if (!scope.prefs.settings.value.pauseOnError) return;
    if (playController.state.value != EditorPlayState.playing) return;
    // Not from inside the log call that brought it.
    scheduleMicrotask(() {
      if (playController.state.value != EditorPlayState.playing) return;
      playController.pause();
      logService.log(
        'Paused the play-test: an error was logged.',
        source: 'editor',
        category: 'play',
        level: DebuggerLogLevel.warning,
      );
    });
  }

  void _syncDrawingUnderWorkspace() {
    if (!engine.isInitialized) return;
    final rendering = engine.rendering;
    final hold = scope.activeWorkspace.value != null;
    if (hold && !_drawingHeld) {
      _gameDrawInterval = rendering.drawInterval;
      rendering.drawInterval = JustGameEditorPlugin.drawIntervalUnderWorkspace;
      _drawingHeld = true;
    } else if (!hold && _drawingHeld) {
      rendering.drawInterval = _gameDrawInterval;
      _gameDrawInterval = null;
      _drawingHeld = false;
    }
  }
}
