/// The curve editor: the value of number tracks over time, with the keys
/// and their bezier handles to drag. It shares the ruler, the zoom, the
/// playhead and the selection with the dope sheet it swaps places with.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/constants/editor_constants.dart';
import 'dope_sheet.dart';
import 'timeline_session.dart';

/// Which handle of a key.
enum CurveHandle { incoming, outgoing }

class CurveView extends StatefulWidget {
  const CurveView({super.key, required this.session, this.onItemMenu});

  final TimelineSession session;
  final void Function(TimelineItemRef ref, Offset globalPosition)? onItemMenu;

  @override
  State<CurveView> createState() => CurveViewState();
}

class CurveViewState extends State<CurveView> {
  TimelineSession get s => widget.session;

  static const double _pad = 16;

  // The value range shown. Held still during a drag, so the thing being
  // dragged does not slide about under the pointer.
  double _lo = 0, _hi = 1;
  Size _size = Size.zero;

  jge.TimelineAsset? _dragStart;
  Set<TimelineItemRef> _dragRefs = const {};
  Offset _dragFrom = Offset.zero;
  (TimelineItemRef, CurveHandle)? _handle;

  Offset? _boxFrom, _boxTo;
  Set<TimelineItemRef> _boxBase = const {};
  bool _panning = false;

  /// When the last press landed, by the *event's* clock rather than the
  /// wall's: that is the device's time in a game and the test's time under
  /// a test, so a double click means the same thing in both.
  Duration _lastDown = Duration.zero;
  Offset _lastDownAt = Offset.zero;

  /// The tracks whose curves are drawn: the selected one and any with a
  /// selected key — or, with nothing chosen, every number track.
  List<int> get shown {
    final tracks = s.asset.value!.tracks;
    bool drawable(int i) {
      final t = tracks[i];
      return t is jge.PropertyTrack &&
          !t.isColor &&
          t.curve.keys.any((k) => k.value is num);
    }

    final chosen = <int>{
      if (s.selectedTrack.value case final i? when i < tracks.length) i,
      for (final r in s.selection.value) r.track,
    }.where(drawable).toList()..sort();
    if (chosen.isNotEmpty) return chosen;
    return [
      for (var i = 0; i < tracks.length; i++)
        if (drawable(i)) i,
    ];
  }

