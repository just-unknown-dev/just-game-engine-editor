import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:just_editor_core/host.dart';
import 'gizmo_painter.dart' show GizmoHandle;

/// The Move, Scale and Rotate gizmos: how each is drawn, and where its
/// handles are. One for the editor's gizmo and the Level Designer's, so the
/// two look and answer alike.
///
/// Sizes are in screen pixels. The hit tests take positions in any space
/// and [px], what one screen pixel is in it: 1 on the screen, world units
/// per pixel in the level. Screen up is minus y in both.
abstract final class TransformGizmo {
  /// How big the handles are drawn, as the settings make them.
  static double get _k => ViewportLook.gizmoScale;
  static double get _arrow => GizmoConstants.arrowLength * _k;
  static double get _square => (GizmoConstants.moveHandleRadius * _k) * _k;
  static double get _tip => GizmoConstants.axisSquareHalf * _k;

  static final Paint _paint = Paint()..isAntiAlias = true;

  // ── Where ────────────────────────────────────────────────────────────────

  /// The end of the X arrow, or the X scale handle, from [centre].
  static Offset xEnd(Offset centre, [double px = 1]) =>
      centre + Offset(_arrow * px, 0);

  /// The end of the Y arrow, or the Y scale handle: up the screen.
  static Offset yEnd(Offset centre, [double px = 1]) =>
      centre + Offset(0, -_arrow * px);

  /// Which part of the move gizmo at [centre] is under [pos]: the square
  /// (both axes), an arrow (one), or none.
  static GizmoHandle moveHandleAt(Offset pos, Offset centre, {double px = 1}) {
    if (_inSquare(
      pos,
      centre,
      (GizmoConstants.moveHandleHitRadius * _k) * px,
    )) {
      return GizmoHandle.translateXY;
    }
    final reach = (GizmoConstants.arrowTipRadius * _k) * px;
    final shaft = (GizmoConstants.axisHitWidth * _k) * px;
    if ((pos - xEnd(centre, px)).distance <= reach ||
        _nearSegment(pos, centre, xEnd(centre, px), shaft)) {
      return GizmoHandle.translateX;
    }
    if ((pos - yEnd(centre, px)).distance <= reach ||
        _nearSegment(pos, centre, yEnd(centre, px), shaft)) {
      return GizmoHandle.translateY;
    }
    return GizmoHandle.none;
  }

  /// Which axis handle of the scale gizmo at [centre] is under [pos].
  static GizmoHandle scaleAxisAt(Offset pos, Offset centre, {double px = 1}) {
    final reach = (GizmoConstants.axisSquareHitRadius * _k) * px;
    if ((pos - xEnd(centre, px)).distance <= reach) return GizmoHandle.scaleX;
    if ((pos - yEnd(centre, px)).distance <= reach) return GizmoHandle.scaleY;
    return GizmoHandle.none;
  }

  /// [radius], or more: far enough out that a ring drawn with the arrows —
  /// All, on tiles — never sits on an arrowhead and takes its presses.
  static double ringClearOfArrows(double radius, {double px = 1}) => math.max(
    radius,
    (_arrow +
            (GizmoConstants.arrowTipRadius * _k) +
            (GizmoConstants.ringHitWidth * _k) +
            2) *
        px,
  );

  /// Whether [pos] is on the rotate ring of [radius] about [centre].
  static bool onRing(
    Offset pos,
    Offset centre,
    double radius, {
    double px = 1,
  }) =>
      ((pos - centre).distance - radius).abs() <=
      (GizmoConstants.ringHitWidth * _k) * px;

