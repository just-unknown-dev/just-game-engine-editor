part of 'timeline_session.dart';

/// Time and the preview: the playhead, playing, and the editor's undo
/// while a preview shows.
extension TimelineSessionPreview on TimelineSession {
  // ── Time ─────────────────────────────────────────────────────────────────

  /// [time] on the nearest frame when snapping is on. Unlike [snapTime] it
  /// may land past the end — what dragging the end itself needs.
  double snapFrame(double time) =>
      snap.value && fps > 0 ? (time * fps).round() / fps : time;

  /// [time] on the nearest frame when snapping is on, and inside the
  /// timeline either way.
  double snapTime(double time) {
    final d = duration;
    return snapFrame(time).clamp(0.0, d > 0 ? d : double.infinity).toDouble();
  }

  /// Drags the timeline's end to [time], a frame long at the least.
  ///
  /// [start] is the timeline the drag began on, so however many frames it
  /// takes, it is one step to undo — see [beginDrag]. Keys left beyond the
  /// new end are kept, not cut: shortening a timeline by accident should
  /// cost nothing but another drag.
  void dragDuration(TimelineAsset start, double time) {
    if (!time.isFinite) return;
    final least = fps > 0 ? 1 / fps : 0.01;
    final next = snapFrame(time);
    final length = next < least ? least : next;
    if (asset.value?.duration == length) return;
    _set(start.copyWith(duration: length));
  }

  int frameOf(double time) => (time * fps).round();

  /// `12` or `0.40 s`, as the view is set.
  String formatTime(double time) =>
      showFrames.value ? '${frameOf(time)}' : '${time.toStringAsFixed(2)} s';

  /// Seconds across the sheet at this zoom.
  double get visibleSpan {
    final pixels = viewWidth.value - TimelineMetrics.leftInset;
    return pixels <= 0 ? 0 : pixels / pixelsPerSecond.value;
  }

  /// The last time worth scrolling to: the end of the timeline, or of what
  /// is on it when a track runs past the end.
  double get scrollEnd {
    final content = asset.value?.contentEnd ?? 0;
    return duration > content ? duration : content;
  }

  /// How far the sheet can scroll: whatever does not fit, plus
  /// [overscrollFraction] of a screen.
  ///
  /// The room is there even when the whole timeline fits. It earns nothing
  /// to look at, but a middle-drag that refuses to move reads as broken, and
  /// a dead gesture is worse than a little empty space.
  double get maxScroll {
    final span = visibleSpan;
    if (span <= 0) return 0;
    final overflow = scrollEnd - span;
    return (overflow < 0 ? 0 : overflow) +
        span * TimelineSession.overscrollFraction;
  }

  /// Scrolls so the sheet starts at [time], within what there is to see.
  void scrollTo(double time) =>
      scrollTime.value = time.clamp(0.0, maxScroll).toDouble();

  void scrollBy(double seconds) => scrollTo(scrollTime.value + seconds);

  /// Scrolls by [pixels] on screen — what a wheel or a drag hands over.
  void scrollByPixels(double pixels) =>
      scrollBy(pixels / pixelsPerSecond.value);

  /// Brings [time] into view, with a little room around it. For anything
  /// that moves the playhead while the sheet is zoomed in.
  void revealTime(double time) {
    final span = visibleSpan;
    if (span <= 0) return;
    final margin = span * 0.1;
    if (time < scrollTime.value + margin) {
      scrollTo(time - margin);
    } else if (time > scrollTime.value + span - margin) {
      scrollTo(time - span + margin);
    }
  }

  /// Zooms so the whole timeline fits [width] pixels.
  void zoomToFit(double width) {
    final d = duration <= 0 ? 1.0 : duration;
    pixelsPerSecond.value = ((width - 32) / d).clamp(
      TimelineSession.minZoom,
      TimelineSession.maxZoom,
    );
    scrollTime.value = 0;
  }

  /// Zooms by [factor] keeping the time under [anchorX] (pixels from the
  /// sheet's left edge) where it is.
  void zoomAround(double factor, double anchorX) {
    final before = pixelsPerSecond.value;
    final after = (before * factor).clamp(
      TimelineSession.minZoom,
      TimelineSession.maxZoom,
    );
    final time = scrollTime.value + anchorX / before;
    pixelsPerSecond.value = after;
    // Clamped after the zoom: pulling back can leave the sheet past the end.
    scrollTo(time - anchorX / after);
  }

