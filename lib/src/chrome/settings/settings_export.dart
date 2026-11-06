part of 'settings_dialog.dart';

/// Exporting and importing the settings.
extension _SettingsExport on _EditorSettingsDialogState {
  File get _settingsFile => File(
    '${Directory.current.path}/${_EditorSettingsDialogState.settingsFilePath}',
  );

  Future<void> _exportToProject() async {
    try {
      final file = _settingsFile;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        OverlaySettingsStore.export(_scope.prefs.settings.value),
      );
      _say('Saved to ${_EditorSettingsDialogState.settingsFilePath}.');
    } catch (error) {
      _say(
        'Could not save ${_EditorSettingsDialogState.settingsFilePath}: $error',
        error: true,
      );
    }
  }

  Future<void> _exportToClipboard() async {
    await Clipboard.setData(
      ClipboardData(
        text: OverlaySettingsStore.export(_scope.prefs.settings.value),
      ),
    );
    _say('Copied to the clipboard.');
  }

  Future<void> _importFromProject() async {
    final file = _settingsFile;
    if (!file.existsSync()) {
      _say(
        'There is no ${_EditorSettingsDialogState.settingsFilePath} in the project.',
        error: true,
      );
      return;
    }
    try {
      _import(
        await file.readAsString(),
        from: _EditorSettingsDialogState.settingsFilePath,
      );
    } catch (error) {
      _say(
        'Could not read ${_EditorSettingsDialogState.settingsFilePath}: $error',
        error: true,
      );
    }
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    _import(data?.text ?? '', from: 'the clipboard');
  }

  void _import(String text, {required String from}) {
    final current = _scope.prefs.settings.value;
    final imported = OverlaySettingsStore.import(text, current);
    if (imported == null) {
      _say('Nothing in $from is a settings export.', error: true);
      return;
    }
    _scope.commands.applyShortcuts(imported.shortcuts);
    _save(imported);
    _say(
      imported == current
          ? 'Imported from $from: it was all as it is.'
          : 'Imported from $from.',
    );
  }
}
