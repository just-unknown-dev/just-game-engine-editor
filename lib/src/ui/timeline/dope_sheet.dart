/// The right-hand side of the Timeline dock: the ruler, and a sheet of keys,
/// events and blocks over time that fills whatever width the dock has.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/constants/editor_constants.dart';
import 'timeline_session.dart';

/// Sizes the tree and the sheet agree on.
abstract final class TimelineMetrics {
  static const double rowHeight = 24;
  static const double rulerHeight = 26;

  /// How wide an end of the play range is to grab.
  static const double gripWidth = 6;
  static const double treeWidth = 250;
  static const double keySize = 9;

  /// Room left of time zero, so a key at the very start can be seen whole
  /// and boxed.
  static const double leftInset = 12;

  /// How near a pointer must be to a key to mean it.
  static const double hitSlop = 7;
}

/// A line of the dock: a heading for who the tracks below act on, or a
/// track.
sealed class TimelineRow {
  const TimelineRow();
}

class TimelineGroupRow extends TimelineRow {
  const TimelineGroupRow(this.binding);

  final jge.TrackBinding binding;
}

class TimelineTrackRow extends TimelineRow {
  const TimelineTrackRow(this.index);

  /// The track's index in the asset.
  final int index;
}

/// Tracks grouped by who they are bound to, groups in order of first
/// appearance, tracks in the asset's order within each.
List<TimelineRow> timelineRowsOf(jge.TimelineAsset asset) {
  final groups = <jge.TrackBinding, List<int>>{};
  for (var i = 0; i < asset.tracks.length; i++) {
    groups.putIfAbsent(asset.tracks[i].binding, () => []).add(i);
  }
  return [
    for (final group in groups.entries) ...[
      TimelineGroupRow(group.key),
      for (final i in group.value) TimelineTrackRow(i),
    ],
  ];
}

/// The colour a track draws its items in.
Color timelineTrackColor(jge.TimelineTrack track) => switch (track) {
  jge.PropertyTrack t => switch (t.channel) {
    'x' || 'dx' => GizmoConstants.colX,
    'y' || 'dy' => GizmoConstants.colY,
    'z' => const Color(0xFF5B9BFF),
    _ => EditorTheme.warning,
  },
  jge.EventTrack _ => const Color(0xFFFF9C98),
  jge.SpriteClipTrack _ => const Color(0xFF7DE6B1),
  jge.CameraShotTrack _ => const Color(0xFF7DD8E0),
  jge.AudioTrack _ => const Color(0xFFC79BFF),
  jge.ActivationTrack _ => const Color(0xFFCCCCCC),
  jge.NestedTimelineTrack _ => const Color(0xFFFFCA28),
  _ => EditorTheme.textMuted,
};

/// The ruler: frame ticks, numbers, markers and the playhead's handle.
/// Pressing or dragging on it scrubs.
class TimelineRuler extends StatefulWidget {
  const TimelineRuler({super.key, required this.session, this.onMenu});

  final TimelineSession session;

  /// Secondary click: the time, the marker under the pointer (or null), and
  /// where on screen.
  final void Function(double time, int? marker, Offset globalPosition)? onMenu;

  @override
  State<TimelineRuler> createState() => _TimelineRulerState();
}

class _TimelineRulerState extends State<TimelineRuler> {
  TimelineSession get s => widget.session;

  int? _marker;
  double? _rangeFrom;

  /// An end of the play range being dragged: 0 its start, 1 its end.
  int? _grip;
  bool _hoveringGrip = false;

  /// The timeline as it was when its end was taken hold of.
  jge.TimelineAsset? _endDrag;

  double _timeAt(double x) =>
      s.scrollTime.value +
      (x - TimelineMetrics.leftInset) / s.pixelsPerSecond.value;

  int? _markerAt(Offset local) {
    final markers = s.asset.value!.markers;
    for (var i = markers.length - 1; i >= 0; i--) {
      final x =
          (markers[i].time - s.scrollTime.value) * s.pixelsPerSecond.value +
          TimelineMetrics.leftInset;
      if ((x - local.dx).abs() <= 6 && local.dy <= 10) return i;
    }
    return null;
  }

