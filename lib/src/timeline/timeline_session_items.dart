part of 'timeline_session.dart';

/// The timeline's tracks and the items on them — blocks, events, keys —
/// one at a time or many at once.
extension TimelineSessionItems on TimelineSession {
  // ── Tracks ───────────────────────────────────────────────────────────────

  void addTrack(TimelineTrack track) {
    final current = asset.value;
    if (current == null || !_mayEdit()) return;
    apply('Add track', current.copyWith(tracks: [...current.tracks, track]));
    selectedTrack.value = current.tracks.length;
  }

  void removeTrack(int index) {
    final current = asset.value;
    if (current == null || index < 0 || index >= current.tracks.length) return;
    if (!_mayEdit()) return;
    selection.value = const {};
    selectedTrack.value = null;
    apply(
      'Remove track',
      current.copyWith(
        tracks: [
          for (var i = 0; i < current.tracks.length; i++)
            if (i != index) current.tracks[i],
        ],
      ),
    );
  }

  void replaceTrack(int index, TimelineTrack track, String label) {
    final current = asset.value;
    if (current == null) return;
    apply(label, current.withTrackAt(index, track));
  }

  /// Switches the [index]th property track between absolute keys — the
  /// field's values — and relative ones — offsets from the value the scene
  /// has — as one undo step, converting each number key by the scene's
  /// value so the animation plays where it did. A colour track is never
  /// relative, and one whose entity or field is not in the scene has no
  /// value to convert by: only the mode changes.
  void switchTrackMode(int index) {
    final current = asset.value;
    if (current == null || index < 0 || index >= current.tracks.length) return;
    final track = current.tracks[index];
    if (track is! PropertyTrack) return;
    final toRelative = !track.isRelative;
    final base = track.isColor ? null : _sceneChannelOf(track);
    replaceTrack(
      index,
      track.copyWith(
        mode: toRelative
            ? PropertyTrackMode.relative
            : PropertyTrackMode.absolute,
        curve: base == null
            ? track.curve
            : KeyCurve([
                for (final k in track.curve.keys)
                  if (k.value case final num v)
                    k.copyWith(value: toRelative ? v - base : v + base)
                  else
                    k,
              ]),
      ),
      'Track mode',
    );
  }

  // The number [track]'s channel holds in the scene — not what a preview
  // shows; null when its entity or field is not there, or it is no number.
  num? _sceneChannelOf(PropertyTrack track) {
    final entity = track.binding.isSelf
        ? (_owner ?? _scratchOwner)
        : _resolve(track.binding);
    if (entity == null) return null;
    final access = PropertyAccess.of(
      entity,
      track.component,
      track.field,
      track.channel,
    );
    if (access == null) return null;
    final value = isPreviewed(access.component, access.field)
        ? TimelineSession._channelOf(
            authoredValue(access.component, access.field),
            track.channel,
          )
        : access.read();
    return value is num ? value : null;
  }

  /// A property track for every channel of [field], bound to [binding].
  /// Tracks that exist already are left alone. Self-bound transform tracks
  /// start relative, so the timeline can be reused; the rest absolute.
  void addPropertyTracks(
    TrackBinding binding,
    String componentType,
    FieldDefinition field,
  ) {
    final current = asset.value;
    if (current == null) return;
    final relative =
        binding.isSelf &&
        componentType == 'TransformComponent' &&
        field.name == 'position';
    final added = <TimelineTrack>[
      for (final channel in _shownChannels(componentType, field))
        if (!current.propertyTracks.any(
          (t) =>
              t.binding == binding &&
              t.component == componentType &&
              t.field == field.name &&
              t.channel == channel,
        ))
          PropertyTrack(
            component: componentType,
            field: field.name,
            channel: channel,
            binding: binding,
            isColor: field.kind.id == 'color',
            mode: relative
                ? PropertyTrackMode.relative
                : PropertyTrackMode.absolute,
          ),
    ];
    if (added.isEmpty) return;
    apply('Add track', current.copyWith(tracks: [...current.tracks, ...added]));
  }

  // ── Items ────────────────────────────────────────────────────────────────

