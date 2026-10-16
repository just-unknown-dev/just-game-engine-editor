/// The Timeline dock: one timeline — a file, or the one inside the selected
/// entity's player — with a tree of tracks on the left and a sheet of keys
/// over time on the right, previewed in the world without changing the scene.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import 'curve_view.dart';
import 'dope_sheet.dart';
import 'timeline_dialogs.dart';
import 'timeline_header.dart';
import 'timeline_item_bar.dart';
import 'timeline_menu.dart';
import 'timeline_scrollbar.dart';
import 'timeline_session.dart';
import 'track_tree.dart';

class TimelineDock extends StatefulWidget {
  const TimelineDock({super.key, required this.scope, this.openPath});

  final EditorScope scope;

  /// A `.timeline.json` to open instead of following the selection — what
  /// the Assets dock passes.
  final String? openPath;

  @override
  State<TimelineDock> createState() => TimelineDockState();
}

class TimelineDockState extends State<TimelineDock>
    with SingleTickerProviderStateMixin {
  late final TimelineSession session = TimelineSession.of(widget.scope);
  final ScrollController _vertical = ScrollController();
  final FocusNode _focus = FocusNode(debugLabel: 'TimelineDock');
  final GlobalKey<DopeSheetState> _sheet = GlobalKey();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  final List<void Function()> _stop = [];
  bool _fitted = false;
  Timer? _recordPoll;
  double _sheetWidth = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    void rebuild() {
      if (mounted) setState(() {});
    }

    for (final signal in <Signal<Object?>>[
      session.asset,
      session.revision,
      session.playhead,
      session.isPlaying,
      session.pixelsPerSecond,
      session.scrollTime,
      session.selection,
      session.selectedTrack,
      session.snap,
      session.showFrames,
      session.isDirty,
      session.workRange,
      session.showCurves,
      session.record,
      session.viewWidth,
      widget.scope.sceneState.revision,
    ]) {
      _stop.add(signal.watch(rebuild));
    }
    // Gizmos move things without telling anyone; while recording, look.
    _recordPoll = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (session.record.value) session.captureEdits();
    });
    _stop
      ..add(session.isPlaying.watch(_syncTicker))
      // Only a different timeline is worth re-fitting for; an edit must
      // leave the zoom and the scroll where they are.
      ..add(session.opened.watch(() => _fitted = false))
      ..add(widget.scope.sceneState.selectedEntity.watch(_follow));
    final path = widget.openPath;
    if (path != null) {
      session.openFile(
        path,
        owner: _playerOf(path) ?? widget.scope.sceneState.selectedEntity.value,
      );
    } else {
      _follow();
    }
  }

  /// The first entity whose player plays [path], so "self" means someone.
  jge.Entity? _playerOf(String path) {
    for (final e in widget.scope.world.query([jge.TimelinePlayerComponent])) {
      if (e.getComponent<jge.TimelinePlayerComponent>()!.timelinePath == path) {
        return e;
      }
    }
    return null;
  }

  @override
  void didUpdateWidget(TimelineDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final path = widget.openPath;
    if (path != null && path != oldWidget.openPath) {
      session.openFile(path, owner: _playerOf(path));
    }
  }

  void _follow() =>
      session.follow(widget.scope.sceneState.selectedEntity.value);

  void _syncTicker() {
    if (session.isPlaying.value && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!session.isPlaying.value && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    session.tick(dt.clamp(0.0, 0.1).toDouble());
  }

  @override
  void dispose() {
    for (final stop in _stop) {
      stop();
    }
    _ticker.dispose();
    _recordPoll?.cancel();
    // The dock going away ends the look at the timeline: the world is the
    // scene again, and a file's changes are on disk.
    session
      ..pause()
      ..endPreview();
    if (session.isDirty.value) unawaited(session.save());
    _vertical.dispose();
    _focus.dispose();
    super.dispose();
  }

  static bool get _isTyping {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static final Set<LogicalKeyboardKey> _ctrlKeys = {
    LogicalKeyboardKey.keyZ,
    LogicalKeyboardKey.keyY,
    LogicalKeyboardKey.keyC,
    LogicalKeyboardKey.keyX,
    LogicalKeyboardKey.keyV,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.keyA,
  };

  static final Set<LogicalKeyboardKey> _plainKeys = {
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.delete,
    LogicalKeyboardKey.backspace,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.keyM,
    LogicalKeyboardKey.bracketLeft,
    LogicalKeyboardKey.bracketRight,
    LogicalKeyboardKey.backslash,
    LogicalKeyboardKey.comma,
    LogicalKeyboardKey.period,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.keyK,
    LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyR,
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.escape,
  };

  /// The keys [_onKey] acts on, kept from the editor's shortcuts while the
  /// dock has the focus: the editor hears every key first, so Delete would
  /// otherwise delete the selected entity as well as the keys, Ctrl+Z undo
  /// in the level as well as here, and R pick the Rotate tool. Ctrl+S is
  /// left to both: it saves the timeline and the scene.
  bool _claims(KeyEvent event) {
    if (session.asset.value == null) return false;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      return _ctrlKeys.contains(event.logicalKey);
    }
    return _plainKeys.contains(event.logicalKey);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _isTyping || session.asset.value == null) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final key = event.logicalKey;
    if (ctrl && key == LogicalKeyboardKey.keyZ) {
      keys.isShiftPressed ? session.redo() : session.undo();
    } else if (ctrl && key == LogicalKeyboardKey.keyY) {
      session.redo();
    } else if (ctrl && key == LogicalKeyboardKey.keyS) {
      session.save();
    } else if (key == LogicalKeyboardKey.space) {
      session.isPlaying.value ? session.pause() : session.play();
    } else if (ctrl && key == LogicalKeyboardKey.keyC) {
      session.copy();
    } else if (ctrl && key == LogicalKeyboardKey.keyX) {
      session
        ..copy()
        ..removeItems(session.selection.value);
    } else if (ctrl && key == LogicalKeyboardKey.keyV) {
      session.paste();
    } else if (ctrl && key == LogicalKeyboardKey.keyD) {
      session.duplicate();
    } else if (ctrl && key == LogicalKeyboardKey.keyA) {
      session.selection.value = {
        for (var t = 0; t < session.asset.value!.tracks.length; t++)
          for (var i = 0; i < session.itemCount(t); i++) TimelineItemRef(t, i),
      };
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      keys.isShiftPressed
          ? session.rippleDelete(session.selection.value)
          : session.removeItems(session.selection.value);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final step =
          (key == LogicalKeyboardKey.arrowLeft ? -1 : 1) *
          (keys.isShiftPressed ? 10 : 1);
      // With nothing selected the arrows walk the playhead instead.
      session.selection.value.isEmpty
          ? session.stepFrames(step)
          : session.nudge(step);
    } else if (key == LogicalKeyboardKey.keyM) {
      session.addMarker(
        session.playhead.value,
        'Marker ${session.asset.value!.markers.length + 1}',
      );
    } else if (key == LogicalKeyboardKey.bracketLeft) {
      session.setWorkRange(
        session.playhead.value,
        session.workRange.value?.$2 ?? session.duration,
      );
    } else if (key == LogicalKeyboardKey.bracketRight) {
      session.setWorkRange(
        session.workRange.value?.$1 ?? 0,
        session.playhead.value,
      );
    } else if (key == LogicalKeyboardKey.backslash) {
      session.workRange.value = null;
    } else if (key == LogicalKeyboardKey.comma) {
      session.stepFrames(-1);
    } else if (key == LogicalKeyboardKey.period) {
      session.stepFrames(1);
    } else if (key == LogicalKeyboardKey.home) {
      session
        ..pause()
        ..scrubTo(0)
        ..scrollTo(0);
    } else if (key == LogicalKeyboardKey.end) {
      session
        ..pause()
        ..scrubTo(session.duration)
        ..revealTime(session.duration);
    } else if (key == LogicalKeyboardKey.keyK) {
      _keySelectedTrack();
    } else if (key == LogicalKeyboardKey.keyF) {
      session.zoomToFit(_sheetWidth);
    } else if (key == LogicalKeyboardKey.keyR) {
      session.setRecording(!session.record.value);
    } else if (key == LogicalKeyboardKey.tab) {
      session.showCurves.value = !session.showCurves.value;
    } else if (key == LogicalKeyboardKey.escape) {
      session.selection.value = const {};
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _keySelectedTrack() {
    final index = session.selectedTrack.value;
    if (index == null) return;
    final ref = session.setKey(index, session.playhead.value);
    if (ref != null) session.selection.value = {ref};
  }

  // ── Adding ───────────────────────────────────────────────────────────────

  Future<void> _addTrack(BuildContext anchor) async {
    final box = anchor.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset(0, box.size.height));
    // Every kind the engine knows and offers: its own, and a package's
    // (skeletal clips, once the 3-D renderer is in).
    final kinds = widget.scope.context.trackKinds;
    final choice = await showTimelineMenu<String>(context, at, [
      timelineMenuItem('property', 'A field…'),
      timelineMenuDivider(),
      for (final kind in kinds.offered)
        timelineMenuItem('kind:$kind', kinds.offerFor(kind)!.label),
    ]);
    if (choice == null || !mounted) return;
    if (choice == 'property') {
      final picked = await promptPropertyTrack(context, session);
      if (picked != null) {
        session.addPropertyTracks(
          picked.binding,
          picked.componentType,
          picked.field,
        );
      }
      return;
    }
    if (!choice.startsWith('kind:')) return;
    final offer = kinds.offerFor(choice.substring('kind:'.length));
    if (offer != null) session.addTrack(offer.create());
  }

  Future<void> _addAt(int trackIndex, double time) async {
    final track = session.asset.value!.tracks[trackIndex];
    TimelineItemRef? ref;
    if (track is jge.PropertyTrack) {
      ref = session.setKey(trackIndex, time);
    } else if (track is jge.EventTrack) {
      final name = await promptTimelineText(
        context,
        title: 'Event name',
        hint: 'footstep',
      );
      if (name == null || name.isEmpty) return;
      ref = session.addEvent(trackIndex, time, name);
    } else if (track is jge.BlockTrack) {
      ref = session.addBlock(trackIndex, time);
    }
    if (ref != null) session.selection.value = {ref};
  }

  Future<void> _rulerMenu(double time, int? marker, Offset at) async {
    final choice = await showTimelineMenu<String>(context, at, [
      if (marker == null)
        timelineMenuItem('add', 'Add a marker here  (M)')
      else ...[
        timelineMenuItem('rename', 'Rename…'),
        timelineMenuItem('remove', 'Remove marker'),
      ],
      timelineMenuDivider(),
      timelineMenuItem('from', 'Work range starts here  ([)'),
      timelineMenuItem('to', 'Work range ends here  (])'),
      if (session.workRange.value != null)
        timelineMenuItem('clear', 'Clear the work range  (\\)'),
      if (session.player case final player?) ...[
        timelineMenuDivider(),
        if (session.workRange.value != null)
          timelineMenuItem('toPlayer', 'Play only this range, in the game too'),
        if (player.hasRange) ...[
          timelineMenuItem('fromPlayer', 'Work range from the play range'),
          timelineMenuItem('clearPlayer', 'Play the whole timeline again'),
        ],
      ],
    ]);
    if (choice == null || !mounted) return;
    final markers = session.asset.value!.markers;
    switch (choice) {
      case 'add' || 'rename':
        final name = await promptTimelineText(
          context,
          title: 'Marker name',
          initial: marker == null
              ? 'Marker ${markers.length + 1}'
              : markers[marker].name,
        );
        if (name == null || name.isEmpty) return;
        marker == null
            ? session.addMarker(time, name)
            : session.updateMarker(marker, name: name);
      case 'remove':
        session.removeMarker(marker!);
      case 'from':
        session.setWorkRange(
          time,
          session.workRange.value?.$2 ?? session.duration,
        );
      case 'to':
        session.setWorkRange(session.workRange.value?.$1 ?? 0, time);
      case 'clear':
        session.workRange.value = null;
      case 'toPlayer':
        session.applyWorkRangeToPlayer();
      case 'fromPlayer':
        session.workRangeFromPlayer();
      case 'clearPlayer':
        session.clearPlayRange();
    }
  }

  Future<void> _itemMenu(TimelineItemRef ref, Offset at) async {
    final track = session.asset.value!.tracks[ref.track];
    final isKey = track is jge.PropertyTrack;
    final choice = await showTimelineMenu<String>(context, at, [
      if (isKey) ...[
        for (final i in jge.KeyInterpolation.values)
          if (i != jge.KeyInterpolation.eased)
            timelineMenuItem('i:${i.name}', switch (i) {
              jge.KeyInterpolation.step => 'Hold (step)',
              jge.KeyInterpolation.linear => 'Linear',
              _ => 'Smooth (bezier)',
            }),
        timelineMenuDivider(),
      ],
      timelineMenuItem('copy', 'Copy'),
      timelineMenuItem('duplicate', 'Duplicate'),
      timelineMenuItem('delete', 'Delete'),
      timelineMenuItem('ripple', 'Ripple delete'),
    ]);
    if (choice == null) return;
    if (choice == 'delete') {
      session.removeItems(session.selection.value);
    } else if (choice == 'ripple') {
      session.rippleDelete(session.selection.value);
    } else if (choice == 'copy') {
      session.copy();
    } else if (choice == 'duplicate') {
      session.duplicate();
    } else if (choice.startsWith('i:') && track is jge.PropertyTrack) {
      final mode = jge.KeyInterpolation.values.byName(choice.substring(2));
      // Every selected key on this kind of track, in one step.
      final current = session.asset.value!;
      final tracks = List.of(current.tracks);
      for (var t = 0; t < tracks.length; t++) {
        final it = tracks[t];
        if (it is! jge.PropertyTrack || it.locked) continue;
        final mine = {
          for (final r in session.selection.value)
            if (r.track == t) r.index,
        };
        if (mine.isEmpty) continue;
        tracks[t] = it.copyWith(
          curve: jge.KeyCurve([
            for (var i = 0; i < it.curve.keys.length; i++)
              mine.contains(i)
                  ? it.curve.keys[i].copyWith(interpolation: mode)
                  : it.curve.keys[i],
          ]),
        );
      }
      session.apply('Interpolation', current.copyWith(tracks: tracks));
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final asset = session.asset.value;
    if (asset == null) return _empty();
    final rows = timelineRowsOf(asset);

    return EditorKeyClaim(
      claims: _claims,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: (_) {
            if (!_focus.hasFocus && !_isTyping) _focus.requestFocus();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TimelineHeader(
                session: session,
                onFit: () => session.zoomToFit(_sheetWidth),
              ),
              // Always there, so the sheet does not jump when a selection
              // comes or goes — between the two clicks of a double click, say.
              TimelineItemBar(session: session),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: TimelineMetrics.treeWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TreeHeader(onAdd: _addTrack),
                          Expanded(
                            child: asset.tracks.isEmpty
                                ? Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text(
                                      'No tracks yet. Add one to animate a '
                                      'field, play a clip or fire an event.',
                                      style: TextStyle(
                                        color: EditorTheme.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  )
                                : TrackTree(
                                    session: session,
                                    rows: rows,
                                    controller: _vertical,
                                  ),
                          ),
                          // The sheet beside it gives up this much to the
                          // scroll bar; without the same gap here the two
                          // would show different last rows.
                          const SizedBox(height: TimelineScrollBar.height),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      color: EditorTheme.textPrimary.withValues(alpha: 0.08),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _sheetWidth = constraints.maxWidth;
                          // What the sheet can show bounds how far it scrolls,
                          // and sizes the bar's thumb.
                          if (session.viewWidth.value != _sheetWidth) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                session.viewWidth.value = _sheetWidth;
                              }
                            });
                          }
                          // The first look at a timeline shows all of it.
                          if (!_fitted && _sheetWidth > 0) {
                            _fitted = true;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) session.zoomToFit(_sheetWidth);
                            });
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: TimelineMetrics.rulerHeight,
                                child: ClipRect(
                                  child: TimelineRuler(
                                    session: session,
                                    onMenu: _rulerMenu,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: session.showCurves.value
                                    ? CurveView(
                                        session: session,
                                        onItemMenu: _itemMenu,
                                      )
                                    : DopeSheet(
                                        key: _sheet,
                                        session: session,
                                        rows: rows,
                                        verticalScroll: _vertical,
                                        onItemMenu: _itemMenu,
                                        onEmptyDoubleTap: _addAt,
                                      ),
                              ),
                              TimelineScrollBar(session: session),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final entity = widget.scope.sceneState.selectedEntity.value;
    final player = entity?.getComponent<jge.TimelinePlayerComponent>();
    final note = session.message.value;
    return EditorEmptyState(
      icon: Icons.movie_filter_outlined,
      title: entity == null
          ? 'No timeline'
          : player == null
          ? '${entity.name ?? 'This entity'} plays no timeline'
          : 'Its Timeline Player is empty',
      hint:
          note ??
          (entity == null
              ? 'Select an entity, or open a .timeline.json from Assets.'
              : 'A timeline animates any field, plays clips and sounds, cuts '
                    'cameras and fires events — on one clock.'),
      actionLabel: entity == null
          ? null
          : player == null
          ? 'Add a Timeline Player'
          : 'Create a timeline',
      onAction: entity == null ? null : () => session.createInlineFor(entity),
    );
  }
}

class _TreeHeader extends StatelessWidget {
  const _TreeHeader({required this.onAdd});

  final void Function(BuildContext anchor) onAdd;

  @override
  Widget build(BuildContext context) => Container(
    height: TimelineMetrics.rulerHeight,
    color: EditorTheme.surfaceDark,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            'TRACKS',
            style: TextStyle(
              color: EditorTheme.textMuted,
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Builder(
          builder: (anchor) => InkWell(
            onTap: () => onAdd(anchor),
            borderRadius: BorderRadius.circular(3),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: 13,
                    color: EditorTheme.primaryBright,
                  ),
                  SizedBox(width: 2),
                  Text(
                    'Add track',
                    style: TextStyle(
                      color: EditorTheme.primaryBright,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