  double _xOf(double time) =>
      (time - s.scrollTime.value) * s.pixelsPerSecond.value +
      TimelineMetrics.leftInset;

  /// The end of the play range under [local], if the pointer is on one.
  int? _gripAt(Offset local) {
    final range = s.playRange;
    if (range == null) return null;
    for (final (i, time) in [
      (0, range.$1),
      (1, range.$2),
    ].indexed.map((e) => (e.$1, e.$2.$2))) {
      if ((_xOf(time) - local.dx).abs() <= TimelineMetrics.gripWidth) return i;
    }
    return null;
  }

  /// Whether [local] is on the timeline's end, where it can be dragged.
  bool _onEnd(Offset local) =>
      (_xOf(s.duration) - local.dx).abs() <= TimelineMetrics.gripWidth;

  void _dragGrip(Offset local) {
    final range = s.playRange;
    final grip = _grip;
    if (range == null || grip == null) return;
    final at = s.snapTime(_timeAt(local.dx));
    s.setPlayRange(grip == 0 ? at : range.$1, grip == 0 ? range.$2 : at);
  }

  void _scrub(Offset local) => s
    ..pause()
    ..scrubTo(s.snapTime(_timeAt(local.dx)));

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        final local = e.localPosition;
        if (e.buttons == kSecondaryMouseButton) {
          widget.onMenu?.call(_timeAt(local.dx), _markerAt(local), e.position);
          return;
        }
        if (e.buttons != kPrimaryMouseButton) return;
        // An end of the play range beats a marker: it is the thing most
        // often reached for, and it is drawn over the whole height.
        _grip = _gripAt(local);
        if (_grip != null) return;
        // The end of the timeline: drag it to make it longer or shorter.
        if (_onEnd(local)) {
          _endDrag = s.beginDrag();
          return;
        }
        _marker = _markerAt(local);
        if (_marker != null) return;
        if (HardwareKeyboard.instance.isShiftPressed) {
          _rangeFrom = _timeAt(local.dx);
          return;
        }
        _scrub(local);
      },
      onPointerMove: (e) {
        final local = e.localPosition;
        final marker = _marker, from = _rangeFrom;
        if (_grip != null) {
          _dragGrip(local);
          return;
        }
        if (_endDrag case final start?) {
          s.dragDuration(start, _timeAt(local.dx));
          return;
        }
        if (marker != null) {
          final time = s.snapTime(_timeAt(local.dx));
          if (time != s.asset.value!.markers[marker].time) {
            final name = s.asset.value!.markers[marker].name;
            s.updateMarker(marker, time: time);
            // Markers sort by time: keep hold of the one being dragged.
            _marker = s.asset.value!.markers.indexWhere(
              (m) => m.name == name && m.time == time,
            );
            if (_marker! < 0) _marker = null;
          }
        } else if (from != null) {
          s.setWorkRange(from, _timeAt(local.dx));
        } else if (e.buttons == kPrimaryMouseButton) {
          _scrub(local);
        }
      },
      onPointerUp: (_) {
        _marker = null;
        _rangeFrom = null;
        _grip = null;
        if (_endDrag case final start?) {
          s.endDrag(start);
          _endDrag = null;
        }
      },
      onPointerHover: (e) {
        final on = _gripAt(e.localPosition) != null || _onEnd(e.localPosition);
        if (on != _hoveringGrip) setState(() => _hoveringGrip = on);
      },
      onPointerSignal: (e) {
        if (e is! PointerScrollEvent) return;
        if (e.scrollDelta.dx != 0) s.scrollByPixels(e.scrollDelta.dx);
        final dy = e.scrollDelta.dy;
        if (dy == 0) return;
        // The ruler is all one axis, so a plain wheel scrolls it sideways.
        HardwareKeyboard.instance.isControlPressed
            ? s.zoomAround(
                dy < 0 ? 1.15 : 1 / 1.15,
                e.localPosition.dx - TimelineMetrics.leftInset,
              )
            : s.scrollByPixels(dy);
      },
      child: MouseRegion(
        cursor: _hoveringGrip
            ? SystemMouseCursors.resizeLeftRight
            : MouseCursor.defer,
        child: CustomPaint(
          size: const Size(double.infinity, TimelineMetrics.rulerHeight),
          painter: _RulerPainter(
            asset: s.asset.value!,
            pps: s.pixelsPerSecond.value,
            scroll: s.scrollTime.value,
            playhead: s.playhead.value,
            frames: s.showFrames.value,
            range: s.workRange.value,
            playRange: s.playRange,
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.asset,
    required this.pps,
    required this.scroll,
    required this.playhead,
    required this.frames,
    required this.range,
    required this.playRange,
  });

  final jge.TimelineAsset asset;
  final double pps, scroll, playhead;
  final bool frames;
  final (double, double)? range;

  /// What the entity's player will actually run, when it runs only part.
  final (double, double)? playRange;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = EditorTheme.surfaceDark,
    );
    final fps = math.max(1, asset.fps);

    // The smallest of these steps (in frames) whose labels do not collide.
    const steps = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600];
    final perFrame = pps / fps;
    var major = steps.last;
    for (final s in steps) {
      if (s * perFrame >= 56) {
        major = s;
        break;
      }
    }
    final minor = math.max(1, major ~/ 5);
    final tick = Paint()..color = EditorTheme.textMuted.withValues(alpha: 0.5);
    final first = (scroll * fps).floor();
    final last = ((scroll + size.width / pps) * fps).ceil();
    const inset = TimelineMetrics.leftInset;
    for (var f = first - first % minor; f <= last; f += minor) {
      if (f < 0) continue;
      final x = (f / fps - scroll) * pps + inset;
      final isMajor = f % major == 0;
      canvas.drawLine(
        Offset(x, size.height - (isMajor ? 9 : 4)),
        Offset(x, size.height),
        tick,
      );
      if (!isMajor) continue;
      final label = TextPainter(
        text: TextSpan(
          text: frames ? '$f' : (f / fps).toStringAsFixed(f % fps == 0 ? 0 : 2),
          style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + 3, 1));
    }

    // Past the end is not the timeline — and the end itself is a handle.
    final endX = (asset.duration - scroll) * pps + inset;
    if (endX < size.width) {
      canvas.drawRect(
        Rect.fromLTRB(math.max(0, endX), 0, size.width, size.height),
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
    }
    if (endX >= -TimelineMetrics.gripWidth && endX <= size.width) {
      final handle = Paint()..color = EditorTheme.textSecondary;
      canvas
        ..drawRect(Rect.fromLTWH(endX - 1, 0, 2, size.height), handle)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              endX - TimelineMetrics.gripWidth / 2,
              size.height / 2 - 5,
              TimelineMetrics.gripWidth,
              10,
            ),
            const Radius.circular(2),
          ),
          handle,
        );
    }

    // What the entity plays: the rest of the timeline is dimmed, and the two
    // ends carry a grip to drag.
    final play = playRange;
    if (play != null) {
      final from = (play.$1 - scroll) * pps + inset;
      final to = (play.$2 - scroll) * pps + inset;
      final dim = Paint()..color = Colors.black.withValues(alpha: 0.45);
      canvas
        ..drawRect(Rect.fromLTRB(0, 0, math.max(0, from), size.height), dim)
        ..drawRect(Rect.fromLTRB(to, 0, size.width, size.height), dim);
      final edge = Paint()..color = EditorTheme.primaryBright;
      for (final x in [from, to]) {
        canvas
          ..drawRect(Rect.fromLTWH(x - 1, 0, 2, size.height), edge)
          ..drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                x - TimelineMetrics.gripWidth / 2,
                size.height / 2 - 6,
                TimelineMetrics.gripWidth,
                12,
              ),
              const Radius.circular(2),
            ),
            edge,
          );
      }
      _text(
        canvas,
        'plays',
        Offset(math.max(2, from + 6), size.height - 12),
        EditorTheme.primaryBright,
      );
    }

    // The stretch being worked on: an editor's own, and only a loop.
    final work = range;
    if (work != null) {
      final from = (work.$1 - scroll) * pps + inset;
      final to = (work.$2 - scroll) * pps + inset;
      canvas
        ..drawRect(
          Rect.fromLTRB(from, size.height - 5, to, size.height),
          Paint()..color = GizmoConstants.colSel,
        )
        ..drawRect(
          Rect.fromLTRB(from, 0, to, size.height),
          Paint()..color = GizmoConstants.colSel.withValues(alpha: 0.10),
        );
    }

    for (final m in asset.markers) {
      final x = (m.time - scroll) * pps + inset;
      if (x < -40 || x > size.width) continue;
      final paint = Paint()..color = EditorTheme.warning;
      canvas.drawPath(
        Path()
          ..moveTo(x - 4, 0)
          ..lineTo(x + 4, 0)
          ..lineTo(x, 7)
          ..close(),
        paint,
      );
      final label = TextPainter(
        text: TextSpan(
          text: m.name,
          style: TextStyle(color: EditorTheme.warning, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + 6, 0));
    }

    final px = (playhead - scroll) * pps + inset;
    if (px >= -6 && px <= size.width + 6) {
      canvas.drawPath(
        Path()
          ..moveTo(px - 5, size.height - 10)
          ..lineTo(px + 5, size.height - 10)
          ..lineTo(px, size.height)
          ..close(),
        Paint()..color = EditorTheme.primaryBright,
      );
    }
  }

  void _text(Canvas canvas, String text, Offset at, Color color) {
    TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..paint(canvas, at);
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.asset != asset ||
      old.pps != pps ||
      old.scroll != scroll ||
      old.playhead != playhead ||
      old.frames != frames ||
      old.range != range ||
      old.playRange != playRange;
}