  /// The time of [ref], or null when it points at nothing.
  double? timeOf(TimelineItemRef ref) {
    final tracks = asset.value?.tracks;
    if (tracks == null || ref.track < 0 || ref.track >= tracks.length) {
      return null;
    }
    final track = tracks[ref.track];
    final i = ref.index;
    if (i < 0) return null;
    if (track is PropertyTrack) {
      return i < track.curve.keys.length ? track.curve.keys[i].time : null;
    }
    if (track is EventTrack) {
      return i < track.events.length ? track.events[i].time : null;
    }
    if (track is BlockTrack) {
      return i < track.blocks.length ? track.blocks[i].start : null;
    }
    return null;
  }

  /// How many items the [index]th track has.
  int itemCount(int index) {
    final track = asset.value?.tracks[index];
    return switch (track) {
      PropertyTrack t => t.curve.keys.length,
      EventTrack t => t.events.length,
      BlockTrack t => t.blocks.length,
      _ => 0,
    };
  }

  /// The value a new key at [time] on a property track starts with: what the
  /// curve already says there, else the field's value now (zero offset for a
  /// relative track).
  Object valueForNewKey(int trackIndex, double time) {
    final track = asset.value!.tracks[trackIndex] as PropertyTrack;
    final onCurve = track.curve.valueAt(
      time,
      isColor: track.isColor,
      easings: scope.context.easings,
    );
    if (onCurve != null) return onCurve;
    if (track.isRelative) return 0.0;
    final entity = _resolve(track.binding);
    final live = entity == null
        ? null
        : PropertyAccess.of(
            entity,
            track.component,
            track.field,
            track.channel,
          )?.read();
    return live ?? (track.isColor ? 0xFFFFFFFF : 0.0);
  }

  /// Adds a key at [time] (or replaces the one there). Returns where it is.
  TimelineItemRef? setKey(int trackIndex, double time, {Object? value}) {
    final current = asset.value;
    if (current == null || !_mayEdit()) return null;
    final track = current.tracks[trackIndex];
    if (track is! PropertyTrack || track.locked) return null;
    final at = snapTime(time);
    final v = value ?? valueForNewKey(trackIndex, at);
    final key = TimelineKey(
      time: at,
      value: v,
      // What cannot blend — a flag, a name, a path — holds until the next.
      interpolation: v is num ? KeyInterpolation.bezier : KeyInterpolation.step,
    );
    final curve = track.curve.withKey(key, isColor: track.isColor);
    apply('Key', current.withTrackAt(trackIndex, track.copyWith(curve: curve)));
    final index = curve.keys.indexWhere((k) => (k.time - at).abs() < 1e-6);
    return TimelineItemRef(trackIndex, index);
  }

  /// Replaces the key at [ref]. A key moved onto another's time takes its
  /// place: a track never holds two keys at one time.
  void updateKey(TimelineItemRef ref, TimelineKey key, {String label = 'Key'}) {
    final current = asset.value;
    final track = current?.tracks[ref.track];
    if (current == null || track is! PropertyTrack || track.locked) return;
    final keys = [
      for (final (i, k) in track.curve.keys.indexed)
        if (i == ref.index) key else if ((k.time - key.time).abs() >= 1e-6) k,
    ];
    apply(
      label,
      current.withTrackAt(
        ref.track,
        track.copyWith(
          curve: KeyCurve(keys).withAutoTangents(isColor: track.isColor),
        ),
      ),
    );
  }

  TimelineItemRef? addEvent(int trackIndex, double time, String name) {
    final current = asset.value;
    final track = current?.tracks[trackIndex];
    if (current == null || track is! EventTrack || track.locked) return null;
    if (!_mayEdit()) return null;
    final at = snapTime(time);
    final next = track.copyWith(
      events: [
        ...track.events,
        TimelineEvent(time: at, name: name),
      ],
    );
    apply('Event', current.withTrackAt(trackIndex, next));
    return TimelineItemRef(
      trackIndex,
      next.events.indexWhere((e) => e.time == at && e.name == name),
    );
  }