  bool get isPreviewing => _playback != null;

  /// The value [field] of [component] has in the scene — not what a preview
  /// is showing. Null when the preview has not touched it.
  Object? authoredValue(Component component, FieldDefinition field) =>
      _authored[component]?[field];

  bool isPreviewed(Component component, FieldDefinition field) =>
      _authored[component]?.containsKey(field) ?? false;

  Entity? _resolve(TrackBinding binding) =>
      binding.resolve(scope.world, _owner);

  /// Moves the playhead to [time] and shows the timeline there.
  void scrubTo(double time) => _scrub(time, refresh: true);

  void _scrub(double time, {required bool refresh}) {
    final current = asset.value;
    if (current == null || !time.isFinite) return;
    playhead.value = time.clamp(0.0, current.duration).toDouble();
    if (!isAuthoring()) return;
    if (_previewStale) _restartPreview();
    final playback = _playback ??= _startPreview(current);
    playback.seek(playhead.value);
    _afterSeek();
    if (refresh) scope.sceneState.refresh();
  }

  // What the preview shows now is what an edit is told apart from.
  void _afterSeek() {
    _shown.clear();
    for (final MapEntry(key: component, value: fields) in _authored.entries) {
      _shown[component] = Map.identity()
        ..addEntries([
          for (final field in fields.keys)
            MapEntry(field, field.encodeFrom(component)),
        ]);
    }
    _captureExpected();
  }

  TimelinePlayback _startPreview(TimelineAsset current) {
    // What is done from here on is one step of the editor's undo of its
    // own, not folded into one made before the preview.
    if (!_rebuilding) scope.history.breakMerge();
    var owner = _owner;
    if (owner == null) {
      final scratch = _scratchOwner;
      owner = scratch != null && scratch.isAlive
          ? scratch
          : (_scratchOwner = scope.world.createEntity(name: ''));
    }
    final player = _owner?.getComponent<TimelinePlayerComponent>();
    player?.suspended = true;
    return TimelinePlayback(
      current,
      world: scope.world,
      owner: owner,
      isPreview: true,
      loader: _readTimeline,
      onWillWrite: (component, field) {
        final fields = _authored.putIfAbsent(component, () => Map.identity());
        fields.putIfAbsent(field, () => field.encodeFrom(component));
      },
    );
  }

  // Runs [body] with the preview being ended and started again rather than
  // for good; see [_rebuilding].
  void _quietly(void Function() body) {
    final was = _rebuilding;
    _rebuilding = true;
    try {
      body();
    } finally {
      _rebuilding = was;
    }
  }

  // Ends the preview and starts it again at once, over what the scene
  // holds now: after the scene changed under it.
  void _restartPreview() {
    if (_playback == null) return;
    _quietly(() {
      _endPreview();
      final current = asset.value;
      if (current == null || !isAuthoring()) return;
      _playback = _startPreview(current)..seek(playhead.value);
      _afterSeek();
    });
    if (_playback == null) _destroyScratch();
  }

  void _destroyScratch() {
    final scratch = _scratchOwner;
    if (scratch == null) return;
    _scratchOwner = null;
    if (scratch.isAlive) scope.world.destroyEntity(scratch);
  }

  Future<TimelineAsset> _readTimeline(String file) async => TimelineAsset.parse(
    await PackageAssetPaths.of(root).file(file).readAsString(),
    kinds: scope.context.trackKinds,
    migrations: scope.context.migrations,
  );

  void play() {
    if (asset.value == null) return;
    final range = workRange.value;
    if (range != null &&
        (playhead.value < range.$1 || playhead.value >= range.$2)) {
      scrubTo(range.$1);
    } else if (playhead.value >= duration) {
      scrubTo(0);
    }
    isPlaying.value = true;
  }

  void pause() {
    if (!isPlaying.value) return;
    isPlaying.value = false;
    // What the panels show caught up with the last frame played.
    scope.sceneState.refresh();
  }