/// The sheet under the ruler. One widget for every row, so a box can be
/// dragged across rows and the playhead is one line.
class DopeSheet extends StatefulWidget {
  const DopeSheet({
    super.key,
    required this.session,
    required this.rows,
    required this.verticalScroll,
    this.onItemMenu,
    this.onEmptyDoubleTap,
  });

  final TimelineSession session;
  final List<TimelineRow> rows;

  /// The tree's scroll controller: the sheet draws at its offset rather than
  /// scrolling by itself, so the two can never drift apart.
  final ScrollController verticalScroll;

  /// Secondary click on an item.
  final void Function(TimelineItemRef ref, Offset globalPosition)? onItemMenu;

  /// Double click where there is no item: the track's index and the time.
  final void Function(int track, double time)? onEmptyDoubleTap;

  @override
  State<DopeSheet> createState() => DopeSheetState();
}

class DopeSheetState extends State<DopeSheet> {
  TimelineSession get s => widget.session;

  // A drag of items.
  jge.TimelineAsset? _dragStart;
  Set<TimelineItemRef> _dragRefs = const {};
  double _dragFromTime = 0;

  // Alt held as the drag began: stretch the selection about its first item
  // instead of moving it.
  bool _scaling = false;

  /// The timeline as it was when its end was taken hold of.
  jge.TimelineAsset? _endDrag;

