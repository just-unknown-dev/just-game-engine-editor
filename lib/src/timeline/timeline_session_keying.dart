part of 'timeline_session.dart';

/// Keying a field from anywhere in the editor, and the motion paths drawn
/// in the level.
extension TimelineSessionKeying on TimelineSession {
  void setRecording(bool on) {
    if (asset.value == null) return;
    if (on && !_mayEdit()) return;
    record.value = on;
    // Recording compares the world with what the timeline shows, so there
    // has to be something shown.
    if (on) scrubTo(playhead.value);
  }

  /// How [entity] is bound from this timeline: as "self" when it is the
  /// owner, else by its name; null when it has no name to be bound by.
  TrackBinding? bindingFor(Entity entity) {
    if (identical(entity, _owner)) return TrackBinding.owner;
    final name = entity.name ?? '';
    return name.isEmpty ? null : TrackBinding.name(name);
  }

  /// The entities whose fields recording watches: the owner, and whoever a
  /// track is already bound to.
  Map<Entity, TrackBinding> _watched() {
    final out = <Entity, TrackBinding>{};
    final owner = _owner;
    if (owner != null && owner.isAlive) out[owner] = TrackBinding.owner;
    for (final track in asset.value?.tracks ?? const <TimelineTrack>[]) {
      if (track.binding.isSelf) continue;
      final entity = _resolve(track.binding);
      if (entity != null) out.putIfAbsent(entity, () => track.binding);
    }
    return out;
  }

  Iterable<(Component, ComponentDefinition, FieldDefinition)> _fieldsOf(
    Entity entity,
  ) sync* {
    for (final component in entity.components) {
      final definition = scope.definitions.definitionFor(component);
      if (definition == null ||
          TimelineSession.unrecorded.contains(definition.type)) {
        continue;
      }
      for (final field in definition.fields) {
        if (PropertyAccess.canAnimate(field)) {
          yield (component, definition, field);
        }
      }
    }
  }

  void _captureExpected() {
    _expected.clear();
    if (!record.value) return;
    for (final entity in _watched().keys) {
      for (final (component, _, field) in _fieldsOf(entity)) {
        _expected.putIfAbsent(component, () => Map.identity())[field] = field
            .encodeFrom(component);
      }
    }
  }

  // Whether something other than this preview is showing a value nobody
  // chose yet — a colour picker trying colours out.
  bool _othersHold() =>
      scope.authoredStateHeld.any((held) => held != _previewing && held());

  /// Looks for fields that are no longer what the timeline showed and keys
  /// them at the playhead. Returns how many keys it wrote. Cheap when
  /// nothing changed, so it can be called often.
  ///
  /// Nothing is keyed while a value is only being tried out (a colour
  /// picker's live preview): what the author settles on is.
  int captureEdits() {
    final current = asset.value;
    if (current == null || !record.value || !isAuthoring()) return 0;
    if (_othersHold()) return 0;
    final edits = <_FieldEdit>[];
    for (final MapEntry(key: entity, value: binding) in _watched().entries) {
      for (final (component, definition, field) in _fieldsOf(entity)) {
        final known = _expected[component];
        if (known == null || !known.containsKey(field)) continue;
        final was = known[field], now = field.encodeFrom(component);
        for (final channel in PropertyAccess.channelsOf(field)) {
          final live = TimelineSession._channelOf(now, channel);
          if (live == null ||
              TimelineSession._same(
                TimelineSession._channelOf(was, channel),
                live,
              )) {
            continue;
          }
          edits.add(
            _FieldEdit(
              binding,
              component,
              definition.type,
              field,
              channel,
              live,
              was,
            ),
          );
        }
      }
    }
    if (edits.isEmpty) return 0;
    _keyEdits(current, edits, label: 'Record');
    return edits.length;
  }

  /// The channels of [field] to make tracks for and key: those the scene's
  /// mode shows (a 2-D scene keys a position's x and y, a rotation's z),
  /// or the one value of a field that is one.
  List<String> _shownChannels(String componentType, FieldDefinition field) {
    final all = PropertyAccess.channelsOf(field);
    if (field.kind.channels.isEmpty) return all;
    final hint = scope.definitions
        .definitionByType(componentType)
        ?.hints
        .fields[field.name];
    final shown = SceneModeFilters.visibleChannels(
      field,
      hint,
      scope.sceneState.editingMode,
    );
    return [
      for (final c in all)
        if (shown.contains(c)) c,
    ];
  }

  /// Keys [field] of [entity]'s [component] at the playhead with the value
  /// it has now, making its tracks if there are none: the inspector's key
  /// button. False when [entity] cannot be bound from this timeline.
  bool keyField(Entity entity, Component component, FieldDefinition field) =>
      keyFields(entity, component, [field]);