  /// Stops, rewinds, and puts the world back as authored.
  void stop() {
    isPlaying.value = false;
    playhead.value = 0;
    endPreview();
  }

  bool _refreshDue() {
    if (!isPlaying.value) return true;
    if (_sinceRefresh.isRunning && _sinceRefresh.elapsedMilliseconds < 80) {
      return false;
    }
    _sinceRefresh
      ..reset()
      ..start();
    return true;
  }

  /// A frame of playing: called by whoever owns a ticker.
  void tick(double deltaTime) {
    final current = asset.value;
    if (current == null || !isPlaying.value) return;
    var next = playhead.value + deltaTime;
    final range = workRange.value;
    if (range != null) {
      // A work range always loops: it is for looking at one part.
      if (next >= range.$2) {
        next = range.$1 + (next - range.$2) % (range.$2 - range.$1);
      }
    } else if (next >= current.duration) {
      if (current.wrap == TimelineWrap.once) {
        next = current.duration;
        isPlaying.value = false;
      } else {
        next %= current.duration;
      }
    }
    _scrub(next, refresh: _refreshDue());
    // Zoomed in, the playhead would otherwise run off the right edge.
    revealTime(next);
  }

  void stepFrames(int frames) {
    pause();
    scrubTo((frameOf(playhead.value) + frames) / fps);
    revealTime(playhead.value);
  }

  void _endPreview() {
    final playback = _playback;
    if (playback == null) {
      if (!_rebuilding) _destroyScratch();
      return;
    }
    _playback = null;
    playback.dispose();
    for (final entry in _authored.entries) {
      for (final field in entry.value.entries) {
        field.key.decodeInto(entry.key, field.value);
      }
    }
    _authored.clear();
    _shown.clear();
    _previewStale = false;
    // Nothing is shown any more, so there is nothing to compare with.
    _expected.clear();
    _owner?.getComponent<TimelinePlayerComponent>()?.suspended = false;
    if (_rebuilding) return;
    _destroyScratch();
    // The scope is going, and its history and scene state with it.
    if (_disposed) return;
    // What is done from here on is the scene's own, not folded into a step
    // made while the preview showed.
    scope.history.breakMerge();
    scope.sceneState.refresh();
  }

  void _noteHistory() {
    final undo = scope.history.undoEntries, redo = scope.history.redoEntries;
    _lastTop = undo.isEmpty ? null : undo.last;
    _lastRedoTop = redo.isEmpty ? null : redo.last;
    _lastRedoDepth = redo.length;
  }

  void _onHistory() {
    final undo = scope.history.undoEntries, redo = scope.history.redoEntries;
    final top = undo.isEmpty ? null : undo.last;
    final redoTop = redo.isEmpty ? null : redo.last;
    EditorCommand? undone, redone;
    if (redoTop != null &&
        redo.length == _lastRedoDepth + 1 &&
        identical(redoTop, _lastTop)) {
      undone = redoTop;
    } else if (top != null &&
        redo.length == _lastRedoDepth - 1 &&
        identical(top, _lastRedoTop)) {
      redone = top;
    }
    _lastTop = top;
    _lastRedoTop = redoTop;
    _lastRedoDepth = redo.length;
    if (undone != null) {
      _replayed(undone, undo: true);
    } else if (redone != null) {
      _replayed(redone, undo: false);
    } else if (top != null && redo.isEmpty && _playback != null) {
      _madeWhilePreviewing(top);
    }
  }

  // [step] was just done while the preview showed: what it changed of what
  // the preview shows is remembered with the scene's values.
  void _madeWhilePreviewing(EditorCommand step) {
    if (_othersHold()) return;
    final edits = <(Component, FieldDefinition, Object?)>[];
    for (final MapEntry(key: component, value: fields) in _authored.entries) {
      final shown = _shown[component];
      if (shown == null) continue;
      for (final field in fields.keys) {
        if (!shown.containsKey(field)) continue;
        final live = field.encodeFrom(component);
        if (!TimelineSession._sameSaved(live, shown[field])) {
          edits.add((component, field, live));
        }
      }
    }
    if (edits.isEmpty) return;
    final taint = _tainted[step] ??= Map.identity();
    for (final (component, field, live) in edits) {
      final authored = _authored[component]!;
      final fields = taint.putIfAbsent(component, () => Map.identity());
      final was = authored[field];
      final before = fields.containsKey(field) ? fields[field]!.$1 : was;
      if (record.value) {
        // Recording: the edit becomes a key, and the scene keeps its value.
        fields[field] = (before, was);
      } else {
        // Not recording: the edit is the scene's own, kept when the
        // preview ends.
        final shown = _shown[component]!;
        final now = _authoredAfterEdit(
          component,
          field,
          was,
          shown[field],
          live,
        );
        fields[field] = (before, now);
        authored[field] = now;
        shown[field] = live;
        _previewStale = true;
      }
    }
  }