  // An edge of a block being dragged: true for its start.
  bool? _trimLeading;
  TimelineItemRef? _trimRef;
  MouseCursor _cursor = SystemMouseCursors.basic;
  double _scalePivot = 0;

  // A box being dragged out, in local pixels.
  Offset? _boxFrom;
  Offset? _boxTo;
  Set<TimelineItemRef> _boxBase = const {};

  // Panning with the middle button.
  bool _panning = false;

  /// When the last press landed, by the *event's* clock rather than the
  /// wall's: that is the device's time in a game and the test's time under
  /// a test, so a double click means the same thing in both.
  Duration _lastDown = Duration.zero;
  Offset _lastDownAt = Offset.zero;

  double get _offsetY =>
      widget.verticalScroll.hasClients ? widget.verticalScroll.offset : 0;

  double timeAt(double x) =>
      s.scrollTime.value +
      (x - TimelineMetrics.leftInset) / s.pixelsPerSecond.value;
  double xOf(double time) =>
      (time - s.scrollTime.value) * s.pixelsPerSecond.value +
      TimelineMetrics.leftInset;

  /// The row under local [y], or null.
  TimelineRow? rowAt(double y) {
    final i = ((y + _offsetY) / TimelineMetrics.rowHeight).floor();
    return i >= 0 && i < widget.rows.length ? widget.rows[i] : null;
  }