  /// Which part of the all-in-one gizmo at [centre] is under [pos], its
  /// scale corners at [corners] (NW, NE, SE, SW) and its rotate dot at the
  /// end of an arc from [rotation]. Without [scale] or [rotate], those
  /// parts are not there.
  static GizmoHandle allHandleAt(
    Offset pos,
    Offset centre, {
    required List<Offset> corners,
    double rotation = 0,
    bool scale = true,
    bool rotate = true,
  }) {
    if ((pos - centre).distance < (GizmoConstants.moveHandleHitRadius * _k)) {
      return GizmoHandle.translateXY;
    }
    if (scale && corners.length == 4) {
      const handles = [
        GizmoHandle.scaleNW,
        GizmoHandle.scaleNE,
        GizmoHandle.scaleSE,
        GizmoHandle.scaleSW,
      ];
      for (var i = 0; i < 4; i++) {
        if ((pos - corners[i]).distance <
            (GizmoConstants.scaleHandle * _k) + 4) {
          return handles[i];
        }
      }
    }
    if (rotate &&
        (pos - _arcEnd(centre, rotation)).distance <
            (GizmoConstants.rotDotRadius * _k)) {
      return GizmoHandle.rotate;
    }
    if ((pos - xEnd(centre)).distance < (GizmoConstants.arrowTipRadius * _k)) {
      return GizmoHandle.translateX;
    }
    if ((pos - yEnd(centre)).distance < (GizmoConstants.arrowTipRadius * _k)) {
      return GizmoHandle.translateY;
    }
    // After the tips, so an arrowhead wins over the shaft.
    if (scale) {
      final along = GizmoConstants.axisSquareOffset * _k;
      if ((pos - (centre + Offset(along, 0))).distance <
          (GizmoConstants.axisSquareHitRadius * _k)) {
        return GizmoHandle.scaleX;
      }
      if ((pos - (centre + Offset(0, -along))).distance <
          (GizmoConstants.axisSquareHitRadius * _k)) {
        return GizmoHandle.scaleY;
      }
    }
    return GizmoHandle.none;
  }

  /// The end of the all-in-one gizmo's rotate arc.
  static Offset _arcEnd(Offset centre, double rotation) =>
      centre +
      Offset(
            math.cos(rotation + GizmoConstants.rotSweep),
            math.sin(rotation + GizmoConstants.rotSweep),
          ) *
          (GizmoConstants.rotRadius * _k);

  static bool _inSquare(Offset pos, Offset centre, double half) =>
      (pos.dx - centre.dx).abs() <= half && (pos.dy - centre.dy).abs() <= half;

  static bool _nearSegment(Offset p, Offset a, Offset b, double width) {
    final ab = b - a;
    final length2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (length2 == 0) return (p - a).distance <= width;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / length2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance <= width;
  }

  // ── Drawing, on the screen ───────────────────────────────────────────────

