part of 'settings_dialog.dart';

/// The settings' Keyboard page.
extension _SettingsKeyboardPage on _EditorSettingsDialogState {
  List<_Shortcut> _shortcuts() {
    final registry = _scope.commands;
    final all = [
      for (final command in registry.all)
        (
          group: _EditorSettingsDialogState._groupOf(command.id),
          command: command,
          keys: [for (final b in registry.bindingsFor(command.id)) b.shortcut],
        ),
    ];
    all.sort((a, b) {
      final byGroup = a.group.compareTo(b.group);
      return byGroup != 0
          ? byGroup
          : a.command.label.toLowerCase().compareTo(
              b.command.label.toLowerCase(),
            );
    });
    return all;
  }

  /// [chords] now run [commandId]. With [takeFrom], that command gives up
  /// [chord]. A command back at the keys it was built with is no longer a
  /// change. Chords are as settings store them ([KeyBinding.savedChord]),
  /// so the file reads the same on every OS.
  void _setShortcut(
    OverlayUiSettings s,
    String commandId,
    List<String> chords, {
    String? takeFrom,
    String? chord,
  }) {
    final registry = _scope.commands;
    final next = {...s.shortcuts};
    void put(String id, List<String> keys) {
      final built = [
        for (final b in registry.builtBindingsFor(id)) b.savedChord,
      ];
      if (listEquals(built, keys)) {
        next.remove(id);
      } else {
        next[id] = keys;
      }
    }

    if (takeFrom != null) {
      put(takeFrom, [
        for (final b in registry.bindingsFor(takeFrom))
          if (b.savedChord != chord) b.savedChord,
      ]);
    }
    put(commandId, chords);
    // Laid over the registry now, so the page shows it as it rebuilds.
    registry.applyShortcuts(next);
    _save(s.copyWith(shortcuts: next));
  }

  void _resetShortcut(OverlayUiSettings s, String commandId) {
    final next = {...s.shortcuts}..remove(commandId);
    _scope.commands.applyShortcuts(next);
    _save(s.copyWith(shortcuts: next));
  }
}
