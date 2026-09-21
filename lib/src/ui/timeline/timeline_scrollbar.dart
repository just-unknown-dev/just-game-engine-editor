/// The bar under the sheet: how much of the timeline is on screen, and a
/// thumb to drag along it.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';
import 'timeline_session.dart';

class TimelineScrollBar extends StatefulWidget {
  const TimelineScrollBar({super.key, required this.session});

  final TimelineSession session;

  static const double height = 10;

  /// A thumb narrower than this cannot be grabbed.
  static const double minThumb = 28;

  @override
  State<TimelineScrollBar> createState() => _TimelineScrollBarState();
}

class _TimelineScrollBarState extends State<TimelineScrollBar> {
  TimelineSession get s => widget.session;

  bool _dragging = false;
  bool _hovered = false;

  /// The whole stretch the bar stands for: what there is, plus the room the
  /// sheet may scroll into past it.
  double get _total => math.max(s.scrollEnd, s.maxScroll + s.visibleSpan);

  /// The thumb, in pixels along a bar [width] wide.
  (double, double) _thumb(double width) {
    final total = _total;
    if (total <= 0 || s.visibleSpan <= 0) return (0, width);
    final size = math.max(
      TimelineScrollBar.minThumb,
      width * (s.visibleSpan / total).clamp(0.0, 1.0),
    );
    final room = s.maxScroll;
    final at = room <= 0 ? 0.0 : (s.scrollTime.value / room) * (width - size);
    return (at.clamp(0.0, width - size), size);
  }

  /// Puts the thumb's middle under [x].
  void _jumpTo(double x, double width) {
    final (_, size) = _thumb(width);
    final room = width - size;
    if (room <= 0) return;
    s.scrollTo(((x - size / 2) / room) * s.maxScroll);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final (at, size) = _thumb(width);
        // Nothing to scroll: the bar stays as a hairline, so the sheet does
        // not change height as you zoom.
        final idle = s.maxScroll <= 0;
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              if (e.buttons != kPrimaryMouseButton || idle) return;
              final x = e.localPosition.dx;
              // Beside the thumb: jump there. On it: pick it up where it is.
              if (x < at || x > at + size) _jumpTo(x, width);
              setState(() => _dragging = true);
            },
            onPointerMove: (e) {
              if (!_dragging) return;
              final room = width - size;
              if (room <= 0) return;
              s.scrollBy(e.delta.dx / room * s.maxScroll);
            },
            onPointerUp: (_) => setState(() => _dragging = false),
            onPointerCancel: (_) => setState(() => _dragging = false),
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                s.scrollByPixels(e.scrollDelta.dx + e.scrollDelta.dy);
              }
            },
            child: SizedBox(
              height: TimelineScrollBar.height,
              child: CustomPaint(
                painter: _BarPainter(
                  at: at,
                  size: size,
                  idle: idle,
                  bright: _dragging || _hovered,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.at,
    required this.size,
    required this.idle,
    required this.bright,
  });

  final double at;
  final double size;
  final bool idle;
  final bool bright;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    canvas.drawRect(
      Offset.zero & canvasSize,
      Paint()..color = EditorTheme.surfaceDarker,
    );
    if (idle) return;
    final track = Rect.fromLTWH(at, 2.5, size, canvasSize.height - 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, const Radius.circular(2.5)),
      Paint()
        ..color = EditorTheme.textPrimary.withValues(
          alpha: bright ? 0.34 : 0.18,
        ),
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.at != at ||
      old.size != size ||
      old.idle != idle ||
      old.bright != bright;
}
