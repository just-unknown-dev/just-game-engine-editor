/// The timeline being edited: the asset, its undo history, what is selected,
/// where the playhead is — and the preview that shows it in the world
/// without changing the scene.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';
import 'dope_sheet.dart' show TimelineMetrics;
import 'motion_path.dart';

part 'timeline_session_opening.dart';
part 'timeline_session_edits.dart';
part 'timeline_session_items.dart';
part 'timeline_session_keying.dart';
part 'timeline_session_preview.dart';

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
  final FieldDefinition field;
  final String channel;
  final Object live;
  final Object? was;
}

// A copied item: where it came from, what kind of track can take it, its
// time after the first copied item, and the item itself.
class _Copied {
  const _Copied(this.track, this.signature, this.kind, this.offset, this.item);

  /// The index of the track it came from, when it was copied.
  final int track;

  /// Which track that was, to find it again after tracks came and went.
  final String signature;

  /// What can take it: a key of a colour, a number, a flag or a name; an
  /// event; a block of one kind of block track.
  final String kind;

  final double offset;
  final Object item;
}

// The scene's value of a field before and after a step of the editor's
// history made while a preview showed.
typedef _Authored = (Object? before, Object? after);

/// The timeline being edited: the document and its undo, the preview and
/// recording, and the view's time and zoom. One per editor ([of]).
class TimelineSession {
  TimelineSession(this.scope, {String? root})
    : root = (root ?? Directory.current.path).replaceAll('\\', '/') {
    scope.authoredStateGuards.add(endPreview);
    scope.authoredStateHeld.add(_previewing);
    _noteHistory();
    _stopHistory = scope.history.revision.watch(_onHistory);
  }

  bool _previewing() => isPreviewing;

  /// The one session of [scope]: the dock, the inspector's key buttons and
  /// the viewport's motion paths all look at the same timeline.
  ///
  /// Kept in the scope's container, so it is disposed with the scope.
  static TimelineSession of(EditorScope scope) => scope.service(
    () => TimelineSession(scope),
    dispose: (session) => session.dispose(),
  );

  final EditorScope scope;

  /// The project folder that asset paths are relative to.
  final String root;

  /// Whether the editor is authoring (not play-testing). A preview only
  /// happens then: during a play-test the world is the game's.
  bool Function() isAuthoring = () => true;

  static const String newTimelineFolder = 'assets/timelines';

  // ── Who is looking ───────────────────────────────────────────────────────

  int _views = 0;

  /// Whether a Timeline dock shows this session. The inspector's key
  /// buttons, the motion paths and the timeline commands only work while
  /// one does: an edit made with nobody looking would land in a timeline
  /// nobody can see.
  bool get isShown => _views > 0;

  /// A Timeline dock shows the session from now on.
  void attachView() => _views++;

  /// A Timeline dock showing the session went away. With none left,
  /// recording stops, the preview ends — the world is the scene again — and
  /// a file's changes are written. False when that write failed: the
  /// changes are still here, and the next dock to open shows them and why.
  Future<bool> detachView() async {
    if (_views > 0) _views--;
    if (_views > 0) return true;
    record.value = false;
    pause();
    endPreview();
    if (isDirty.value && _path != null) return save();
    return true;
  }

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

  // Whether what is shown is what the owner's player plays — its inline
  // timeline or its file — rather than a file opened with the owner only
  // lending "self" to the preview.
  bool _followsPlayer = false;

  // The file last asked for, so one that would not open is not read again
  // and again.
  String? _requested;

  // Bumped by every open and close: one that finishes after a later one
  // began leaves the later one's timeline showing.
  int _opening = 0;

  bool get isInline => asset.value != null && _path == null;

  /// A file with changes not yet written.
  final Signal<bool> isDirty = Signal(false, debugLabel: 'timelineDirty');

  /// Bumped on anything a view draws that is not a signal of its own.
  final Signal<int> revision = Signal(0, debugLabel: 'timelineRevision');

  /// What the author should know: why a file did not open or save, why an
  /// edit was refused. Cleared when another timeline is shown.
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

  /// The most frames a second a timeline can be set to.
  static const int maxFps = 240;

  final List<_Step> _undo = [];
  final List<_Step> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  double get duration => asset.value?.duration ?? 0;
  int get fps => asset.value?.fps ?? 30;

  Future<bool>? _saving;

  /// Told the file that was written, so running players can reload it.
  void Function(String path)? onSaved;

  static String _safeName(String name) =>
      name.trim().replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');