  /// Two arrows, X to the right and Y up, and a square where they meet
  /// that moves on both.
  static void paintMove(Canvas canvas, Offset centre) {
    _arrowTo(canvas, centre, xEnd(centre), GizmoConstants.colX);
    _arrowTo(canvas, centre, yEnd(centre), GizmoConstants.colY);
    final square = Rect.fromCenter(
      center: centre,
      width: _square * 2,
      height: _square * 2,
    );
    canvas
      ..drawRect(
        square,
        _paint
          ..style = PaintingStyle.fill
          ..color = GizmoConstants.colMove.withValues(alpha: 0.9),
      )
      ..drawRect(
        square,
        _paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF000000).withValues(alpha: 0.45),
      );
  }

  /// Two lines, X and Y, each ending in the square that stretches along
  /// it.
  static void paintScaleAxes(Canvas canvas, Offset centre) {
    for (final (end, color) in [
      (xEnd(centre), GizmoConstants.colX),
      (yEnd(centre), GizmoConstants.colY),
    ]) {
      canvas.drawLine(
        centre,
        end,
        _paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
      _handle(canvas, end, _tip, color);
    }
  }

  /// A square on each of [corners], which scale evenly.
  static void paintScaleCorners(Canvas canvas, List<Offset> corners) {
    for (final corner in corners) {
      _handle(
        canvas,
        corner,
        (GizmoConstants.scaleHandle * _k),
        GizmoConstants.colScale,
      );
    }
  }

  /// A ring of [radius] about [centre], with a knob at [angle] saying
  /// which way is turned.
  static void paintRotate(
    Canvas canvas,
    Offset centre,
    double radius, {
    double angle = 0,
  }) {
    canvas.drawCircle(
      centre,
      radius,
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = GizmoConstants.colRot.withValues(alpha: 0.85),
    );
    final knob = centre + Offset(math.cos(angle), math.sin(angle)) * radius;
    canvas
      ..drawLine(
        centre,
        knob,
        _paint
          ..strokeWidth = 1
          ..color = GizmoConstants.colRot.withValues(alpha: 0.5),
      )
      ..drawCircle(
        knob,
        (GizmoConstants.dotRadius * _k),
        _paint
          ..style = PaintingStyle.fill
          ..color = GizmoConstants.colRot,
      );
  }

  /// Move, scale and turn in one: the arrows, a square on each shaft that
  /// stretches along it, the corners, an arc from [rotation] with the dot
  /// that turns it, and a round handle in the middle that moves freely.
  /// Without [scale] or [rotate], those parts are left off.
  static void paintAll(
    Canvas canvas,
    Offset centre, {
    required List<Offset> corners,
    double rotation = 0,
    bool scale = true,
    bool rotate = true,
  }) {
    _arrowTo(canvas, centre, xEnd(centre), GizmoConstants.colX);
    _arrowTo(canvas, centre, yEnd(centre), GizmoConstants.colY);
    if (scale) {
      final along = GizmoConstants.axisSquareOffset * _k;
      _handle(canvas, centre + Offset(along, 0), _tip, GizmoConstants.colX);
      _handle(canvas, centre + Offset(0, -along), _tip, GizmoConstants.colY);
    }
    if (rotate) {
      canvas
        ..drawArc(
          Rect.fromCircle(
            center: centre,
            radius: (GizmoConstants.rotRadius * _k),
          ),
          rotation,
          GizmoConstants.rotSweep,
          false,
          _paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = GizmoConstants.colRot.withValues(alpha: 0.6),
        )
        ..drawCircle(
          _arcEnd(centre, rotation),
          (GizmoConstants.dotRadius * _k),
          _paint
            ..style = PaintingStyle.fill
            ..color = GizmoConstants.colRot,
        );
    }
    canvas
      ..drawCircle(
        centre,
        (GizmoConstants.moveHandleRadius * _k),
        _paint
          ..style = PaintingStyle.fill
          ..color = GizmoConstants.colMove.withValues(alpha: 0.9),
      )
      ..drawCircle(
        centre,
        (GizmoConstants.moveHandleRadius * _k),
        _paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF000000).withValues(alpha: 0.45),
      );
    if (scale) paintScaleCorners(canvas, corners);
  }

  static void _handle(Canvas canvas, Offset at, double half, Color color) {
    final square = Rect.fromCenter(
      center: at,
      width: half * 2,
      height: half * 2,
    );
    canvas
      ..drawRect(
        square,
        _paint
          ..style = PaintingStyle.fill
          ..color = color,
      )
      ..drawRect(
        square,
        _paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF000000).withValues(alpha: 0.4),
      );
  }

  static void _arrowTo(Canvas canvas, Offset from, Offset to, Color color) {
    canvas.drawLine(
      from,
      to,
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
    final direction = to - from;
    final length = direction.distance;
    if (length == 0) return;
    final along = direction / length;
    final across = Offset(-along.dy, along.dx);
    final base = to - along * (GizmoConstants.arrowHeadLength * _k);
    final half = (GizmoConstants.arrowHeadWidth * _k) / 2;
    canvas.drawPath(
      ui.Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo((base + across * half).dx, (base + across * half).dy)
        ..lineTo((base - across * half).dx, (base - across * half).dy)
        ..close(),
      _paint
        ..style = PaintingStyle.fill
        ..color = color,
    );
  }
}
