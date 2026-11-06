part of 'timeline_session.dart';

/// Editing the open timeline as one undo step each: its fields, markers,
/// the work range and curves.
extension TimelineSessionEdits on TimelineSession {
  // ── Editing ──────────────────────────────────────────────────────────────

  /// Why the open timeline cannot be changed now; null when it can.
  String? get _lockedBecause {
    final file = _path;
    if (file != null && !ProjectFiles.isContained(file)) {
      return '$file is outside the project, so the editor does not write '
          'it: copy it into the project to change it.';
    }
    if (file != null && !PackageAssetPaths.of(root).isWritable(file)) {
      return '$file is in pub\'s shared cache, which is read-only: copy it '
          'into the project to change it.';
    }
    if (file == null && !isAuthoring()) {
      return 'This timeline is part of the scene: stop the play-test to '
          'change it.';
    }
    return null;
  }

  /// Whether the open timeline can be changed now: it is not a file in
  /// pub's shared cache, nor a timeline inside the scene during a
  /// play-test.
  bool get canEdit => asset.value != null && _lockedBecause == null;

  // Whether an edit may go ahead; says why not when it may not.
  bool _mayEdit() {
    final why = _lockedBecause;
    if (why == null) return true;
    message.value = why;
    return false;
  }

  /// Replaces the timeline with [next], undoably.
  void apply(String label, TimelineAsset next) {
    final current = asset.value;
    if (current == null || !_mayEdit()) return;
    _lastRecord = null;
    _undo.add(_Step(label, current));
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
    _set(next);
  }

  void undo() {
    final current = asset.value;
    if (current == null || _undo.isEmpty || !_mayEdit()) return;
    final step = _undo.removeLast();
    _lastRecord = null;
    _redo.add(_Step(step.label, current));
    selection.value = const {};
    _set(step.asset);
  }

  void redo() {
    final current = asset.value;
    if (current == null || _redo.isEmpty || !_mayEdit()) return;
    final step = _redo.removeLast();
    _undo.add(_Step(step.label, current));
    selection.value = const {};
    _set(step.asset);
  }

  void _set(TimelineAsset next) {
    // The preview was built from the old timeline; put the world back before
    // building one from the new, so relative tracks start from the truth.
    final wasPreviewing = _playback != null;
    if (wasPreviewing) _quietly(_endPreview);
    asset.value = next;
    if (_path == null) {
      // An inline timeline lives in the scene: the scene is what changed.
      final player = _owner?.getComponent<TimelinePlayerComponent>();
      if (player != null) {
        player.inline = next;
        scope.sceneState.markDirty();
      }
    } else {
      isDirty.value = true;
    }
    if (playhead.value > next.duration) playhead.value = next.duration;
    revision.value++;
    if (wasPreviewing) {
      _quietly(() => scrubTo(playhead.value));
      if (_playback == null) _destroyScratch();
    } else {
      // The viewport draws the timeline's motion paths.
      scope.sceneState.refresh();
    }
  }

  /// Writes a file timeline to disk. An inline one is saved with the scene.
  ///
  /// Saves follow one another, so two quick ones never write at once. A
  /// file outside the project, or in pub's shared cache, is not written. A
  /// failure is said in [message] and in the log; the changes stay.
  Future<bool> save() {
    final current = asset.value, file = _path;
    if (current == null || file == null) return Future.value(false);
    final previous = _saving;
    final write = () async {
      if (previous != null) await previous;
      return _write(current, file);
    }();
    _saving = write;
    return write;
  }

  Future<bool> _write(TimelineAsset current, String file) async {
    final paths = PackageAssetPaths.of(root);
    if (!ProjectFiles.isContained(file)) {
      _saveFailed(file, 'it is not inside the project');
      return false;
    }
    if (!paths.isWritable(file)) {
      _saveFailed(file, 'it is in pub\'s shared cache, which is read-only');
      return false;
    }
    try {
      await ProjectFiles.writeString(
        paths.absolute(file),
        '${current.encode()}\n',
      );
    } catch (e) {
      _saveFailed(file, '$e');
      return false;
    }
    // Still the timeline written, unchanged since: nothing left to write.
    if (_path == file && identical(asset.value, current)) {
      isDirty.value = false;
    }
    onSaved?.call(file);
    return true;
  }

  void _saveFailed(String file, String why) {
    final text = 'Could not save $file: $why. Its changes are still open.';
    message.value = text;
    scope.log.log(
      text,
      source: 'editor',
      category: 'timeline',
      level: DebuggerLogLevel.warning,
    );
  }

  /// Whether a timeline file called [name] — as [extractToAsset] would name
  /// it — is in the project already.
  bool isTimelineNameTaken(String name) {
    final file = TimelineSession._timelineFileFor(name);
    return file != null && PackageAssetPaths.of(root).file(file).existsSync();
  }

  /// [base] as a timeline name no file in the project has yet: itself, or
  /// with `_2`, `_3`… after it.
  String freeTimelineName(String base) {
    final safe = TimelineSession._safeName(base);
    final stem = safe.isEmpty || safe == '_' ? 'timeline' : safe;
    if (!isTimelineNameTaken(stem)) return stem;
    for (var i = 2; ; i++) {
      if (!isTimelineNameTaken('${stem}_$i')) return '${stem}_$i';
    }
  }

