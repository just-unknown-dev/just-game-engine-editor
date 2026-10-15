/// The timeline being edited: the asset, its undo history, what is selected,
/// where the playhead is — and the preview that shows it in the world
/// without changing the scene.
library;

import 'dart:io';
import 'dart:ui' show Offset;

import 'package:just_game_engine/just_game_engine.dart';

import '../../core/assets/package_asset_paths.dart';
import '../../core/scope/editor_scope.dart';
import '../../core/state/scene_mode_filters.dart';
import 'dope_sheet.dart' show TimelineMetrics;
import 'motion_path.dart';

/// A key, an event or a block: the [index]th thing on the [track]th track.
class TimelineItemRef {
  const TimelineItemRef(this.track, this.index);

  final int track;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is TimelineItemRef && other.track == track && other.index == index;

  @override
  int get hashCode => Object.hash(track, index);

  @override
  String toString() => 'item($track, $index)';
}

class _Step {
  const _Step(this.label, this.asset);

  final String label;
  final TimelineAsset asset;
}

/// What a field has to do with the open timeline.
enum FieldKeyState {
  /// No track animates it.
  none,

  /// A track animates it.
  animated,

  /// A track has a key for it right at the playhead.
  keyed,
}

// A field that is not what the timeline showed: who, what, its value now,
// and the whole field as it was.
class _FieldEdit {
  const _FieldEdit(
    this.binding,
    this.component,
    this.componentType,
    this.field,
    this.channel,
    this.live,
    this.was,
  );

  final TrackBinding binding;
  final Component component;
  final String componentType;
  final SchemaField field;
  final String channel;
  final Object live;
  final Object? was;
}

class TimelineSession {
  TimelineSession(this.scope, {String? root})
    : root = (root ?? Directory.current.path).replaceAll('\\', '/') {
    scope.authoredStateGuards.add(endPreview);
    scope.authoredStateHeld.add(_previewing);
  }

  bool _previewing() => isPreviewing;

  static final Expando<TimelineSession> _sessions = Expando('timelineSession');

  /// The one session of [scope]: the dock, the inspector's key buttons and
  /// the viewport's motion paths all look at the same timeline.
  static TimelineSession of(EditorScope scope) =>
      _sessions[scope] ??= TimelineSession(scope);

  final EditorScope scope;

  /// The project folder that asset paths are relative to.
  final String root;

  /// Whether the editor is authoring (not play-testing). A preview only
  /// happens then: during a play-test the world is the game's.
  bool Function() isAuthoring = () => true;

  static const String newTimelineFolder = 'assets/timelines';

  // ── What is open ─────────────────────────────────────────────────────────

  /// The timeline, or null when nothing is open.
  final Signal<TimelineAsset?> asset = Signal(null, debugLabel: 'timeline');

  /// The file it came from; null for an inline timeline.
  String? get path => _path;
  String? _path;

  /// The entity whose player plays it: "self" for the preview, and where an
  /// inline timeline lives. Null for a file opened by itself.
  Entity? get owner => _owner;
  Entity? _owner;

  bool get isInline => asset.value != null && _path == null;

  /// A file with changes not yet written.
  final Signal<bool> isDirty = Signal(false, debugLabel: 'timelineDirty');

  /// Bumped on anything a view draws that is not a signal of its own.
  final Signal<int> revision = Signal(0, debugLabel: 'timelineRevision');

  final Signal<String?> message = Signal(null, debugLabel: 'timelineMessage');

  /// Bumped when a *different* timeline is opened — not when this one is
  /// edited. What the view hangs its first-look behaviour on.
  final Signal<int> opened = Signal(0, debugLabel: 'timelineOpened');

  // ── View state ───────────────────────────────────────────────────────────

  final Signal<double> playhead = Signal(0.0, debugLabel: 'playhead');
  final Signal<bool> isPlaying = Signal(false, debugLabel: 'timelinePlaying');

  /// Horizontal zoom.
  final Signal<double> pixelsPerSecond = Signal(120.0, debugLabel: 'pps');

  /// The time at the sheet's left edge.
  final Signal<double> scrollTime = Signal(0.0, debugLabel: 'scrollTime');

  final Signal<Set<TimelineItemRef>> selection = Signal(
    const {},
    debugLabel: 'timelineSelection',
  );
  final Signal<int?> selectedTrack = Signal(null, debugLabel: 'selectedTrack');

