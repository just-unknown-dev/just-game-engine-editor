import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import '../../../core/view/orbit_fly_editor_view.dart';
import '../../overlay/gizmo_3d.dart' show gizmoAxisColors;

/// One end of an axis on the [ViewCube]: the side it looks from.
class _Side {
  const _Side(this.direction, this.axis, this.positive, this.yaw, this.pitch);

  /// Where it points, engine axes (+Y down).
  final List<double> direction;

  /// 0 X, 1 Y, 2 Z.
  final int axis;

  /// The positive end, labelled and filled.
  final bool positive;

  /// The view along it: from this side towards the middle.
  final double yaw, pitch;
}

/// The axes as the 3-D view sees them, at a corner of the viewport: click
/// an end to look from that side, click the label under them to switch
/// between perspective and orthographic (pad 5).
///
/// Y is drawn up, as the editor shows it; in the engine up is -Y.
class ViewCube extends StatefulWidget {
  const ViewCube({
    super.key,
    required this.view,
    required this.onViewAlong,
    required this.onToggleOrthographic,
  });

  /// The view it shows and turns.
  final OrbitFlyEditorView view;

  /// Looks along an axis: yaw and pitch, radians.
  final void Function(double yaw, double pitch) onViewAlong;

  /// Switches perspective and orthographic.
  final VoidCallback onToggleOrthographic;

  /// Its side, in logical pixels.
  static const double size = 76;

  static const List<_Side> _sides = [
    _Side([1, 0, 0], 0, true, -math.pi / 2, 0),
    _Side([-1, 0, 0], 0, false, math.pi / 2, 0),
    // Up the screen is -Y: the top.
    _Side([0, -1, 0], 1, true, 0, -math.pi / 2),
    _Side([0, 1, 0], 1, false, 0, math.pi / 2),
    _Side([0, 0, 1], 2, true, math.pi, 0),
    _Side([0, 0, -1], 2, false, 0, 0),
  ];

  @override
  State<ViewCube> createState() => _ViewCubeState();
}

class _ViewCubeState extends State<ViewCube>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _yaw = double.nan, _pitch = double.nan;
  bool _ortho = false;

  @override
  void initState() {
    super.initState();
    // Built again only when the view turned or changed its lens.
    _ticker = createTicker((_) {
      final v = widget.view;
      if (v.yaw != _yaw || v.pitch != _pitch || v.orthographic != _ortho) {
        setState(() {
          _yaw = v.yaw;
          _pitch = v.pitch;
          _ortho = v.orthographic;
        });
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Where each side's end is drawn in the widget, and how far it is (the
  /// further first).
  List<(_Side, Offset, double)> _ends() {
    final v = widget.view;
    final r = v.right, u = v.up, f = v.forward;
    const centre = Offset(ViewCube.size / 2, ViewCube.size / 2 - 6);
    const reach = 26.0;
    final out = <(_Side, Offset, double)>[
      for (final side in ViewCube._sides)
        (
          side,
          centre +
              Offset(
                _dot(side.direction, r) * reach,
                -_dot(side.direction, u) * reach,
              ),
          _dot(side.direction, f),
        ),
    ]..sort((a, b) => b.$3.compareTo(a.$3));
    return out;
  }

  static double _dot(List<double> d, jge.Vector3 v) =>
      d[0] * v.x + d[1] * v.y + d[2] * v.z;

  void _tap(Offset at) {
    _Side? best;
    var bestDistance = 11.0;
    for (final (side, point, _) in _ends()) {
      final d = (point - at).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = side;
      }
    }
    if (best != null) widget.onViewAlong(best.yaw, best.pitch);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ViewCube.size,
      height: ViewCube.size + 10,
      child: Column(
        children: [
          Tooltip(
            message: 'Look from a side: click an axis end',
            waitDuration: const Duration(milliseconds: 600),
            child: GestureDetector(
              onTapUp: (d) => _tap(d.localPosition),
              child: CustomPaint(
                size: const Size(ViewCube.size, ViewCube.size - 6),
                painter: _ViewCubePainter(_ends()),
              ),
            ),
          ),
          InkWell(
            onTap: widget.onToggleOrthographic,
            child: Text(
              _ortho ? 'Ortho' : 'Persp',
              style: TextStyle(
                color: EditorTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewCubePainter extends CustomPainter {
  _ViewCubePainter(this.ends);

  final List<(_Side, Offset, double)> ends;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      centre,
      size.shortestSide / 2,
      Paint()..color = EditorTheme.panelBg.withValues(alpha: 0.55),
    );
    const labels = ['X', 'Y', 'Z'];
    for (final (side, point, _) in ends) {
      final colour = gizmoAxisColors[side.axis];
      if (side.positive) {
        canvas.drawLine(
          centre,
          point,
          Paint()
            ..color = colour
            ..strokeWidth = 2,
        );
      }
      canvas.drawCircle(
        point,
        side.positive ? 7 : 5,
        Paint()
          ..color = side.positive ? colour : colour.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill,
      );
      if (side.positive) {
        final text = TextPainter(
          text: TextSpan(
            text: labels[side.axis],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, point - Offset(text.width / 2, text.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_ViewCubePainter old) => true;
}