  /// Moves an inline timeline into a file of its own, which the player then
  /// names — so other entities can play it too. The player's change is one
  /// step of the editor's undo.
  ///
  /// Never over a file that is there already: whoever plays that one would
  /// play this from then on, and its keys would be gone. False then, saying
  /// so in [message].
  Future<bool> extractToAsset(String name) async {
    final current = asset.value, entity = _owner;
    final player = entity?.getComponent<TimelinePlayerComponent>();
    if (current == null || player == null || !isInline) return false;
    if (!_mayEdit()) return false;
    final file = TimelineSession._timelineFileFor(name);
    if (file == null) return false;
    if (await PackageAssetPaths.of(root).file(file).exists()) {
      message.value =
          '$file is there already: pick another name. Nothing was written.';
      return false;
    }
    // Something else was opened while the disk was asked.
    if (!identical(asset.value, current) || !identical(_owner, entity)) {
      return false;
    }
    endPreview();
    _path = file;
    final named = current.copyWith(name: TimelineSession._safeName(name));
    asset.value = named;
    if (!await save()) {
      if (identical(asset.value, named)) {
        _path = null;
        asset.value = current;
      }
      return false;
    }
    final edit = ComponentEdit.begin(scope, player);
    player
      ..timelinePath = file
      ..inline = null;
    edit.commit('Extract the timeline');
    _followsPlayer = true;
    revision.value++;
    return true;
  }

  // ── Markers and the work range ───────────────────────────────────────────

  void addMarker(double time, String name) {
    final current = asset.value;
    if (current == null) return;
    apply(
      'Marker',
      current.copyWith(
        markers: [
          ...current.markers,
          TimelineMarker(time: snapTime(time), name: name),
        ],
      ),
    );
  }

  void removeMarker(int index) {
    final current = asset.value;
    if (current == null) return;
    apply(
      'Remove marker',
      current.copyWith(
        markers: [
          for (var i = 0; i < current.markers.length; i++)
            if (i != index) current.markers[i],
        ],
      ),
    );
  }

  void updateMarker(int index, {double? time, String? name}) {
    final current = asset.value;
    if (current == null) return;
    apply('Marker', _withMarker(current, index, time: time, name: name));
  }

  TimelineAsset _withMarker(
    TimelineAsset base,
    int index, {
    double? time,
    String? name,
  }) {
    final m = base.markers[index];
    return base.copyWith(
      markers: [
        for (var i = 0; i < base.markers.length; i++)
          if (i == index)
            TimelineMarker(
              time: time == null ? m.time : snapTime(time),
              name: name ?? m.name,
            )
          else
            base.markers[i],
      ],
    );
  }

  /// A frame of dragging marker [index] of [start] to [time]; the drag
  /// begins with [beginDrag] and ends with [endDrag], one undo step. Returns
  /// where the marker is now: markers sort by time. -1 when it is gone.
  int dragMarker(TimelineAsset start, int index, double time) {
    if (index < 0 || index >= start.markers.length) return -1;
    final name = start.markers[index].name;
    final at = snapTime(time);
    _set(_withMarker(start, index, time: at));
    return asset.value!.markers.indexWhere(
      (m) => m.name == name && (m.time - at).abs() < 1e-9,
    );
  }

  /// The player of the open timeline, when an entity owns it.
  TimelinePlayerComponent? get player =>
      _owner?.getComponent<TimelinePlayerComponent>();

  /// Gives the player the work range as its **play range**: from here on it
  /// runs only that stretch, in the game as well as here.
  ///
  /// This is the one way an editor-only view — the work range — becomes
  /// something the scene keeps, so it asks before it changes anything.
  bool applyWorkRangeToPlayer() {
    final range = workRange.value;
    if (range == null) return false;
    return setPlayRange(range.$1, range.$2);
  }

  /// Sets what the entity's player runs, in seconds, as one step of the
  /// editor's undo. Zero for [to] plays to the end; the two are sorted, so
  /// dragging one edge past the other is not an error.
  bool setPlayRange(double from, double to) {
    final target = player;
    if (target == null || !isAuthoring()) return false;
    final edit = ComponentEdit.begin(scope, target);
    _writePlayRange(target, from, to <= 0 ? duration : to);
    edit.commit('Play range');
    revision.value++;
    return true;
  }

  void _writePlayRange(TimelinePlayerComponent target, double a, double b) {
    final lo = math.min(a, b).clamp(0.0, duration).toDouble();
    final hi = math.max(a, b).clamp(0.0, duration).toDouble();
    // A range that is the whole thing is no range at all.
    final whole = lo <= 0 && hi >= duration - 1e-6;
    target
      ..from = whole ? 0 : lo
      ..to = whole ? 0 : hi;
  }