  /// The item under [local], or null. Keys and events are points; blocks
  /// are spans.
  TimelineItemRef? itemAt(Offset local) {
    final row = rowAt(local.dy);
    if (row is! TimelineTrackRow) return null;
    final track = s.asset.value!.tracks[row.index];
    TimelineItemRef? best;
    var bestDistance = TimelineMetrics.hitSlop;
    void point(int i, double time) {
      final d = (xOf(time) - local.dx).abs();
      if (d <= bestDistance) {
        bestDistance = d;
        best = TimelineItemRef(row.index, i);
      }
    }

    if (track is jge.PropertyTrack) {
      for (var i = 0; i < track.curve.keys.length; i++) {
        point(i, track.curve.keys[i].time);
      }
    } else if (track is jge.EventTrack) {
      for (var i = 0; i < track.events.length; i++) {
        point(i, track.events[i].time);
      }
    } else if (track is jge.BlockTrack) {
      for (var i = track.blocks.length - 1; i >= 0; i--) {
        final b = track.blocks[i];
        if (track.isInstant) {
          point(i, b.start);
        } else if (local.dx >= xOf(b.start) && local.dx <= xOf(b.end)) {
          return TimelineItemRef(row.index, i);
        }
      }
    }
    return best;
  }

  /// The block edge under [local]: the block and whether it is its start.
  (TimelineItemRef, bool)? edgeAt(Offset local) {
    final row = rowAt(local.dy);
    if (row is! TimelineTrackRow) return null;
    final track = s.asset.value!.tracks[row.index];
    if (track is! jge.BlockTrack || track.isInstant || track.locked) {
      return null;
    }
    for (var i = track.blocks.length - 1; i >= 0; i--) {
      final b = track.blocks[i];
      // Only the outer few pixels, and never so much that a short block has
      // no middle left to move it by.
      final grip = math.min(5.0, (xOf(b.end) - xOf(b.start)) / 4);
      if ((local.dx - xOf(b.start)).abs() <= grip) {
        return (TimelineItemRef(row.index, i), true);
      }
      if ((local.dx - xOf(b.end)).abs() <= grip) {
        return (TimelineItemRef(row.index, i), false);
      }
    }
    return null;
  }

  /// Whether [local] is on the timeline's end, with no item in the way.
  bool _onEnd(Offset local) =>
      (xOf(s.duration) - local.dx).abs() <= TimelineMetrics.gripWidth &&
      itemAt(local) == null;

  void _hover(PointerHoverEvent e) {
    final next = edgeAt(e.localPosition) != null || _onEnd(e.localPosition)
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.basic;
    if (next != _cursor) setState(() => _cursor = next);
  }

  void _down(PointerDownEvent e) {
    final local = e.localPosition;
    if (e.buttons == kMiddleMouseButton) {
      _panning = true;
      return;
    }
    final hit = itemAt(local);
    if (e.buttons == kSecondaryMouseButton) {
      if (hit != null) {
        if (!s.selection.value.contains(hit)) s.selection.value = {hit};
        widget.onItemMenu?.call(hit, e.position);
      }
      return;
    }
    if (e.buttons != kPrimaryMouseButton) return;

    final now = e.timeStamp;
    final isDouble =
        now - _lastDown < const Duration(milliseconds: 350) &&
        (local - _lastDownAt).distance < 6;
    _lastDown = now;
    _lastDownAt = local;

    final row = rowAt(local.dy);
    if (row is TimelineTrackRow) s.selectedTrack.value = row.index;

    final keys = HardwareKeyboard.instance;
    final additive = keys.isShiftPressed || keys.isControlPressed;

    // The timeline's end, when no key sits on it. A key there wins: the
    // ruler carries the same handle, with nothing to compete with it.
    if (hit == null && !additive && _onEnd(local)) {
      _endDrag = s.beginDrag();
      return;
    }

    if (hit == null) {
      if (isDouble && row is TimelineTrackRow) {
        widget.onEmptyDoubleTap?.call(row.index, timeAt(local.dx));
        return;
      }
      _boxBase = additive ? s.selection.value : const {};
      if (!additive) s.selection.value = const {};
      setState(() {
        _boxFrom = local;
        _boxTo = local;
      });
      return;
    }

    final edge = additive ? null : edgeAt(local);
    if (edge != null) {
      s.selection.value = {edge.$1};
      _dragStart = s.beginDrag();
      _trimRef = edge.$1;
      _trimLeading = edge.$2;
      return;
    }

    final selected = s.selection.value;
    if (additive) {
      s.selection.value = selected.contains(hit)
          ? ({...selected}..remove(hit))
          : {...selected, hit};
      return;
    }
    if (!selected.contains(hit)) s.selection.value = {hit};
    // Shown at the key, so what is being moved is what is seen.
    final at = s.timeOf(hit);
    if (at != null) {
      s
        ..pause()
        ..scrubTo(at);
    }
    _dragStart = s.beginDrag();
    _dragRefs = s.selection.value;
    _dragFromTime = timeAt(local.dx);
    final times = [for (final r in _dragRefs) s.timeOf(r) ?? 0.0];
    _scalePivot = times.reduce(math.min);
    _scaling =
        keys.isAltPressed &&
        _dragRefs.length > 1 &&
        _dragFromTime - _scalePivot > 1e-3;
  }