  /// Times snap to whole frames.
  final Signal<bool> snap = Signal(true, debugLabel: 'timelineSnap');

  /// Show time as frames rather than seconds.
  final Signal<bool> showFrames = Signal(true, debugLabel: 'showFrames');

  static const double minZoom = 8, maxZoom = 2400;

  final List<_Step> _undo = [];
  final List<_Step> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  double get duration => asset.value?.duration ?? 0;
  int get fps => asset.value?.fps ?? 30;

  // ── Opening ──────────────────────────────────────────────────────────────

  /// Shows what [entity] plays: its timeline file, else its inline timeline,
  /// else nothing. A dirty file is saved on the way out.
  Future<void> follow(Entity? entity) async {
    final player = entity?.getComponent<TimelinePlayerComponent>();
    if (player == null) {
      // A file opened by itself stays open while nothing else is chosen.
      if (_owner != null || asset.value == null) await close();
      return;
    }
    final file = player.timelinePath.trim();
    if (identical(entity, _owner) &&
        (file.isEmpty ? isInline : file == _path)) {
      return;
    }
    if (file.isNotEmpty) {
      await openFile(file, owner: entity);
    } else {
      await _leave();
      _show(player.inline, path: null, owner: entity);
    }
  }

  /// Opens the project's [file]. With [owner], "self" tracks preview on it.
  Future<bool> openFile(String file, {Entity? owner}) async {
    await _leave();
    try {
      final source = await PackageAssetPaths.of(root).file(file).readAsString();
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
      _show(null, path: null, owner: owner);
      message.value = 'Could not open $file: $e';
      return false;
    }
  }

  Future<void> close() async {
    await _leave();
    _show(null, path: null, owner: null);
  }

  Future<void> _leave() async {
    endPreview();
    isPlaying.value = false;
    if (isDirty.value && _path != null) await save();
  }

  void _show(TimelineAsset? next, {required String? path, Entity? owner}) {
    _path = path;
    _owner = owner;
    _undo.clear();
    _redo.clear();
    isDirty.value = false;
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
  /// inline timeline, and opens it.
  void createInlineFor(Entity entity) {
    var player = entity.getComponent<TimelinePlayerComponent>();
    if (player == null) {
      player = TimelinePlayerComponent();
      entity.addComponent(player);
    }
    player
      ..timelinePath = ''
      ..inline = TimelineAsset(duration: 2);
    scope.sceneState
      ..markDirty()
      ..refresh();
    _show(player.inline, path: null, owner: entity);
  }

  // ── Editing ──────────────────────────────────────────────────────────────

  /// Replaces the timeline with [next], undoably.
  void apply(String label, TimelineAsset next) {
    final current = asset.value;
    if (current == null) return;
    _lastRecord = null;
    _undo.add(_Step(label, current));
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
    _set(next);
  }

  void undo() {
    final current = asset.value;
    if (current == null || _undo.isEmpty) return;
    final step = _undo.removeLast();
    _lastRecord = null;
    _redo.add(_Step(step.label, current));
    selection.value = const {};
    _set(step.asset);
  }

  void redo() {
    final current = asset.value;
    if (current == null || _redo.isEmpty) return;
    final step = _redo.removeLast();
    _undo.add(_Step(step.label, current));
    selection.value = const {};
    _set(step.asset);
  }

  void _set(TimelineAsset next) {
    // The preview was built from the old timeline; put the world back before
    // building one from the new, so relative tracks start from the truth.
    final wasPreviewing = _playback != null;
    endPreview();
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
      scrubTo(playhead.value);
    } else {
      // The viewport draws the timeline's motion paths.
      scope.sceneState.refresh();
    }
  }

  /// Writes a file timeline to disk. An inline one is saved with the scene.
  Future<bool> save() async {
    final current = asset.value, file = _path;
    if (current == null || file == null) return false;
    try {
      final target = PackageAssetPaths.of(root).file(file);
      await target.parent.create(recursive: true);
      await target.writeAsString('${current.encode()}\n');
      isDirty.value = false;
      onSaved?.call(file);
      return true;
    } catch (e) {
      message.value = 'Could not save $file: $e';
      return false;
    }
  }

  /// Told the file that was written, so running players can reload it.
  void Function(String path)? onSaved;