  void _fit() {
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final i in shown) {
      final curve = (s.asset.value!.tracks[i] as jge.PropertyTrack).curve;
      // Sampled, not just the keys: a bezier or a bounce goes past them.
      final end = math.max(curve.end, 1e-6);
      for (var n = 0; n <= 64; n++) {
        final v = curve.numberAt(end * n / 64);
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (lo == double.infinity) {
      lo = 0;
      hi = 1;
    }
    if (hi - lo < 1e-6) {
      lo -= 0.5;
      hi += 0.5;
    }
    _lo = lo;
    _hi = hi;
  }

  double xOf(double time) =>
      (time - s.scrollTime.value) * s.pixelsPerSecond.value +
      TimelineMetrics.leftInset;
  double timeAt(double x) =>
      s.scrollTime.value +
      (x - TimelineMetrics.leftInset) / s.pixelsPerSecond.value;
  double yOf(double value) =>
      _pad + (1 - (value - _lo) / (_hi - _lo)) * (_size.height - 2 * _pad);
  double valueAt(double y) =>
      _lo + (1 - (y - _pad) / (_size.height - 2 * _pad)) * (_hi - _lo);

  /// Value per pixel, for turning a drag into a change of value.
  double get _valuePerPixel => (_hi - _lo) / (_size.height - 2 * _pad);

  Offset keyPoint(jge.TimelineKey k) => Offset(xOf(k.time), yOf(k.number));

  /// Where a handle is drawn: its tangent from the key, in pixels.
  Offset handlePoint(jge.TimelineKey k, CurveHandle h) {
    final t = h == CurveHandle.outgoing ? k.outTangent : k.inTangent;
    return Offset(xOf(k.time + t.dt), yOf(k.number + t.dv));
  }

  /// The handles a key shows: towards a neighbour it reaches by a bezier.
  List<CurveHandle> handlesOf(jge.KeyCurve curve, int index) => [
    if (index > 0 &&
        curve.keys[index - 1].interpolation == jge.KeyInterpolation.bezier)
      CurveHandle.incoming,
    if (index < curve.keys.length - 1 &&
        curve.keys[index].interpolation == jge.KeyInterpolation.bezier)
      CurveHandle.outgoing,
  ];

  TimelineItemRef? _keyAt(Offset local) {
    TimelineItemRef? best;
    var bestDistance = TimelineMetrics.hitSlop + 1;
    for (final t in shown) {
      final keys = (s.asset.value!.tracks[t] as jge.PropertyTrack).curve.keys;
      for (var i = 0; i < keys.length; i++) {
        if (keys[i].value is! num) continue;
        final d = (keyPoint(keys[i]) - local).distance;
        if (d < bestDistance) {
          bestDistance = d;
          best = TimelineItemRef(t, i);
        }
      }
    }
    return best;
  }

  (TimelineItemRef, CurveHandle)? _handleAt(Offset local) {
    for (final r in s.selection.value) {
      final track = s.asset.value!.tracks[r.track];
      if (track is! jge.PropertyTrack || track.locked) continue;
      if (r.index >= track.curve.keys.length) continue;
      final key = track.curve.keys[r.index];
      for (final h in handlesOf(track.curve, r.index)) {
        if ((handlePoint(key, h) - local).distance <= TimelineMetrics.hitSlop) {
          return (r, h);
        }
      }
    }
    return null;
  }

  void _down(PointerDownEvent e) {
    final local = e.localPosition;
    if (e.buttons == kMiddleMouseButton) {
      _panning = true;
      return;
    }
    if (e.buttons == kSecondaryMouseButton) {
      final hit = _keyAt(local);
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

    // A handle wins over the key under it: it is the smaller target.
    final handle = _handleAt(local);
    if (handle != null) {
      _handle = handle;
      _dragStart = s.beginDrag();
      _dragFrom = local;
      return;
    }

    final keys = HardwareKeyboard.instance;
    final additive = keys.isShiftPressed || keys.isControlPressed;
    final hit = _keyAt(local);
    if (hit == null) {
      if (isDouble) {
        _addKeyAt(local);
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
    final selected = s.selection.value;
    if (additive) {
      s.selection.value = selected.contains(hit)
          ? ({...selected}..remove(hit))
          : {...selected, hit};
      return;
    }
    if (!selected.contains(hit)) s.selection.value = {hit};
    _dragStart = s.beginDrag();
    _dragRefs = s.selection.value;
    _dragFrom = local;
  }

  /// A double click adds a key to the curve nearest the pointer, on it.
  void _addKeyAt(Offset local) {
    final time = timeAt(local.dx);
    int? nearest;
    var distance = 24.0;
    for (final t in shown) {
      final track = s.asset.value!.tracks[t] as jge.PropertyTrack;
      if (track.locked) continue;
      final d = (yOf(track.curve.numberAt(time)) - local.dy).abs();
      if (d < distance) {
        distance = d;
        nearest = t;
      }
    }
    if (nearest == null) return;
    final ref = s.setKey(nearest, time);
    if (ref != null) s.selection.value = {ref};
  }

  void _move(PointerMoveEvent e) {
    final local = e.localPosition;
    if (_panning) {
      s.scrollByPixels(-e.delta.dx);
      return;
    }
    final start = _dragStart;
    final handle = _handle;
    if (start != null && handle != null) {
      final key = (start.tracks[handle.$1.track] as jge.PropertyTrack)
          .curve
          .keys[handle.$1.index];
      s.dragTangent(
        start,
        handle.$1,
        handle.$2 == CurveHandle.outgoing,
        jge.KeyTangent(
          timeAt(local.dx) - key.time,
          valueAt(local.dy) - key.number,
        ),
        // Alt pulls one handle free of the other.
        breakApart: HardwareKeyboard.instance.isAltPressed,
      );
      return;
    }
    if (start != null) {
      final delta = local - _dragFrom;
      // Shift keeps the move to whichever way it mostly goes.
      final shift = HardwareKeyboard.instance.isShiftPressed;
      final alongTime = delta.dx.abs() >= delta.dy.abs();
      s.dragKeys(
        start,
        _dragRefs,
        shift && !alongTime ? 0 : delta.dx / s.pixelsPerSecond.value,
        shift && alongTime ? 0 : -delta.dy * _valuePerPixel,
      );
      return;
    }
    if (_boxFrom != null) {
      setState(() => _boxTo = local);
      final box = Rect.fromPoints(_boxFrom!, _boxTo!);
      s.selection.value = {
        ..._boxBase,
        for (final t in shown)
          for (final (i, k)
              in (s.asset.value!.tracks[t] as jge.PropertyTrack)
                  .curve
                  .keys
                  .indexed)
            if (k.value is num && box.contains(keyPoint(k)))
              TimelineItemRef(t, i),
      };
    }
  }

  void _up(PointerEvent e) {
    _panning = false;
    final start = _dragStart;
    if (start != null) {
      s.endDrag(start);
      _dragStart = null;
      _handle = null;
    }
    if (_boxFrom != null) {
      setState(() {
        _boxFrom = null;
        _boxTo = null;
      });
    }
  }

  void _scroll(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    if (e.scrollDelta.dx != 0) s.scrollByPixels(e.scrollDelta.dx);
    final dy = e.scrollDelta.dy;
    if (dy == 0) return;
    // The value axis fits itself, so a plain wheel scrolls through time.
    HardwareKeyboard.instance.isControlPressed
        ? s.zoomAround(
            dy < 0 ? 1.15 : 1 / 1.15,
            e.localPosition.dx - TimelineMetrics.leftInset,
          )
        : s.scrollByPixels(dy);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        if (_dragStart == null) _fit();
        final tracks = shown;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          onPointerSignal: _scroll,
          child: ClipRect(
            child: tracks.isEmpty
                ? Center(
                    child: Text(
                      'No number tracks with keys to draw.',
                      style: TextStyle(
                        color: EditorTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  )
                : CustomPaint(
                    size: Size.infinite,
                    painter: _CurvePainter(this, tracks),
                  ),
          ),
        );
      },
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.view, this.tracks);

  final CurveViewState view;
  final List<int> tracks;

  @override
  void paint(Canvas canvas, Size size) {
    final s = view.s;
    final asset = s.asset.value!;
    canvas.drawRect(Offset.zero & size, Paint()..color = EditorTheme.panelBg);

    // Value grid: a step from 1, 2, 5 × 10ⁿ that leaves lines ~40 px apart.
    final range = view._hi - view._lo;
    final rough = range / math.max(2, size.height / 40);
    final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor());
    final step = [1, 2, 5, 10]
        .map((m) => m * magnitude)
        .firstWhere((v) => v >= rough, orElse: () => 10 * magnitude)
        .toDouble();
    final grid = Paint()
      ..color = EditorTheme.textPrimary.withValues(alpha: 0.06);
    for (var v = (view._lo / step).floor() * step; v <= view._hi; v += step) {
      final y = view.yOf(v);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      final label = TextPainter(
        text: TextSpan(
          text: v.abs() < 1e-9 ? '0' : v.toStringAsFixed(step < 1 ? 2 : 0),
          style: TextStyle(color: EditorTheme.textMuted, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(2, y - 11));
    }

    final endX = view.xOf(asset.duration);
    if (endX < size.width) {
      canvas.drawRect(
        Rect.fromLTRB(math.max(0, endX), 0, size.width, size.height),
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
    }

    for (final t in tracks) {
      final track = asset.tracks[t] as jge.PropertyTrack;
      final color = timelineTrackColor(
        track,
      ).withValues(alpha: track.muted ? 0.35 : 1);
      final curve = track.curve;
      final path = Path();
      var started = false;
      for (var px = 0.0; px <= size.width; px += 2) {
        final y = view.yOf(curve.numberAt(view.timeAt(px)));
        started ? path.lineTo(px, y) : path.moveTo(px, y);
        started = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      for (var i = 0; i < curve.keys.length; i++) {
        final key = curve.keys[i];
        if (key.value is! num) continue;
        final at = view.keyPoint(key);
        final selected = s.selection.value.contains(TimelineItemRef(t, i));
        if (selected) {
          for (final h in view.handlesOf(curve, i)) {
            final to = view.handlePoint(key, h);
            canvas
              ..drawLine(
                at,
                to,
                Paint()
                  ..color = EditorTheme.textSecondary.withValues(alpha: 0.7),
              )
              ..drawCircle(to, 3.5, Paint()..color = EditorTheme.panelBg)
              ..drawCircle(
                to,
                3.5,
                Paint()
                  ..color = EditorTheme.textSecondary
                  ..style = PaintingStyle.stroke,
              );
          }
        }
        final box = Rect.fromCenter(center: at, width: 7, height: 7);
        canvas
          ..drawRect(
            box,
            Paint()..color = selected ? GizmoConstants.colSel : color,
          )
          ..drawRect(
            box,
            Paint()
              ..color = selected ? Colors.white : EditorTheme.panelBg
              ..style = PaintingStyle.stroke,
          );
      }
    }

    final px = view.xOf(s.playhead.value);
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      Paint()
        ..color = EditorTheme.primaryBright
        ..strokeWidth = 1.2,
    );

    final from = view._boxFrom, to = view._boxTo;
    if (from != null && to != null) {
      final box = Rect.fromPoints(from, to);
      canvas
        ..drawRect(
          box,
          Paint()..color = GizmoConstants.colSel.withValues(alpha: 0.12),
        )
        ..drawRect(
          box,
          Paint()
            ..color = GizmoConstants.colSel
            ..style = PaintingStyle.stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}