  void _move(PointerMoveEvent e) {
    final local = e.localPosition;
    if (_panning) {
      // Middle-drag takes the sheet with the pointer, both ways.
      s.scrollByPixels(-e.delta.dx);
      scrollVerticallyBy(-e.delta.dy);
      return;
    }
    if (_endDrag case final start?) {
      s.dragDuration(start, timeAt(local.dx));
      return;
    }
    final start = _dragStart;
    final trimming = _trimRef;
    if (start != null && trimming != null) {
      // Measured from where the drag began, so the index into [start] holds.
      s.dragTrim(start, trimming, timeAt(local.dx), leadingEdge: _trimLeading!);
      return;
    }
    if (start != null) {
      if (_scaling) {
        final factor =
            (timeAt(local.dx) - _scalePivot) / (_dragFromTime - _scalePivot);
        s.dragScale(start, _dragRefs, math.max(0.05, factor));
      } else {
        s.dragItems(start, _dragRefs, timeAt(local.dx) - _dragFromTime);
      }
      return;
    }
    if (_boxFrom != null) {
      setState(() => _boxTo = local);
      s.selection.value = {..._boxBase, ..._itemsIn(_box!)};
    }
  }

  void _up(PointerEvent e) {
    _panning = false;
    if (_endDrag case final start?) {
      s.endDrag(start);
      _endDrag = null;
    }
    final start = _dragStart;
    if (start != null) {
      s.endDrag(start);
      _dragStart = null;
      _trimRef = null;
      _trimLeading = null;
    }
    if (_boxFrom != null) {
      setState(() {
        _boxFrom = null;
        _boxTo = null;
      });
    }
  }

  Rect? get _box => _boxFrom == null || _boxTo == null
      ? null
      : Rect.fromPoints(_boxFrom!, _boxTo!);

  Set<TimelineItemRef> _itemsIn(Rect box) {
    final found = <TimelineItemRef>{};
    final tracks = s.asset.value!.tracks;
    for (var r = 0; r < widget.rows.length; r++) {
      final row = widget.rows[r];
      if (row is! TimelineTrackRow) continue;
      final top = r * TimelineMetrics.rowHeight - _offsetY;
      if (top + TimelineMetrics.rowHeight < box.top || top > box.bottom) {
        continue;
      }
      final track = tracks[row.index];
      bool inX(double from, double to) =>
          xOf(to) >= box.left && xOf(from) <= box.right;
      if (track is jge.PropertyTrack) {
        for (var i = 0; i < track.curve.keys.length; i++) {
          final t = track.curve.keys[i].time;
          if (inX(t, t)) found.add(TimelineItemRef(row.index, i));
        }
      } else if (track is jge.EventTrack) {
        for (var i = 0; i < track.events.length; i++) {
          final t = track.events[i].time;
          if (inX(t, t)) found.add(TimelineItemRef(row.index, i));
        }
      } else if (track is jge.BlockTrack) {
        for (var i = 0; i < track.blocks.length; i++) {
          final b = track.blocks[i];
          if (inX(b.start, track.isInstant ? b.start : b.end)) {
            found.add(TimelineItemRef(row.index, i));
          }
        }
      }
    }
    return found;
  }