  /// Moves an inline timeline into a file of its own, which the player then
  /// names — so other entities can play it too.
  Future<bool> extractToAsset(String name) async {
    final current = asset.value, entity = _owner;
    final player = entity?.getComponent<TimelinePlayerComponent>();
    if (current == null || player == null || !isInline) return false;
    final safe = name.trim().replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
    if (safe.isEmpty) return false;
    final file = '$newTimelineFolder/$safe.${TimelineAsset.fileExtension}';
    endPreview();
    _path = file;
    asset.value = current.copyWith(name: safe);
    if (!await save()) {
      _path = null;
      return false;
    }
    player
      ..timelinePath = file
      ..inline = null;
    scope.sceneState
      ..markDirty()
      ..refresh();
    revision.value++;
    return true;
  }

  // ── Tracks ───────────────────────────────────────────────────────────────

  void addTrack(TimelineTrack track) {
    final current = asset.value;
    if (current == null) return;
    apply('Add track', current.copyWith(tracks: [...current.tracks, track]));
    selectedTrack.value = current.tracks.length;
  }

  void removeTrack(int index) {
    final current = asset.value;
    if (current == null || index < 0 || index >= current.tracks.length) return;
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

  /// A property track for every channel of [field], bound to [binding].
  /// Tracks that exist already are left alone. Self-bound transform tracks
  /// start relative, so the timeline can be reused; the rest absolute.
  void addPropertyTracks(
    TrackBinding binding,
    String componentType,
    SchemaField field,
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
    if (current == null) return null;
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
    final curve = track.curve.withKey(key);
    apply('Key', current.withTrackAt(trackIndex, track.copyWith(curve: curve)));
    final index = curve.keys.indexWhere((k) => (k.time - at).abs() < 1e-6);
    return TimelineItemRef(trackIndex, index);
  }

  /// Replaces the key at [ref].
  void updateKey(TimelineItemRef ref, TimelineKey key, {String label = 'Key'}) {
    final current = asset.value;
    final track = current?.tracks[ref.track];
    if (current == null || track is! PropertyTrack || track.locked) return;
    final keys = List.of(track.curve.keys)..[ref.index] = key;
    apply(
      label,
      current.withTrackAt(
        ref.track,
        track.copyWith(curve: KeyCurve(keys).withAutoTangents()),
      ),
    );
  }

  TimelineItemRef? addEvent(int trackIndex, double time, String name) {
    final current = asset.value;
    final track = current?.tracks[trackIndex];
    if (current == null || track is! EventTrack || track.locked) return null;
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
    final trimmed = leadingEdge
        ? block.copyWith(
            start: at.clamp(0.0, block.end - least).toDouble(),
            length: block.end - at.clamp(0.0, block.end - least),
          )
        : block.copyWith(
            length: (at - block.start)
                .clamp(least, start.duration - block.start)
                .toDouble(),
          );
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
    final at = snapTime(time);
    final block = track.defaultBlock.copyWith(start: at);
    final next = track.rebuild(blocks: [...track.blocks, block]);
    apply('Block', current.withTrackAt(trackIndex, next));
    return TimelineItemRef(trackIndex, next.blocks.indexOf(block));
  }

  /// Removes [refs] (on tracks that are not locked).
  void removeItems(Set<TimelineItemRef> refs) {
    final current = asset.value;
    if (current == null || refs.isEmpty) return;
    final tracks = List.of(current.tracks);
    for (var t = 0; t < tracks.length; t++) {
      final gone = {
        for (final r in refs)
          if (r.track == t) r.index,
      };
      if (gone.isEmpty || tracks[t].locked) continue;
      tracks[t] = _mapItems(tracks[t], (i, _) => gone.contains(i) ? null : 0.0);
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
      final t = _timeIn(base, r);
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
      tracks[t] = _mapItems(tracks[t], (i, time) {
        if (!mine.contains(i)) return 0.0;
        landed.add(time + shift);
        return shift;
      }, replaceAt: true);
      for (final time in landed) {
        final index = _indexAt(tracks[t], time);
        if (index >= 0) moved.add(TimelineItemRef(t, index));
      }
    }
    return (base.copyWith(tracks: tracks), moved);
  }

  /// Moves [refs] by [delta] seconds as one undo step; returns where they
  /// are now.
  Set<TimelineItemRef> moveItems(Set<TimelineItemRef> refs, double delta) {
    final current = asset.value;
    if (current == null || refs.isEmpty) return refs;
    final (next, moved) = _shifted(current, refs, delta);
    apply('Move', next);
    selection.value = moved;
    return moved;
  }

  /// A drag of items begins. The timeline as it is now comes back: every
  /// [dragItems] is measured from it, and the whole drag is one undo step.
  TimelineAsset? beginDrag() {
    final current = asset.value;
    if (current == null) return null;
    _undo.add(_Step('Move', current));
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

  static double? _timeIn(TimelineAsset a, TimelineItemRef r) {
    if (r.track < 0 || r.track >= a.tracks.length || r.index < 0) return null;
    final track = a.tracks[r.track];
    if (track is PropertyTrack && r.index < track.curve.keys.length) {
      return track.curve.keys[r.index].time;
    }
    if (track is EventTrack && r.index < track.events.length) {
      return track.events[r.index].time;
    }
    if (track is BlockTrack && r.index < track.blocks.length) {
      return track.blocks[r.index].start;
    }
    return null;
  }

  static int _indexAt(TimelineTrack track, double time) {
    bool at(double t) => (t - time).abs() < 1e-6;
    if (track is PropertyTrack) {
      return track.curve.keys.indexWhere((k) => at(k.time));
    }
    if (track is EventTrack) return track.events.indexWhere((e) => at(e.time));
    if (track is BlockTrack) return track.blocks.indexWhere((b) => at(b.start));
    return -1;
  }

  /// [track] with each item dropped ([change] returns null) or shifted by
  /// what [change] returns.
  static TimelineTrack _mapItems(
    TimelineTrack track,
    double? Function(int index, double time) change, {
    bool replaceAt = false,
  }) {
    if (track is PropertyTrack) {
      final kept = <TimelineKey>[], moved = <TimelineKey>[];
      for (var i = 0; i < track.curve.keys.length; i++) {
        final k = track.curve.keys[i];
        final shift = change(i, k.time);
        if (shift == null) continue;
        (shift == 0 ? kept : moved).add(k.copyWith(time: k.time + shift));
      }
      // A moved key dropped onto another takes its place.
      if (replaceAt) {
        kept.removeWhere(
          (k) => moved.any((m) => (m.time - k.time).abs() < 1e-6),
        );
      }
      return track.copyWith(
        curve: KeyCurve([...kept, ...moved]).withAutoTangents(),
      );
    }
    if (track is EventTrack) {
      return track.copyWith(
        events: [
          for (var i = 0; i < track.events.length; i++)
            if (change(i, track.events[i].time) case final shift?)
              track.events[i].copyWith(time: track.events[i].time + shift),
        ],
      );
    }
    if (track is BlockTrack) {
      return track.rebuild(
        blocks: [
          for (var i = 0; i < track.blocks.length; i++)
            if (change(i, track.blocks[i].start) case final shift?)
              track.blocks[i].copyWith(start: track.blocks[i].start + shift),
        ],
      );
    }
    return track;
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
      tracks[t] = _mapItems(tracks[t], (i, time) {
        if (!mine.contains(i)) return 0.0;
        final to = snapTime(pivot + (time - pivot) * factor);
        landed.add(to);
        return to - time;
      }, replaceAt: true);
      for (final time in landed) {
        final index = _indexAt(tracks[t], time);
        if (index >= 0) moved.add(TimelineItemRef(t, index));
      }
    }
    return (base.copyWith(tracks: tracks), moved);
  }

  /// The earliest and latest time among [refs] in [base].
  static (double, double)? _span(
    TimelineAsset base,
    Set<TimelineItemRef> refs,
  ) {
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final r in refs) {
      final t = _timeIn(base, r);
      if (t == null) continue;
      if (t < lo) lo = t;
      if (t > hi) hi = t;
    }
    return lo == double.infinity ? null : (lo, hi);
  }