  static String? _timelineFileFor(String name) {
    final safe = _safeName(name);
    return safe.isEmpty
        ? null
        : '$newTimelineFolder/$safe.${TimelineAsset.fileExtension}';
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
        curve: KeyCurve([
          ...kept,
          ...moved,
        ]).withAutoTangents(isColor: track.isColor),
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

  // What was copied, oldest first.
  final List<_Copied> _clipboard = [];

  // Which track [track] is, by what it is rather than where it is in the
  // list: its kind, who it acts on and, for a field, which field.
  static String _signatureOf(TimelineTrack track) =>
      '${track.runtimeType}|${track.binding.kind.name}:${track.binding.value}|'
      '${track is PropertyTrack ? track.path : ''}';

  /// The stretch Play loops over, when set: for working on one part of a
  /// long timeline. An editor's choice, not part of the asset.
  final Signal<(double, double)?> workRange = Signal(
    null,
    debugLabel: 'workRange',
  );

  /// What the player runs, in seconds, or null when it plays the lot.
  (double, double)? get playRange {
    final target = player;
    if (target == null || !target.hasRange) return null;
    return (target.from, target.to <= 0 ? duration : target.to);
  }

  // ── Curves ───────────────────────────────────────────────────────────────

  /// The right-hand side shows curves rather than the dope sheet.
  final Signal<bool> showCurves = Signal(false, debugLabel: 'showCurves');

  // ── Keying from anywhere ─────────────────────────────────────────────────

  /// While on, a change to a field the timeline could animate — in the
  /// inspector, by a gizmo, by anything — becomes a key at the playhead,
  /// and the scene keeps the value it had.
  final Signal<bool> record = Signal(false, debugLabel: 'timelineRecord');

  // What every watched field held when the timeline was last shown, in its
  // saved form: a difference from this is somebody's edit.
  final Map<Component, Map<FieldDefinition, Object?>> _expected =
      Map.identity();

  /// The component types recording leaves alone: a timeline does not
  /// animate its own player, and a tile map's file path is not something
  /// to key — a map moved into a file while Record is on would otherwise
  /// become a key.
  static const Set<String> unrecorded = {
    'TimelinePlayerComponent',
    'TimelineTriggerComponent',
    'LevelMapComponent',
  };

  static bool _same(Object? a, Object? b) =>
      a is num && b is num ? (a - b).abs() < 1e-6 : a == b;

  // [_same], into maps and lists: two saved values that say the same.
  static bool _sameSaved(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final MapEntry(:key, :value) in a.entries) {
        if (!b.containsKey(key) || !_sameSaved(value, b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameSaved(a[i], b[i])) return false;
      }
      return true;
    }
    return _same(a, b);
  }

  static Object? _channelOf(Object? saved, String channel) =>
      channel.isEmpty ? saved : (saved is Map ? saved[channel] : null);

  String? _lastRecord;

  /// How wide the sheet is drawn, in pixels. The layout sets it; scrolling
  /// is clamped by it, and the scroll bar sizes its thumb from it.
  final Signal<double> viewWidth = Signal(0.0, debugLabel: 'timelineWidth');

  /// How far past the end the sheet may scroll, whatever it holds: enough
  /// that dragging it always moves something, and that the last key never
  /// sits pinned against the right edge.
  static const double overscrollFraction = 0.5;

  // ── Preview ──────────────────────────────────────────────────────────────

  TimelinePlayback? _playback;

  // What each field held before the preview first wrote to it, in the
  // field's saved form.
  final Map<Component, Map<FieldDefinition, Object?>> _authored =
      Map.identity();

  // What the preview showed in each field it wrote, after its last seek: a
  // field that holds something else has been changed by somebody.
  final Map<Component, Map<FieldDefinition, Object?>> _shown = Map.identity();

  // An edit while Recording was off changed what the scene holds: the
  // preview is built again before it next shows a moment.
  bool _previewStale = false;

  // Set while the preview is ended only to be started again at once: the
  // scratch owner stays, and the editor's undo groups as it did.
  bool _rebuilding = false;

  // The entity "self" stands for while a file opened by itself previews.
  Entity? _scratchOwner;

  // How long since the panels were last told the world moved while
  // playing: a dozen times a second is plenty for numbers to follow, and
  // every frame rebuilds every panel that shows the scene.
  final Stopwatch _sinceRefresh = Stopwatch();

  /// Puts back every field the preview wrote, exactly as it was. After this
  /// the world is the scene as authored again.
  void endPreview() => _endPreview();

  // ── The editor's undo, while a preview shows ─────────────────────────────
  //
  // A preview writes into the scene's own fields, so a step of the editor's
  // history made while it shows — an inspector edit, a gizmo drag — holds
  // what the preview showed as its "before". Left alone, undoing that step
  // once the preview has ended would put a previewed value into the scene,
  // a value nobody authored. So each such step is remembered with what the
  // scene really held before and after it, and its undo and redo leave
  // those in the fields the preview showed.

  final Expando<Map<Component, Map<FieldDefinition, _Authored>>> _tainted =
      Expando('timelineTainted');

  void Function()? _stopHistory;
  EditorCommand? _lastTop, _lastRedoTop;
  int _lastRedoDepth = 0;

  bool _disposed = false;
}