  void _scroll(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    // A wheel tilt or a trackpad's sideways swipe always scrolls sideways,
    // whatever else the wheel is doing.
    if (e.scrollDelta.dx != 0) s.scrollByPixels(e.scrollDelta.dx);
    final dy = e.scrollDelta.dy;
    if (dy == 0) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed) {
      s.zoomAround(dy < 0 ? 1.15 : 1 / 1.15, timeAtPixels(e.localPosition.dx));
    } else if (keys.isShiftPressed) {
      s.scrollByPixels(dy);
    } else {
      scrollVerticallyBy(dy);
    }
  }

  /// Moves the rows under the sheet by [pixels]; the tree scrolls with them.
  void scrollVerticallyBy(double pixels) {
    if (!widget.verticalScroll.hasClients) return;
    final p = widget.verticalScroll.position;
    p.jumpTo((p.pixels + pixels).clamp(0.0, p.maxScrollExtent));
  }

  /// [x] in local pixels as an offset from the sheet's left edge.
  static double timeAtPixels(double x) => x - TimelineMetrics.leftInset;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      onPointerSignal: _scroll,
      onPointerHover: _hover,
      child: MouseRegion(
        cursor: _cursor,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: widget.verticalScroll,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: _SheetPainter(
                asset: s.asset.value!,
                rows: widget.rows,
                pps: s.pixelsPerSecond.value,
                scroll: s.scrollTime.value,
                offsetY: _offsetY,
                playhead: s.playhead.value,
                selection: s.selection.value,
                selectedTrack: s.selectedTrack.value,
                box: _box,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetPainter extends CustomPainter {
  _SheetPainter({
    required this.asset,
    required this.rows,
    required this.pps,
    required this.scroll,
    required this.offsetY,
    required this.playhead,
    required this.selection,
    required this.selectedTrack,
    required this.box,
  });

  final jge.TimelineAsset asset;
  final List<TimelineRow> rows;
  final double pps, scroll, offsetY, playhead;
  final Set<TimelineItemRef> selection;
  final int? selectedTrack;
  final Rect? box;

  double x(double time) => (time - scroll) * pps + TimelineMetrics.leftInset;

  @override
  void paint(Canvas canvas, Size size) {
    const h = TimelineMetrics.rowHeight;
    canvas.drawRect(Offset.zero & size, Paint()..color = EditorTheme.panelBg);

    final line = Paint()
      ..color = EditorTheme.textPrimary.withValues(alpha: 0.05);
    final firstRow = math.max(0, (offsetY / h).floor());
    final lastRow = math.min(
      rows.length - 1,
      ((offsetY + size.height) / h).ceil(),
    );
    for (var r = firstRow; r <= lastRow; r++) {
      final top = r * h - offsetY;
      final row = rows[r];
      if (row is TimelineGroupRow) {
        canvas.drawRect(
          Rect.fromLTWH(0, top, size.width, h),
          Paint()..color = EditorTheme.surfaceDark,
        );
        continue;
      }
      final index = (row as TimelineTrackRow).index;
      if (index == selectedTrack) {
        canvas.drawRect(
          Rect.fromLTWH(0, top, size.width, h),
          Paint()..color = EditorTheme.selectionBg.withValues(alpha: 0.45),
        );
      }
      canvas.drawLine(Offset(0, top + h), Offset(size.width, top + h), line);
      _track(canvas, size, asset.tracks[index], index, top);
    }

    // Past the end is not the timeline; the line is the end itself, which
    // can be dragged from here or from the ruler.
    final endX = x(asset.duration);
    if (endX < size.width) {
      canvas.drawRect(
        Rect.fromLTRB(math.max(0, endX), 0, size.width, size.height),
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(endX - 1, 0, 2, size.height),
      Paint()..color = EditorTheme.textSecondary.withValues(alpha: 0.45),
    );
    for (final m in asset.markers) {
      canvas.drawLine(
        Offset(x(m.time), 0),
        Offset(x(m.time), size.height),
        Paint()..color = EditorTheme.warning.withValues(alpha: 0.25),
      );
    }

    final px = x(playhead);
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      Paint()
        ..color = EditorTheme.primaryBright
        ..strokeWidth = 1.2,
    );

    final area = box;
    if (area != null) {
      canvas
        ..drawRect(
          area,
          Paint()..color = GizmoConstants.colSel.withValues(alpha: 0.12),
        )
        ..drawRect(
          area,
          Paint()
            ..color = GizmoConstants.colSel
            ..style = PaintingStyle.stroke,
        );
    }
  }

  void _track(
    Canvas canvas,
    Size size,
    jge.TimelineTrack track,
    int index,
    double top,
  ) {
    const h = TimelineMetrics.rowHeight;
    final cy = top + h / 2;
    final base = timelineTrackColor(track);
    final color = track.muted ? base.withValues(alpha: 0.35) : base;
    bool selected(int i) => selection.contains(TimelineItemRef(index, i));

    if (track is jge.PropertyTrack) {
      final keys = track.curve.keys;
      if (keys.length > 1) {
        canvas.drawLine(
          Offset(x(keys.first.time), cy),
          Offset(x(keys.last.time), cy),
          Paint()
            ..color = color.withValues(alpha: 0.3)
            ..strokeWidth = 2,
        );
      }
      for (var i = 0; i < keys.length; i++) {
        _diamond(
          canvas,
          Offset(x(keys[i].time), cy),
          color,
          selected(i),
          hollow: keys[i].interpolation == jge.KeyInterpolation.step,
        );
      }
    } else if (track is jge.EventTrack) {
      for (var i = 0; i < track.events.length; i++) {
        final e = track.events[i];
        final at = Offset(x(e.time), cy);
        canvas.drawPath(
          Path()
            ..moveTo(at.dx, top + 4)
            ..lineTo(at.dx + 7, top + 8)
            ..lineTo(at.dx, top + 12)
            ..close(),
          Paint()..color = selected(i) ? GizmoConstants.colSel : color,
        );
        canvas.drawLine(
          Offset(at.dx, top + 4),
          Offset(at.dx, top + h - 3),
          Paint()
            ..color = selected(i) ? GizmoConstants.colSel : color
            ..strokeWidth = 1.5,
        );
        _label(canvas, e.name, Offset(at.dx + 9, top + 10), color, 120);
      }
    } else if (track is jge.BlockTrack) {
      for (var i = 0; i < track.blocks.length; i++) {
        final b = track.blocks[i];
        if (track.isInstant) {
          _diamond(canvas, Offset(x(b.start), cy), color, selected(i));
          _label(
            canvas,
            b.value.split('/').last,
            Offset(x(b.start) + 8, top + 6),
            color,
            140,
          );
          continue;
        }
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTRB(x(b.start), top + 3, x(b.end), top + h - 3),
          const Radius.circular(3),
        );
        canvas
          ..drawRRect(rect, Paint()..color = color.withValues(alpha: 0.28))
          ..drawRRect(
            rect,
            Paint()
              ..color = selected(i) ? GizmoConstants.colSel : color
              ..style = PaintingStyle.stroke
              ..strokeWidth = selected(i) ? 1.6 : 1,
          );
        _label(
          canvas,
          b.value.split('/').last,
          Offset(x(b.start) + 5, top + 6),
          EditorTheme.textPrimary,
          math.max(0, rect.width - 8),
        );
      }
    }
  }

  void _diamond(
    Canvas canvas,
    Offset at,
    Color color,
    bool selected, {
    bool hollow = false,
  }) {
    const r = TimelineMetrics.keySize / 2;
    final path = Path()
      ..moveTo(at.dx, at.dy - r)
      ..lineTo(at.dx + r, at.dy)
      ..lineTo(at.dx, at.dy + r)
      ..lineTo(at.dx - r, at.dy)
      ..close();
    final fill = selected ? GizmoConstants.colSel : color;
    if (hollow) {
      canvas.drawPath(path, Paint()..color = EditorTheme.panelBg);
    } else {
      canvas.drawPath(path, Paint()..color = fill);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = selected ? Colors.white : fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 1.4 : 1,
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at,
    Color color,
    double maxWidth,
  ) {
    if (text.isEmpty || maxWidth < 12) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_SheetPainter old) => true;
}