  /// Replaces the event at [ref]; the selection follows it.
  void updateEvent(TimelineItemRef ref, TimelineEvent event) {
    final current = asset.value;
    final track = current?.tracks[ref.track];
    if (current == null || track is! EventTrack || track.locked) return;
    if (!_mayEdit()) return;
    final next = track.copyWith(
      events: List.of(track.events)..[ref.index] = event,
    );
    apply('Event', current.withTrackAt(ref.track, next));
    final index = next.events.indexOf(event);
    if (index >= 0) selection.value = {TimelineItemRef(ref.track, index)};
  }

  /// Replaces the block at [ref]; the selection follows it.
  void updateBlock(TimelineItemRef ref, TimelineBlock block) {
    final current = asset.value;
    final track = current?.tracks[ref.track];
    if (current == null || track is! BlockTrack || track.locked) return;
    if (!_mayEdit()) return;
    final next = track.rebuild(
      blocks: List.of(track.blocks)..[ref.index] = _fitted(block, current),
    );
    apply('Block', current.withTrackAt(ref.track, next));
    final index = next.blocks.indexWhere(
      (b) => b.start == block.start && b.value == block.value,
    );
    if (index >= 0) selection.value = {TimelineItemRef(ref.track, index)};
  }

  // A block starts inside the timeline and is at least a frame long.
  TimelineBlock _fitted(TimelineBlock block, TimelineAsset within) {
    final least = within.fps > 0 ? 1 / within.fps : 0.01;
    final start = block.start.clamp(0.0, within.duration).toDouble();
    return block.copyWith(
      start: start,
      length: block.length < least ? least : block.length,
    );
  }

  /// A frame of dragging one edge of the block at [ref] in [start] to
  /// [time]: the other edge stays put. See [dragItems].
  ///
  /// A block that sits at or past the timeline's end (the end was dragged
  /// in over it), or is shorter than a frame (the frame rate went down),
  /// is trimmed as far as it can be rather than refused.
  TimelineItemRef dragTrim(
    TimelineAsset start,
    TimelineItemRef ref,
    double time, {
    required bool leadingEdge,
  }) {
    final track = start.tracks[ref.track];
    if (track is! BlockTrack || track.locked) return ref;
    final block = track.blocks[ref.index];
    final least = start.fps > 0 ? 1 / start.fps : 0.01;
    final at = snapTime(time);
    final TimelineBlock trimmed;
    if (leadingEdge) {
      final from = at.clamp(0.0, math.max(0.0, block.end - least)).toDouble();
      trimmed = block.copyWith(start: from, length: block.end - from);
    } else {
      final room = start.duration - block.start;
      final most = room >= least ? room : math.max(least, block.length);
      trimmed = block.copyWith(
        length: (at - block.start).clamp(least, most).toDouble(),
      );
    }
    final next = track.rebuild(
      blocks: List.of(track.blocks)..[ref.index] = trimmed,
    );
    _set(start.withTrackAt(ref.track, next));
    final moved = TimelineItemRef(ref.track, next.blocks.indexOf(trimmed));
    selection.value = {moved};
    return moved;
  }

  TimelineItemRef? addBlock(int trackIndex, double time) {
    final current = asset.value;
    final track = current?.tracks[trackIndex];
    if (current == null || track is! BlockTrack || track.locked) return null;
    if (!_mayEdit()) return null;
    final at = snapTime(time);
    final block = track.defaultBlock.copyWith(start: at);
    final next = track.rebuild(blocks: [...track.blocks, block]);
    apply('Block', current.withTrackAt(trackIndex, next));
    return TimelineItemRef(trackIndex, next.blocks.indexOf(block));
  }

  /// Removes [refs] (on tracks that are not locked).
  void removeItems(Set<TimelineItemRef> refs) {
    final current = asset.value;
    if (current == null || refs.isEmpty || !_mayEdit()) return;
    final tracks = List.of(current.tracks);
    for (var t = 0; t < tracks.length; t++) {
      final gone = {
        for (final r in refs)
          if (r.track == t) r.index,
      };
      if (gone.isEmpty || tracks[t].locked) continue;
      tracks[t] = TimelineSession._mapItems(
        tracks[t],
        (i, _) => gone.contains(i) ? null : 0.0,
      );
    }
    selection.value = const {};
    apply('Delete', current.copyWith(tracks: tracks));
  }

