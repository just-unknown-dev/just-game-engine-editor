part of 'just_game_editor_plugin.dart';

/// The editor's keys: who gets a key press — the settings dialog, a
/// typed value, the designer, a command — and when the game does.
extension _PluginKeys on JustGameEditorPlugin {
  bool _dispatchKey(KeyEvent event) {
    if (!_isInitialized) return false;
    // A chord being bound in the settings: every key is for that.
    if (scope.chrome.capturingKeys) return false;
    // Flying (right button held in 3-D): the movement keys steer, and are
    // no shortcuts meanwhile.
    if (viewport.isLooking &&
        JustGameEditorPlugin._flyKeys.contains(event.logicalKey)) {
      return true;
    }
    // A scene opening: the editor waits for it, and Esc stops waiting on
    // its assets. The toggle key still hides the editor; a key let go
    // still reaches whatever saw it pressed.
    if (isVisible.value &&
        sceneIO.loading.isLoading &&
        event is! KeyUpEvent &&
        event.logicalKey != _toggleKey) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        sceneIO.loading.skip();
      }
      return true;
    }
    // Holding a key keeps nudging; nothing else acts on a repeat.
    if (event is KeyRepeatEvent) {
      if (EditorKeyClaim.focusedClaims(event)) return false;
      return scope.activeWorkspace.value == null &&
          isAuthoring.value &&
          !JustGameEditorPlugin._isTypingInTextField &&
          (designer.value?.handleKey(
                event.logicalKey,
                gridSize: gridSize.value,
                isRepeat: true,
              ) ??
              false);
    }
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    // A 3-D gizmo being dragged takes a typed value: digits, Enter, Esc.
    if (viewport.isDragging && viewport.typeKey(key)) return true;

    if (key == _toggleKey) {
      toggleVisibility();
      return true;
    }
    // The settings dialog is modal: Esc or its own chord shuts it, and every
    // other key is the dialog's — typing in its search must not pick a tool
    // or delete the selection behind it.
    final settingsOpen = scope.chrome.settingsOpen;
    if (settingsOpen.value) {
      final modifiers = ModifierKeys.fromHardwareKeyboard();
      if (key == LogicalKeyboardKey.escape ||
          scope.commands
              .bindingsFor(BuiltInCommands.settingsId)
              .any((b) => b.matches(key, modifiers))) {
        settingsOpen.value = false;
        return true;
      }
      return false;
    }
    // A focused panel that keeps a key for itself — the Scenes list's F2
    // renames, its Delete deletes a scene — has it.
    if (EditorKeyClaim.focusedClaims(event)) return false;
    // F2: the dock panel. The status bar itself comes and goes with the
    // editor, so there is nothing else for this key to switch.
    if (key == _statusPanelToggleKey) {
      if (!isVisible.value || scope.activeWorkspace.value != null) return false;
      scope.dockController.togglePanel(fallback: 'logs');
      return true;
    }
    if (!isVisible.value) return false;
    // A workspace has the screen: every other key is its own — Ctrl+S saves
    // its file, not the scene; B is its brush, not the level's.
    if (scope.activeWorkspace.value != null) return false;

    final context = CommandContext(
      scope: scope,
      session: designer.value,
      host: this,
      modifiers: ModifierKeys.fromHardwareKeyboard(),
      gridSize: gridSize.value,
    );
    final commands = scope.commands;
    // Save works even from inside a text field — with what was typed there,
    // kept first as leaving the field would keep it, not the value before.
    if (commands.resolve(key, context.modifiers)?.availability ==
        CommandAvailability.always) {
      PendingFieldEdits.flush();
    }
    if (commands.dispatch(
      key,
      context,
      availabilities: const {CommandAvailability.always},
    )) {
      return true;
    }
    // Everything below means something else in a text field: Delete,
    // Ctrl+C, Ctrl+Z, every single-letter tool key. A HardwareKeyboard
    // handler sees keys before the focused widget does.
    if (JustGameEditorPlugin._isTypingInTextField) return false;
    // A collider being edited: Esc finishes, Delete takes a point away.
    if (isAuthoring.value && Collider2DEditSession.of(scope).handleKey(key)) {
      return true;
    }
    // Level-building keys, and only while authoring: during Play the keys
    // belong to the game.
    final session = designer.value;
    if (session != null &&
        isAuthoring.value &&
        session.handleKey(key, gridSize: gridSize.value)) {
      return true;
    }
    return commands.dispatch(
      key,
      context,
      availabilities: const {CommandAvailability.editor},
    );
  }
}
