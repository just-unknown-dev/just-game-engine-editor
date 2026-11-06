part of 'just_game_editor_plugin.dart';

/// The debugger's link to the engine, made once the engine is ready.
extension PluginDebugger on JustGameEditorPlugin {
  /// Feeds [debuggerController] from the engine — only while the editor is
  /// shown: it walks the whole world four times a second, for the docks and
  /// the status bar, which show only then.
  void _attachDebuggerIfReady() {
    if (_isDebuggerAttached || !engine.isInitialized || !isVisible.value) {
      return;
    }
    engine.attachDebugger(debuggerController);
    _isDebuggerAttached = true;
  }

  /// Stops feeding [debuggerController]: the editor is closed.
  void _detachDebugger() {
    if (!_isDebuggerAttached) return;
    debuggerController.stopBinding();
    _isDebuggerAttached = false;
  }
}
