part of 'assets_dock.dart';

/// What the Assets dock does to files: its keys and operations.
extension _AssetsDockOperations on _AssetsDockState {
  /// The keys the browser keeps while it has the focus itself (not its
  /// search field) and something is selected: Ctrl+D (Cmd+D on macOS, where
  /// Backspace also deletes).
  bool _claims(KeyEvent event) {
    if (!_focus.hasPrimaryFocus || _selected == null) return false;
    if (EditorKeys.primaryPressed) {
      return event.logicalKey == LogicalKeyboardKey.keyD;
    }
    return _AssetsDockState._keys.contains(event.logicalKey) ||
        EditorKeys.isDeleteKey(event.logicalKey);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_claims(event)) {
      return KeyEventResult.ignored;
    }
    final entry = _index.entryAt(_selected!);
    if (entry == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyD) {
      if (!entry.isDirectory && !entry.isPackage) unawaited(_duplicate(entry));
    } else if (EditorKeys.isDeleteKey(key)) {
      if (!entry.isPackage) unawaited(_delete(entry));
    } else if (key == LogicalKeyboardKey.f2) {
      if (!entry.isPackage) unawaited(_rename(entry));
    } else {
      _open(entry);
    }
    return KeyEventResult.handled;
  }

  /// The name of the scene at [path] (project-relative), when it is a scene
  /// of the scenes folder — what the editor opens a scene by; null for any
  /// other file.
  String? sceneNameOf(String path) => AssetsDock.sceneNameAt(
    _index.absolute(path),
    widget.scope.scenes.scenesRoot,
  );

  /// Points what is loaded in the editor at [to] wherever it named [from]
  /// — for a [folder], at the same place under [to] wherever it named a
  /// path under [from]; [files] are the files that were in it. The files
  /// on disk are rewritten separately.
  int _rewriteWorld(
    String from,
    String to, {
    bool folder = false,
    List<String> files = const [],
  }) {
    final scope = widget.scope;
    var changed = 0;
    for (final entity in scope.world.entities) {
      for (final component in entity.components) {
        final definition = scope.definitions.definitionFor(component);
        if (definition == null) continue;
        for (final field in definition.fields) {
          if (field.kind.id != jge.FieldTypes.assetRef.id) continue;
          final write = field.write;
          final value = field.read(component);
          if (write == null || value is! String) continue;
          final next = _AssetsDockState._moved(value, from, to, folder: folder);
          if (next == null) continue;
          write(component, next);
          changed++;
        }
      }
    }
    // Tile maps name their tilesets, and tilesets their images, inside
    // themselves rather than in a field.
    for (final file in folder ? files : [from]) {
      changed += scope.mapDocs.renamed(
        file,
        _AssetsDockState._moved(file, from, to, folder: folder) ?? file,
      );
    }
    if (changed > 0) {
      scope.sceneState
        ..markDirty()
        ..refresh();
    }
    return changed;
  }

  /// Why [entry] cannot be renamed or deleted ([verb]) now; null when it
  /// can.
  String? _whyNot(AssetEntry entry, String verb) {
    final scope = widget.scope;
    // The play-test's snapshot — what Stop puts back, and what a save
    // writes — would go on naming the old path.
    if (scope.isPlayTesting.value) {
      return 'Stop the play-test first: the level it will put back still '
          'names ${entry.name} as it is.';
    }
    bool isOrHolds(String? path) =>
        path != null &&
        (path == entry.path ||
            entry.isDirectory && path.startsWith('${entry.path}/'));
    final open = scope.activeWorkspace.value;
    if (isOrHolds(open?.path)) {
      return '${open!.path} is open in ${open.definition.label}; close it '
          'first.';
    }
    final scenes = _index.relative(scope.scenes.scenesRoot);
    if (entry.isDirectory && isOrHolds(scenes)) {
      return 'The editor and the game keep their scenes in $scenes; it '
          'cannot be ${verb}d.';
    }
    final scene = sceneNameOf(entry.path);
    if (scene != null) {
      if (_scenes.isProtected(scene)) {
        return '"$scene" is used by the game\'s own code and cannot be '
            '${verb}d.';
      }
      if (scope.sceneState.activeScene.value?.name == scene) {
        return '"$scene" is the scene open in the editor: close it first.';
      }
    }
    return null;
  }

  /// [_whyNot], said; true when it was.
  Future<bool> _refused(AssetEntry entry, String verb) async {
    final why = _whyNot(entry, verb);
    if (why == null) return false;
    await _confirm(
      title: "Can't $verb ${entry.name}",
      body: why,
      primary: 'OK',
      cancellable: false,
    );
    return true;
  }

  Future<void> _showReferences(AssetEntry entry) async {
    final users = await AssetReferences.find(_index, entry.path);
    if (!mounted) return;
    await _confirm(
      title: 'Used by',
      body: users.isEmpty
          ? 'Nothing in the project mentions ${entry.name} by its path: '
                'not the files under ${_index.folder}/, the game\'s code '
                'under ${AssetReferences.codeFolder}/, nor '
                '${AssetReferences.pubspec}.'
          : users.map((u) => '• $u').join('\n'),
      primary: 'OK',
      cancellable: false,
    );
  }

  Future<String?> _promptForName(String initial) async {
    final dot = initial.lastIndexOf('.');
    final controller = TextEditingController(text: initial)
      // The stem is what gets retyped; the extension rarely is.
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: dot <= 0 ? initial.length : dot,
      );
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => EditorLook(
          child: AlertDialog(
            backgroundColor: EditorTheme.dialogBg,
            title: Text(
              'Rename',
              style: TextStyle(color: EditorTheme.textPrimary, fontSize: 13),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: EditorTheme.textPrimary, fontSize: 12),
              onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(controller.text.trim()),
                child: const Text('Rename'),
              ),
            ],
          ),
        ),
      );
    } finally {
      // After the dialog's route has gone, not while it animates out.
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
  }

  /// True for [primary], false for [secondary], null when cancelled.
  Future<bool?> _confirm({
    required String title,
    required String body,
    required String primary,
    String? secondary,
    bool cancellable = true,
  }) => showDialog<bool>(
    context: context,
    builder: (context) => EditorLook(
      child: AlertDialog(
        backgroundColor: EditorTheme.dialogBg,
        title: Text(
          title,
          style: TextStyle(color: EditorTheme.textPrimary, fontSize: 13),
        ),
        content: SingleChildScrollView(
          child: Text(
            body,
            style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
          ),
        ),
        actions: [
          if (cancellable)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          if (secondary != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(secondary),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(primary),
          ),
        ],
      ),
    ),
  );
}