  // What the scene holds for [field] once the author, with Recording off,
  // changed what the preview showed from [shown] to [live]: a channel a
  // relative track moves keeps its offset — the thing was moved by so
  // much — and the rest takes what was put there.
  Object? _authoredAfterEdit(
    Component component,
    FieldDefinition field,
    Object? authored,
    Object? shown,
    Object? live,
  ) {
    final relative = <String>{
      for (final t in asset.value?.propertyTracks ?? const <PropertyTrack>[])
        if (t.isRelative && t.field == field.name && _moves(t, component))
          t.channel,
    };
    if (relative.isEmpty) return live;
    num? moved(Object? a, Object? s, Object? l) =>
        a is num && s is num && l is num ? a + (l - s) : null;
    if (live is Map && authored is Map && shown is Map) {
      return <String, dynamic>{
        for (final MapEntry(:key, :value) in live.entries)
          '$key': relative.contains(key)
              ? (moved(authored[key], shown[key], value) ?? value)
              : value,
      };
    }
    if (relative.contains('')) return moved(authored, shown, live) ?? live;
    return live;
  }

  // Whether [track] animates [component].
  bool _moves(PropertyTrack track, Component component) {
    final entity = track.binding.isSelf
        ? (_owner ?? _scratchOwner)
        : _resolve(track.binding);
    if (entity == null) return false;
    return identical(
      PropertyAccess.of(entity, track.component, track.field)?.component,
      component,
    );
  }

  // [step] of the editor's history was just undone ([undo]) or redone.
  void _replayed(EditorCommand step, {required bool undo}) {
    final taint = _tainted[step];
    final previewing = _playback != null;
    if (taint != null) {
      for (final MapEntry(key: component, value: fields) in taint.entries) {
        for (final MapEntry(key: field, value: values) in fields.entries) {
          final value = undo ? values.$1 : values.$2;
          final authored = _authored[component];
          if (previewing && authored != null && authored.containsKey(field)) {
            authored[field] = value;
          } else {
            field.decodeInto(component, value);
          }
        }
      }
    }
    if (!previewing) return;
    // Whatever else the step put in a field the preview shows is the
    // scene's own value now: an edit made before the preview, undone
    // while it shows.
    for (final MapEntry(key: component, value: fields) in _authored.entries) {
      final shown = _shown[component];
      if (shown == null) continue;
      for (final field in fields.keys.toList()) {
        if (taint?[component]?.containsKey(field) ?? false) continue;
        if (!shown.containsKey(field)) continue;
        final live = field.encodeFrom(component);
        if (!TimelineSession._sameSaved(live, shown[field])) {
          fields[field] = live;
        }
      }
    }
    // Shown again over what the scene now holds — and none of it is an
    // edit for Record to key.
    _restartPreview();
  }

  /// Lets go of the scope, which disposes it with itself ([of]): a preview
  /// that shows ends — the world holds the scene's values again — nothing
  /// of the scope's is watched any more, and its own signals let go of
  /// whatever still watched them.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    endPreview();
    _destroyScratch();
    _stopHistory?.call();
    _stopHistory = null;
    scope.authoredStateGuards.remove(endPreview);
    scope.authoredStateHeld.remove(_previewing);
    for (final signal in <Signal<Object?>>[
      asset,
      isDirty,
      revision,
      message,
      opened,
      playhead,
      isPlaying,
      pixelsPerSecond,
      scrollTime,
      selection,
      selectedTrack,
      snap,
      showFrames,
      workRange,
      showCurves,
      record,
      viewWidth,
    ]) {
      signal.dispose();
    }
  }
}