  /// [keyField] for several fields of one component, as one undo step.
  /// Nothing during a play-test: what the game did is not a key.
  bool keyFields(
    Entity entity,
    Component component,
    List<FieldDefinition> fields,
  ) {
    final current = asset.value;
    final binding = bindingFor(entity);
    final definition = scope.definitions.definitionFor(component);
    if (current == null || binding == null || definition == null) return false;
    if (!isAuthoring() || !_mayEdit()) return false;
    final edits = <_FieldEdit>[];
    for (final field in fields) {
      if (!PropertyAccess.canAnimate(field)) continue;
      final now = field.encodeFrom(component);
      for (final channel in _shownChannels(definition.type, field)) {
        final live = TimelineSession._channelOf(now, channel);
        if (live == null) continue;
        edits.add(
          _FieldEdit(
            binding,
            component,
            definition.type,
            field,
            channel,
            live,
            // Not an edit: the scene's value is the one it has.
            _authored[component]?[field] ?? now,
          ),
        );
      }
    }
    if (edits.isEmpty) return false;
    _keyEdits(current, edits, label: 'Key');
    return true;
  }

  void _keyEdits(
    TimelineAsset current,
    List<_FieldEdit> edits, {
    required String label,
  }) {
    if (!_mayEdit()) return;
    final at = snapTime(playhead.value);
    final tracks = List.of(current.tracks);
    for (final e in edits) {
      var index = tracks.indexWhere(
        (t) =>
            t is PropertyTrack &&
            t.binding == e.binding &&
            t.component == e.componentType &&
            t.field == e.field.name &&
            t.channel == e.channel,
      );
      if (index < 0) {
        tracks.add(
          PropertyTrack(
            component: e.componentType,
            field: e.field.name,
            channel: e.channel,
            binding: e.binding,
            isColor: e.field.kind.id == 'color',
            mode:
                e.binding.isSelf &&
                    e.componentType == 'TransformComponent' &&
                    e.field.name == 'position'
                ? PropertyTrackMode.relative
                : PropertyTrackMode.absolute,
          ),
        );
        index = tracks.length - 1;
      }
      final track = tracks[index] as PropertyTrack;
      if (track.locked) continue;

      // The scene keeps the value it had before the edit; the timeline gets
      // the new one — as an offset from the scene's, for a relative track.
      final authoredField = _authored[e.component]?[e.field] ?? e.was;
      _authored
          .putIfAbsent(e.component, () => Map.identity())
          .putIfAbsent(e.field, () => authoredField);
      Object value = e.live;
      if (track.isRelative && value is num) {
        final base = TimelineSession._channelOf(authoredField, e.channel);
        value = value - (base is num ? base : 0);
      }
      tracks[index] = track.copyWith(
        curve: track.curve.withKey(
          TimelineKey(
            time: at,
            value: value,
            interpolation: value is num
                ? KeyInterpolation.bezier
                : KeyInterpolation.step,
          ),
          isColor: track.isColor,
        ),
      );
    }

    // A drag is many edits to the same fields at the same time: one step.
    final stamp =
        '$label@$at:${edits.map((e) => '${e.binding.label}/${e.componentType}.${e.field.name}.${e.channel}').join(',')}';
    final next = current.copyWith(tracks: tracks);
    // Shown from here on, whether or not it was before.
    _playback ??= _startPreview(current);
    if (_lastRecord == stamp && _undo.isNotEmpty) {
      _set(next);
    } else {
      apply(label, next);
    }
    _lastRecord = stamp;
  }

  /// What the inspector's key button shows for [field]: nothing to do with
  /// this timeline, animated by it, or keyed right at the playhead.
  FieldKeyState keyStateOf(
    Entity entity,
    Component component,
    FieldDefinition field,
  ) {
    final current = asset.value;
    final binding = current == null ? null : bindingFor(entity);
    final type = scope.definitions.definitionFor(component)?.type;
    if (current == null || binding == null || type == null) {
      return FieldKeyState.none;
    }
    var state = FieldKeyState.none;
    for (final t in current.propertyTracks) {
      if (t.binding != binding ||
          t.component != type ||
          t.field != field.name) {
        continue;
      }
      if (t.curve.keys.any((k) => (k.time - playhead.value).abs() < 1e-6)) {
        return FieldKeyState.keyed;
      }
      state = FieldKeyState.animated;
    }
    return state;
  }

  // ── Motion paths ─────────────────────────────────────────────────────────

  /// A frame of dragging a motion path's key dot: the keys at [time] on
  /// [path]'s position tracks in [start] are set so the entity is at [world]
  /// then. A channel with no track is left alone. See [dragItems].
  void dragPathPoint(
    TimelineAsset start,
    MotionPath path,
    double time,
    Offset world,
  ) {
    if (!world.dx.isFinite || !world.dy.isFinite) return;
    final tracks = List.of(start.tracks);
    for (final (index, target, base) in [
      (path.x, world.dx, path.base.dx),
      (path.y, world.dy, path.base.dy),
    ]) {
      if (index == null) continue;
      final track = tracks[index] as PropertyTrack;
      if (track.locked) continue;
      final value = track.isRelative ? target - base : target;
      final at = track.curve.keys.indexWhere(
        (k) => (k.time - time).abs() < 1e-6,
      );
      tracks[index] = track.copyWith(
        curve: at >= 0
            ? KeyCurve(
                List.of(track.curve.keys)
                  ..[at] = track.curve.keys[at].copyWith(value: value),
              ).withAutoTangents(isColor: track.isColor)
            // The other channel has a key here and this one does not: give it
            // one, or the dot could only move along one axis.
            : track.curve.withKey(
                TimelineKey(time: time, value: value),
                isColor: track.isColor,
              ),
      );
    }
    _set(start.copyWith(tracks: tracks));
  }
}