  /// A drag of an end of the play range begins. What comes back makes the
  /// whole drag one step of the editor's undo: hand it to
  /// [endPlayRangeDrag].
  ComponentEdit? beginPlayRangeDrag() {
    final target = player;
    if (target == null || !isAuthoring()) return null;
    return ComponentEdit.begin(scope, target);
  }

  /// A frame of dragging an end of the play range to [moving], the other
  /// end staying at [fixed] — where it was when the drag began, so dragging
  /// one past the other does not drag the other along. The range is a frame
  /// long at the least.
  void dragPlayRange(double moving, double fixed) {
    final target = player;
    if (target == null) return;
    final frame = fps > 0 ? 1 / fps : 0.01;
    var a = moving, b = fixed;
    if ((a - b).abs() < frame) {
      a = a >= b ? b + frame : b - frame;
      if (a < 0) a = b + frame;
      if (a > duration) a = b - frame;
    }
    _writePlayRange(target, a, b);
    revision.value++;
  }

  /// The drag that [beginPlayRangeDrag] began is over.
  void endPlayRangeDrag(ComponentEdit? edit) {
    if (edit == null) return;
    edit.commit('Play range');
    revision.value++;
  }

  /// Back to playing the whole timeline, as one step of the editor's undo.
  bool clearPlayRange() {
    final target = player;
    if (target == null || !target.hasRange || !isAuthoring()) return false;
    final edit = ComponentEdit.begin(scope, target);
    target
      ..from = 0
      ..to = 0;
    edit.commit('Play the whole timeline');
    revision.value++;
    return true;
  }

  /// Shows the player's play range as the work range, to see or adjust it.
  bool workRangeFromPlayer() {
    final target = player;
    if (target == null || !target.hasRange) return false;
    setWorkRange(target.from, target.to <= 0 ? duration : target.to);
    return true;
  }

  void setWorkRange(double from, double to) {
    final a = snapTime(from < to ? from : to),
        b = snapTime(from < to ? to : from);
    workRange.value = b - a < 1e-6 ? null : (a, b);
  }

  /// A frame of dragging keys in the curve editor: [refs] of [start] moved
  /// by [dt] seconds and [dv] in value. See [dragItems].
  Set<TimelineItemRef> dragKeys(
    TimelineAsset start,
    Set<TimelineItemRef> refs,
    double dt,
    double dv,
  ) {
    if (!dt.isFinite || !dv.isFinite) return refs;
    final (shifted, moved) = _shifted(start, refs, dt);
    final tracks = List.of(shifted.tracks);
    if (dv != 0) {
      for (var t = 0; t < tracks.length; t++) {
        final track = tracks[t];
        final mine = {
          for (final r in moved)
            if (r.track == t) r.index,
        };
        if (mine.isEmpty || track is! PropertyTrack || track.locked) continue;
        if (track.isColor) continue;
        tracks[t] = track.copyWith(
          curve: KeyCurve([
            for (final (i, k) in track.curve.keys.indexed)
              mine.contains(i) && k.value is num
                  ? k.copyWith(value: k.number + dv)
                  : k,
          ]).withAutoTangents(),
        );
      }
    }
    _set(shifted.copyWith(tracks: tracks));
    selection.value = moved;
    return moved;
  }

  /// A frame of dragging a bezier handle of the key at [ref] in [start] to
  /// [tangent] (an offset from the key). A handle never points backwards in
  /// time or past the neighbouring key. Dragging a handle of an automatic
  /// key makes it aligned — the other handle turns with it — unless
  /// [breakApart], which leaves the other where it is.
  void dragTangent(
    TimelineAsset start,
    TimelineItemRef ref,
    bool outgoing,
    KeyTangent tangent, {
    bool breakApart = false,
  }) {
    if (!tangent.dt.isFinite || !tangent.dv.isFinite) return;
    final track = start.tracks[ref.track];
    if (track is! PropertyTrack || track.locked) return;
    final keys = track.curve.keys;
    final key = keys[ref.index];
    final room = outgoing
        ? (ref.index < keys.length - 1
              ? keys[ref.index + 1].time - key.time
              : 0.0)
        : (ref.index > 0 ? key.time - keys[ref.index - 1].time : 0.0);
    final dt = outgoing
        ? tangent.dt.clamp(1e-4, room <= 0 ? 1e-4 : room).toDouble()
        : tangent.dt.clamp(room <= 0 ? -1e-4 : -room, -1e-4).toDouble();
    final dragged = KeyTangent(dt, tangent.dv);

    final mode = breakApart || key.tangentMode == TangentMode.broken
        ? TangentMode.broken
        : TangentMode.aligned;
    var other = outgoing ? key.inTangent : key.outTangent;
    if (mode == TangentMode.aligned) {
      // Same line through the key, its own reach in time.
      other = KeyTangent(other.dt, other.dt * (dragged.dv / dragged.dt));
    }
    final next = key.copyWith(
      tangentMode: mode,
      inTangent: outgoing ? other : dragged,
      outTangent: outgoing ? dragged : other,
    );
    _set(
      start.withTrackAt(
        ref.track,
        track.copyWith(curve: KeyCurve(List.of(keys)..[ref.index] = next)),
      ),
    );
  }
}