  /// Stretches the selection in time by [factor] about its first item, as
  /// one undo step.
  Set<TimelineItemRef> scaleItems(Set<TimelineItemRef> refs, double factor) {
    final current = asset.value;
    final span = current == null ? null : _span(current, refs);
    if (current == null || span == null || factor <= 0) return refs;
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
    final span = _span(start, refs);
    if (span == null || factor <= 0) return refs;
    final (next, moved) = _scaled(start, refs, factor, span.$1);
    _set(next);
    selection.value = moved;
    return moved;
  }

  // What was copied: for each item its track (to go back where it came
  // from), its time after the first copied item, and the item itself.
  final List<(int track, double offset, Object item)> _clipboard = [];

  bool get canPaste => _clipboard.isNotEmpty;

  /// Copies the selection.
  void copy() {
    final current = asset.value;
    final span = current == null ? null : _span(current, selection.value);
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
      final time = _timeIn(current, r);
      if (item != null && time != null) {
        _clipboard.add((r.track, time - span.$1, item));
      }
    }
  }

  /// Pastes at [time] (the playhead by default). What was copied from one
  /// track goes to the selected track when it holds the same kind of thing —
  /// that is how keys get from one field, or one entity, to another;
  /// otherwise everything goes back to the track it came from.
  Set<TimelineItemRef> paste({double? time}) {
    final current = asset.value;
    if (current == null || _clipboard.isEmpty) return const {};
    final at = snapTime(time ?? playhead.value);
    final sources = {for (final c in _clipboard) c.$1};
    final target = selectedTrack.value;
    int trackFor(int source) {
      if (sources.length == 1 &&
          target != null &&
          target < current.tracks.length &&
          _sameKind(current.tracks[target], _clipboard.first.$3)) {
        return target;
      }
      return source;
    }

    final tracks = List.of(current.tracks);
    final pasted = <(int, double)>[];
    for (final (source, offset, item) in _clipboard) {
      final t = trackFor(source);
      if (t >= tracks.length || tracks[t].locked) continue;
      if (!_sameKind(tracks[t], item)) continue;
      final to = at + offset;
      if (to > current.duration + 1e-9) continue;
      final track = tracks[t];
      if (track is PropertyTrack && item is TimelineKey) {
        tracks[t] = track.copyWith(
          curve: track.curve.withKey(item.copyWith(time: to)),
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
      }
      pasted.add((t, to));
    }
    if (pasted.isEmpty) return const {};
    apply('Paste', current.copyWith(tracks: tracks));
    final refs = {
      for (final (t, to) in pasted)
        if (_indexAt(tracks[t], to) case final i when i >= 0)
          TimelineItemRef(t, i),
    };
    selection.value = refs;
    return refs;
  }

  static bool _sameKind(TimelineTrack track, Object item) =>
      track is PropertyTrack && item is TimelineKey ||
      track is EventTrack && item is TimelineEvent ||
      track is BlockTrack && item is TimelineBlock;

  /// Copies the selection to just after itself.
  Set<TimelineItemRef> duplicate() {
    final current = asset.value;
    final span = current == null ? null : _span(current, selection.value);
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
    if (current == null || refs.isEmpty) return;
    final tracks = List.of(current.tracks);
    for (var t = 0; t < tracks.length; t++) {
      final gone = {
        for (final r in refs)
          if (r.track == t) r.index,
      };
      if (gone.isEmpty || tracks[t].locked) continue;
      final times = [
        for (var i = 0; i < itemCount(t); i++)
          _timeIn(current, TimelineItemRef(t, i))!,
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
      tracks[t] = _mapItems(tracks[t], (i, time) {
        if (gone.contains(i)) return null;
        return time > lastGone ? -gap : 0.0;
      });
    }
    selection.value = const {};
    apply('Ripple delete', current.copyWith(tracks: tracks));
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
    final m = current.markers[index];
    apply(
      'Marker',
      current.copyWith(
        markers: [
          for (var i = 0; i < current.markers.length; i++)
            if (i == index)
              TimelineMarker(
                time: time == null ? m.time : snapTime(time),
                name: name ?? m.name,
              )
            else
              current.markers[i],
        ],
      ),
    );
  }

  /// The stretch Play loops over, when set: for working on one part of a
  /// long timeline. An editor's choice, not part of the asset.
  final Signal<(double, double)?> workRange = Signal(
    null,
    debugLabel: 'workRange',
  );

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

  /// Sets what the entity's player runs, in seconds. Zero for [to] plays to
  /// the end; the two are sorted, so dragging one edge past the other is not
  /// an error.
  bool setPlayRange(double from, double to) {
    final target = player;
    if (target == null) return false;
    final end = to <= 0 ? duration : to;
    final lo = (from < end ? from : end).clamp(0.0, duration).toDouble();
    final hi = (from < end ? end : from).clamp(0.0, duration).toDouble();
    // A range that is the whole thing is no range at all.
    final whole = lo <= 0 && hi >= duration - 1e-6;
    target
      ..from = whole ? 0 : lo
      ..to = whole ? 0 : hi;
    scope.sceneState
      ..markDirty()
      ..refresh();
    revision.value++;
    return true;
  }

  /// What the player runs, in seconds, or null when it plays the lot.
  (double, double)? get playRange {
    final target = player;
    if (target == null || !target.hasRange) return null;
    return (target.from, target.to <= 0 ? duration : target.to);
  }

  /// Back to playing the whole timeline.
  bool clearPlayRange() {
    final target = player;
    if (target == null || !target.hasRange) return false;
    target
      ..from = 0
      ..to = 0;
    scope.sceneState
      ..markDirty()
      ..refresh();
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

  // ── Curves ───────────────────────────────────────────────────────────────

  /// The right-hand side shows curves rather than the dope sheet.
  final Signal<bool> showCurves = Signal(false, debugLabel: 'showCurves');

  /// A frame of dragging keys in the curve editor: [refs] of [start] moved
  /// by [dt] seconds and [dv] in value. See [dragItems].
  Set<TimelineItemRef> dragKeys(
    TimelineAsset start,
    Set<TimelineItemRef> refs,
    double dt,
    double dv,
  ) {
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

  // ── Keying from anywhere ─────────────────────────────────────────────────

  /// While on, a change to a field the timeline could animate — in the
  /// inspector, by a gizmo, by anything — becomes a key at the playhead,
  /// and the scene keeps the value it had.
  final Signal<bool> record = Signal(false, debugLabel: 'timelineRecord');

  void setRecording(bool on) {
    if (asset.value == null) return;
    record.value = on;
    // Recording compares the world with what the timeline shows, so there
    // has to be something shown.
    if (on) scrubTo(playhead.value);
  }

  // What every watched field held when the timeline was last shown, in its
  // saved form: a difference from this is somebody's edit.
  final Map<Component, Map<SchemaField, Object?>> _expected = Map.identity();

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

  /// The component types recording leaves alone: a timeline does not
  /// animate its own player, and a tile map's file path is not something
  /// to key — a map moved into a file while Record is on would otherwise
  /// become a key.
  static const Set<String> unrecorded = {
    'TimelinePlayerComponent',
    'TimelineTriggerComponent',
    'LevelMapComponent',
  };

  Iterable<(Component, ComponentDefinition, SchemaField)> _fieldsOf(
    Entity entity,
  ) sync* {
    for (final component in entity.components) {
      final definition = scope.definitions.definitionFor(component);
      if (definition == null || unrecorded.contains(definition.type)) continue;
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

  static bool _same(Object? a, Object? b) =>
      a is num && b is num ? (a - b).abs() < 1e-6 : a == b;

  static Object? _channelOf(Object? saved, String channel) =>
      channel.isEmpty ? saved : (saved is Map ? saved[channel] : null);

  String? _lastRecord;

  /// Looks for fields that are no longer what the timeline showed and keys
  /// them at the playhead. Returns how many keys it wrote. Cheap when
  /// nothing changed, so it can be called often.
  int captureEdits() {
    final current = asset.value;
    if (current == null || !record.value || !isAuthoring()) return 0;
    final edits = <_FieldEdit>[];
    for (final MapEntry(key: entity, value: binding) in _watched().entries) {
      for (final (component, definition, field) in _fieldsOf(entity)) {
        final known = _expected[component];
        if (known == null || !known.containsKey(field)) continue;
        final was = known[field], now = field.encodeFrom(component);
        for (final channel in PropertyAccess.channelsOf(field)) {
          final live = _channelOf(now, channel);
          if (live == null || _same(_channelOf(was, channel), live)) continue;
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
  List<String> _shownChannels(String componentType, SchemaField field) {
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
  bool keyField(Entity entity, Component component, SchemaField field) =>
      keyFields(entity, component, [field]);

  /// [keyField] for several fields of one component, as one undo step.
  bool keyFields(Entity entity, Component component, List<SchemaField> fields) {
    final current = asset.value;
    final binding = bindingFor(entity);
    final definition = scope.definitions.definitionFor(component);
    if (current == null || binding == null || definition == null) return false;
    final edits = <_FieldEdit>[];
    for (final field in fields) {
      if (!PropertyAccess.canAnimate(field)) continue;
      final now = field.encodeFrom(component);
      for (final channel in _shownChannels(definition.type, field)) {
        final live = _channelOf(now, channel);
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
        final base = _channelOf(authoredField, e.channel);
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
    SchemaField field,
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
              ).withAutoTangents()
            // The other channel has a key here and this one does not: give it
            // one, or the dot could only move along one axis.
            : track.curve.withKey(TimelineKey(time: time, value: value)),
      );
    }
    _set(start.copyWith(tracks: tracks));
  }

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

  /// How wide the sheet is drawn, in pixels. The layout sets it; scrolling
  /// is clamped by it, and the scroll bar sizes its thumb from it.
  final Signal<double> viewWidth = Signal(0.0, debugLabel: 'timelineWidth');

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

  /// How far past the end the sheet may scroll, whatever it holds: enough
  /// that dragging it always moves something, and that the last key never
  /// sits pinned against the right edge.
  static const double overscrollFraction = 0.5;

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
    return (overflow < 0 ? 0 : overflow) + span * overscrollFraction;
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
    pixelsPerSecond.value = ((width - 32) / d).clamp(minZoom, maxZoom);
    scrollTime.value = 0;
  }

  /// Zooms by [factor] keeping the time under [anchorX] (pixels from the
  /// sheet's left edge) where it is.
  void zoomAround(double factor, double anchorX) {
    final before = pixelsPerSecond.value;
    final after = (before * factor).clamp(minZoom, maxZoom);
    final time = scrollTime.value + anchorX / before;
    pixelsPerSecond.value = after;
    // Clamped after the zoom: pulling back can leave the sheet past the end.
    scrollTo(time - anchorX / after);
  }

  // ── Preview ──────────────────────────────────────────────────────────────

  TimelinePlayback? _playback;

  // What each field held before the preview first wrote to it, in the
  // field's saved form.
  final Map<Component, Map<SchemaField, Object?>> _authored = Map.identity();

  bool get isPreviewing => _playback != null;

  /// The value [field] of [component] has in the scene — not what a preview
  /// is showing. Null when the preview has not touched it.
  Object? authoredValue(Component component, SchemaField field) =>
      _authored[component]?[field];

  bool isPreviewed(Component component, SchemaField field) =>
      _authored[component]?.containsKey(field) ?? false;

  Entity? _resolve(TrackBinding binding) =>
      binding.resolve(scope.world, _owner);

  /// Moves the playhead to [time] and shows the timeline there.
  void scrubTo(double time) {
    final current = asset.value;
    if (current == null) return;
    playhead.value = time.clamp(0.0, current.duration).toDouble();
    if (!isAuthoring()) return;
    final playback = _playback ??= _startPreview(current);
    playback.seek(playhead.value);
    _captureExpected();
    scope.sceneState.refresh();
  }

  TimelinePlayback _startPreview(TimelineAsset current) {
    final owner = _owner ?? scope.world.createEntity(name: '');
    if (_owner == null) _scratchOwner = owner;
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

  Entity? _scratchOwner;

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

  void pause() => isPlaying.value = false;

  /// Stops, rewinds, and puts the world back as authored.
  void stop() {
    isPlaying.value = false;
    playhead.value = 0;
    endPreview();
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
    scrubTo(next);
    // Zoomed in, the playhead would otherwise run off the right edge.
    revealTime(next);
  }

  void stepFrames(int frames) {
    pause();
    scrubTo((frameOf(playhead.value) + frames) / fps);
    revealTime(playhead.value);
  }

  /// Puts back every field the preview wrote, exactly as it was. After this
  /// the world is the scene as authored again.
  void endPreview() {
    final playback = _playback;
    if (playback == null) return;
    _playback = null;
    playback.dispose();
    for (final entry in _authored.entries) {
      for (final field in entry.value.entries) {
        field.key.decodeInto(entry.key, field.value);
      }
    }
    _authored.clear();
    // Nothing is shown any more, so there is nothing to compare with.
    _expected.clear();
    _owner?.getComponent<TimelinePlayerComponent>()?.suspended = false;
    final scratch = _scratchOwner;
    if (scratch != null) {
      _scratchOwner = null;
      if (scratch.isAlive) scope.world.destroyEntity(scratch);
    }
    scope.sceneState.refresh();
  }

  void dispose() {
    endPreview();
    scope.authoredStateGuards.remove(endPreview);
    scope.authoredStateHeld.remove(_previewing);
    _sessions[scope] = null;
  }
}