  /// [base] with [refs] moved by [delta] seconds — clamped so none leaves
  /// the timeline, snapped as a group — and where those items are now.
  (TimelineAsset, Set<TimelineItemRef>) _shifted(
    TimelineAsset base,
    Set<TimelineItemRef> refs,
    double delta,
  ) {
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final r in refs) {
      final t = TimelineSession._timeIn(base, r);
      if (t == null) continue;
      if (t < lo) lo = t;
      if (t > hi) hi = t;
    }
    if (lo == double.infinity) return (base, refs);
    final room = base.duration - hi;
    final shift = snapTime(lo + delta.clamp(-lo, room < 0 ? 0.0 : room)) - lo;

    final moved = <TimelineItemRef>{};
    final tracks = List.of(base.tracks);
    for (var t = 0; t < tracks.length; t++) {
      final mine = {
        for (final r in refs)
          if (r.track == t) r.index,
      };
      if (mine.isEmpty) continue;
      if (tracks[t].locked) {
        moved.addAll(refs.where((r) => r.track == t));
        continue;
      }
      // The items re-sort, so each moved one is found again by its new time.
      final landed = <double>[];
      tracks[t] = TimelineSession._mapItems(tracks[t], (i, time) {
        if (!mine.contains(i)) return 0.0;
        landed.add(time + shift);
        return shift;
      }, replaceAt: true);
      for (final time in landed) {
        final index = TimelineSession._indexAt(tracks[t], time);
        if (index >= 0) moved.add(TimelineItemRef(t, index));
      }
    }
    return (base.copyWith(tracks: tracks), moved);
  }

  /// Moves [refs] by [delta] seconds as one undo step; returns where they
  /// are now.
  Set<TimelineItemRef> moveItems(Set<TimelineItemRef> refs, double delta) {
    final current = asset.value;
    if (current == null || refs.isEmpty || !_mayEdit()) return refs;
    final (next, moved) = _shifted(current, refs, delta);
    apply('Move', next);
    selection.value = moved;
    return moved;
  }

  /// A drag begins. The timeline as it is now comes back: every frame of
  /// the drag ([dragItems], [dragKeys], [dragMarker]…) is measured from it,
  /// and the whole drag is one undo step called [label]. Null when the
  /// timeline cannot be changed now.
  TimelineAsset? beginDrag({String label = 'Move'}) {
    final current = asset.value;
    if (current == null || !_mayEdit()) return null;
    _lastRecord = null;
    _undo.add(_Step(label, current));
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
    return current;
  }

  /// A frame of a drag: [refs] of [start] moved by [delta] in all.
  Set<TimelineItemRef> dragItems(
    TimelineAsset start,
    Set<TimelineItemRef> refs,
    double delta,
  ) {
    final (next, moved) = _shifted(start, refs, delta);
    _set(next);
    selection.value = moved;
    return moved;
  }

  /// The drag is over. One that went nowhere leaves no undo step.
  void endDrag(TimelineAsset start) {
    final current = asset.value;
    final unchanged = current != null && current.encode() == start.encode();
    if (!unchanged) return;
    if (_undo.isNotEmpty && identical(_undo.last.asset, start)) {
      _undo.removeLast();
    }
  }

  // ── Editing many at once ─────────────────────────────────────────────────

  /// Moves the selection by whole [frames].
  void nudge(int frames) {
    if (selection.value.isEmpty || fps <= 0) return;
    final wasSnapping = snap.value;
    // A nudge is a frame whether or not dragging snaps.
    snap.value = true;
    moveItems(selection.value, frames / fps);
    snap.value = wasSnapping;
  }

  /// [base] with [refs] stretched in time by [factor] about [pivot], and
  /// where they are now. Items are kept inside the timeline.
  (TimelineAsset, Set<TimelineItemRef>) _scaled(
    TimelineAsset base,
    Set<TimelineItemRef> refs,
    double factor,
    double pivot,
  ) {
    final moved = <TimelineItemRef>{};
    final tracks = List.of(base.tracks);
    for (var t = 0; t < tracks.length; t++) {
      final mine = {
        for (final r in refs)
          if (r.track == t) r.index,
      };
      if (mine.isEmpty) continue;
      if (tracks[t].locked) {
        moved.addAll(refs.where((r) => r.track == t));
        continue;
      }
      final landed = <double>[];
      tracks[t] = TimelineSession._mapItems(tracks[t], (i, time) {
        if (!mine.contains(i)) return 0.0;
        final to = snapTime(pivot + (time - pivot) * factor);
        landed.add(to);
        return to - time;
      }, replaceAt: true);
      for (final time in landed) {
        final index = TimelineSession._indexAt(tracks[t], time);
        if (index >= 0) moved.add(TimelineItemRef(t, index));
      }
    }
    return (base.copyWith(tracks: tracks), moved);
  }

  /// Stretches the selection in time by [factor] about its first item, as
  /// one undo step.
  Set<TimelineItemRef> scaleItems(Set<TimelineItemRef> refs, double factor) {
    final current = asset.value;
    final span = current == null ? null : TimelineSession._span(current, refs);
    if (current == null || span == null || factor <= 0) return refs;
    if (!_mayEdit()) return refs;
    final (next, moved) = _scaled(current, refs, factor, span.$1);
    apply('Scale', next);
    selection.value = moved;
    return moved;
  }

  /// A frame of a scaling drag; see [dragItems].
  Set<TimelineItemRef> dragScale(
    TimelineAsset start,
    Set<TimelineItemRef> refs,
    double factor,
  ) {
    final span = TimelineSession._span(start, refs);
    if (span == null || factor <= 0) return refs;
    final (next, moved) = _scaled(start, refs, factor, span.$1);
    _set(next);
    selection.value = moved;
    return moved;
  }

  bool get canPaste => _clipboard.isNotEmpty;

  // What kind of item [track] takes: a key of a colour, a number, a flag or
  // a name; an event; a block of its own kind.
  String _kindOfTrack(TimelineTrack track) => switch (track) {
    PropertyTrack t => 'key:${_valueKindOf(t)}',
    EventTrack _ => 'event',
    BlockTrack _ => 'block:${track.runtimeType}',
    _ => 'other:${track.runtimeType}',
  };

  String _valueKindOf(PropertyTrack track) {
    if (track.isColor) return 'color';
    if (track.curve.keys.isNotEmpty) {
      return switch (track.curve.keys.first.value) {
        num _ => 'number',
        bool _ => 'bool',
        _ => 'text',
      };
    }
    // An empty track: what its field holds.
    final field = scope.definitions
        .definitionByType(track.component)
        ?.field(track.field);
    final kind = field?.kind;
    if (kind == null) return 'number';
    if (kind.id == 'color') return 'color';
    if (kind.id == 'boolean') return 'bool';
    if (kind is EnumFieldType ||
        const {
          'text',
          'assetRef',
          'entityRef',
          'enumeration',
          'enum',
        }.contains(kind.id)) {
      return 'text';
    }
    return 'number';
  }

  /// Copies the selection.
  void copy() {
    final current = asset.value;
    final span = current == null
        ? null
        : TimelineSession._span(current, selection.value);
    if (current == null || span == null) return;
    _clipboard.clear();
    for (final r in selection.value) {
      final track = current.tracks[r.track];
      final Object? item = switch (track) {
        PropertyTrack t => t.curve.keys[r.index],
        EventTrack t => t.events[r.index],
        BlockTrack t => t.blocks[r.index],
        _ => null,
      };
      final time = TimelineSession._timeIn(current, r);
      if (item != null && time != null) {
        _clipboard.add(
          _Copied(
            r.track,
            TimelineSession._signatureOf(track),
            _kindOfTrack(track),
            time - span.$1,
            item,
          ),
        );
      }
    }
  }

  /// Pastes at [time] (the playhead by default). What was copied from one
  /// track goes to the selected track when it holds the same kind of thing —
  /// a number's keys onto a number, a colour's onto a colour; that is how
  /// keys get from one field, or one entity, to another. Otherwise each
  /// item goes back to the track it came from, found by what that track is
  /// (in this timeline or another); an item with nowhere to go is left out.
  Set<TimelineItemRef> paste({double? time}) {
    final current = asset.value;
    if (current == null || _clipboard.isEmpty || !_mayEdit()) return const {};
    final at = snapTime(time ?? playhead.value);
    final sources = {for (final c in _clipboard) c.signature};
    final target = selectedTrack.value;
    int? trackFor(_Copied copied) {
      if (sources.length == 1 &&
          target != null &&
          target >= 0 &&
          target < current.tracks.length &&
          _kindOfTrack(current.tracks[target]) == copied.kind) {
        return target;
      }
      if (copied.track < current.tracks.length &&
          TimelineSession._signatureOf(current.tracks[copied.track]) ==
              copied.signature) {
        return copied.track;
      }
      final found = current.tracks.indexWhere(
        (t) => TimelineSession._signatureOf(t) == copied.signature,
      );
      return found < 0 ? null : found;
    }

    final tracks = List.of(current.tracks);
    final pasted = <(int, double)>[];
    for (final copied in _clipboard) {
      final t = trackFor(copied);
      if (t == null || tracks[t].locked) continue;
      if (_kindOfTrack(tracks[t]) != copied.kind) continue;
      final to = at + copied.offset;
      if (to > current.duration + 1e-9) continue;
      final track = tracks[t];
      final item = copied.item;
      if (track is PropertyTrack && item is TimelineKey) {
        tracks[t] = track.copyWith(
          curve: track.curve.withKey(
            item.copyWith(time: to),
            isColor: track.isColor,
          ),
        );
      } else if (track is EventTrack && item is TimelineEvent) {
        tracks[t] = track.copyWith(
          events: [
            ...track.events,
            item.copyWith(time: to),
          ],
        );
      } else if (track is BlockTrack && item is TimelineBlock) {
        tracks[t] = track.rebuild(
          blocks: [
            ...track.blocks,
            item.copyWith(start: to),
          ],
        );
      } else {
        continue;
      }
      pasted.add((t, to));
    }
    if (pasted.isEmpty) return const {};
    apply('Paste', current.copyWith(tracks: tracks));
    final refs = {
      for (final (t, to) in pasted)
        if (TimelineSession._indexAt(tracks[t], to) case final i when i >= 0)
          TimelineItemRef(t, i),
    };
    selection.value = refs;
    return refs;
  }

  /// Copies the selection to just after itself.
  Set<TimelineItemRef> duplicate() {
    final current = asset.value;
    final span = current == null
        ? null
        : TimelineSession._span(current, selection.value);
    if (current == null || span == null) return const {};
    copy();
    final step = fps > 0 ? 1 / fps : 0.0;
    final wasSelected = selectedTrack.value;
    // Back where they came from, not onto the selected track.
    selectedTrack.value = null;
    final refs = paste(time: span.$2 + step);
    selectedTrack.value = wasSelected;
    return refs;
  }

  /// Removes [refs] and pulls what comes after them, on the same tracks, in
  /// to close the gap.
  void rippleDelete(Set<TimelineItemRef> refs) {
    final current = asset.value;
    if (current == null || refs.isEmpty || !_mayEdit()) return;
    final tracks = List.of(current.tracks);
    for (var t = 0; t < tracks.length; t++) {
      final gone = {
        for (final r in refs)
          if (r.track == t) r.index,
      };
      if (gone.isEmpty || tracks[t].locked) continue;
      final times = [
        for (var i = 0; i < itemCount(t); i++)
          TimelineSession._timeIn(current, TimelineItemRef(t, i))!,
      ];
      final firstGone = gone
          .map((i) => times[i])
          .reduce((a, b) => a < b ? a : b);
      final lastGone = gone
          .map((i) => times[i])
          .reduce((a, b) => a > b ? a : b);
      // The next thing left standing after the hole slides back to where
      // the hole began.
      double? next;
      for (var i = 0; i < times.length; i++) {
        if (!gone.contains(i) && times[i] > lastGone) {
          next = next == null || times[i] < next ? times[i] : next;
        }
      }
      final gap = next == null ? 0.0 : next - firstGone;
      tracks[t] = TimelineSession._mapItems(tracks[t], (i, time) {
        if (gone.contains(i)) return null;
        return time > lastGone ? -gap : 0.0;
      });
    }
    selection.value = const {};
    apply('Ripple delete', current.copyWith(tracks: tracks));
  }
}
