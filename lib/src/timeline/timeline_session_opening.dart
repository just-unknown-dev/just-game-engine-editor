part of 'timeline_session.dart';

/// Opening a timeline: from a file, an entity's own, a new one.
extension TimelineSessionOpening on TimelineSession {
  // ── Opening ──────────────────────────────────────────────────────────────

  /// Shows what [entity] plays: its timeline file, else its inline timeline,
  /// else nothing. A dirty file is saved on the way out; when that save
  /// fails, the file stays open with its changes, saying why.
  ///
  /// An entity that plays nothing but that one of the open timeline's
  /// tracks moves leaves the timeline open: that is how it is keyed.
  Future<void> follow(Entity? entity) async {
    final player = entity?.getComponent<TimelinePlayerComponent>();
    if (player == null) {
      // A file opened by itself stays open while nothing else is chosen.
      if (asset.value != null && (_owner == null || _bindsTrack(entity))) {
        return;
      }
      await close();
      return;
    }
    final file = player.timelinePath.trim();
    if (identical(entity, _owner) &&
        (file.isEmpty
            ? isInline && identical(player.inline, asset.value)
            : file == _path)) {
      return;
    }
    if (file.isNotEmpty) {
      await openFile(file, owner: entity);
    } else {
      final ticket = ++_opening;
      if (!await _leave() || ticket != _opening) return;
      _show(player.inline, path: null, owner: entity);
    }
  }

  // Whether [entity] is someone a track of the open timeline moves.
  bool _bindsTrack(Entity? entity) {
    if (entity == null) return false;
    for (final track in asset.value?.tracks ?? const <TimelineTrack>[]) {
      if (track.binding.isSelf) continue;
      if (identical(_resolve(track.binding), entity)) return true;
    }
    return false;
  }

  /// Opens the project's [file]. With [owner], "self" tracks preview on it.
  /// False when it did not open — or when what was open could not be saved
  /// first, and so stays open.
  Future<bool> openFile(String file, {Entity? owner}) async {
    final ticket = ++_opening;
    if (!await _leave() || ticket != _opening) return false;
    try {
      final source = await PackageAssetPaths.of(root).file(file).readAsString();
      if (ticket != _opening) return false;
      _show(
        TimelineAsset.parse(
          source,
          kinds: scope.context.trackKinds,
          migrations: scope.context.migrations,
        ),
        path: file,
        owner: owner,
      );
      return true;
    } catch (e) {
      if (ticket != _opening) return false;
      _show(null, path: null, owner: owner);
      _requested = file;
      message.value = 'Could not open $file: $e';
      return false;
    }
  }

  /// Closes the timeline. False when its file had changes that could not
  /// be written: it stays open, saying why.
  Future<bool> close() async {
    final ticket = ++_opening;
    if (!await _leave() || ticket != _opening) return false;
    _show(null, path: null, owner: null);
    return true;
  }

  /// Shows again what the owner's player plays, when the scene changed
  /// under the open timeline with the selection where it was: an editor
  /// undo of "Extract" or of "Add a Timeline Player", a play-test's Stop
  /// putting the scene back as it was.
  Future<void> resync() async {
    final owner = _owner;
    if (owner == null || !_followsPlayer || !isAuthoring()) return;
    final player = owner.isAlive
        ? owner.getComponent<TimelinePlayerComponent>()
        : null;
    if (player == null) {
      await close();
      return;
    }
    final file = player.timelinePath.trim();
    if (file.isNotEmpty) {
      if (file != _path && file != _requested) {
        await openFile(file, owner: owner);
      }
      return;
    }
    if (_path == null && identical(player.inline, asset.value)) return;
    final ticket = ++_opening;
    if (!await _leave() || ticket != _opening) return;
    _show(player.inline, path: null, owner: owner);
  }

  // The look at the open timeline ends: the preview, playing, and a file's
  // changes written. False when that write failed: the file and its
  // changes stay open, and nothing else should be shown over them.
  Future<bool> _leave() async {
    endPreview();
    isPlaying.value = false;
    if (isDirty.value && _path != null) return save();
    return true;
  }

  void _show(TimelineAsset? next, {required String? path, Entity? owner}) {
    _path = path;
    _owner = owner;
    _requested = path;
    final player = owner?.getComponent<TimelinePlayerComponent>();
    _followsPlayer =
        player != null && (path == null || player.timelinePath.trim() == path);
    _undo.clear();
    _redo.clear();
    _lastRecord = null;
    isDirty.value = false;
    message.value = null;
    selection.value = const {};
    selectedTrack.value = null;
    playhead.value = 0;
    workRange.value = null;
    record.value = false;
    asset.value = next;
    revision.value++;
    opened.value++;
    // The inspector shows key buttons only while a timeline is open.
    scope.sceneState.refresh();
  }

  /// Gives [entity] a Timeline Player (if it has none) holding an empty
  /// inline timeline, and opens it — one step of the editor's undo.
  void createInlineFor(Entity entity) {
    if (!isAuthoring()) {
      message.value =
          'A timeline in an entity is part of the scene: stop the '
          'play-test to make one.';
      return;
    }
    final file = _path;
    if (isDirty.value && file != null) {
      message.value = 'Save $file first: it has changes not written yet.';
      return;
    }
    endPreview();
    isPlaying.value = false;
    final fresh = TimelineAsset(duration: 2);
    var player = entity.getComponent<TimelinePlayerComponent>();
    if (player == null) {
      player = TimelinePlayerComponent(inline: fresh);
      scope.history.push(
        AddComponentCommand(
          entity: entity,
          component: player,
          sceneState: scope.sceneState,
        ),
      );
    } else {
      final edit = ComponentEdit.begin(scope, player);
      player
        ..timelinePath = ''
        ..inline = fresh;
      edit.commit('Create a timeline');
    }
    _show(player.inline, path: null, owner: entity);
  }
}
