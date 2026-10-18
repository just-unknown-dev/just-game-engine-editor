import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine/graphics_3d.dart' show Graphics3D;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';

/// The 3-D designer's Measure: drag from one surface point to another for
/// the distance between them in metres, and how much of it is across, up
/// and along; the measurement stays until the next one, or Escape.
/// Snapping puts each end on the move step.
class Measure3DTool extends LevelToolHandler {
  /// The measurement shown, ends in the world; null for none.
  final Signal<(jge.Vector3, jge.Vector3)?> measured = Signal(null, debugLabel: 'measure3D');

  jge.Vector3? _from;

  @override
  String get id => BuiltInTools.measure;

  @override
  String get label => 'Measure';

  @override
  IconData get icon => Icons.straighten;

  @override
  String? get shortcut => 'M';

  @override
  String? get description => 'Drag between two points for the distance in metres; Escape clears it';

  @override
  int get order => 90;

  @override
  String get group => ToolGroups.measure;

  @override
  jge.Dimensions get dimensions => jge.Dimensions.threeD;

  @override
  bool onPointerDown(ToolContext context) {
    final space = context.space;
    if (space == null) return false;
    _from = space.snappedSurface().position;
    measured.value = (_from!, _from!);
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final from = _from, space = context.space;
    if (from == null || space == null) return;
    measured.value = (from, space.snappedSurface().position);
  }

  @override
  void onPointerUp(ToolContext context) {
    _from = null;
    final m = measured.value;
    if (m != null) context.controller.setStatus(describe(m.$1, m.$2));
  }

  @override
  void onCancel() => _from = null;

  @override
  bool onKey(LogicalKeyboardKey key, ToolContext context) {
    if (key != LogicalKeyboardKey.escape || measured.value == null) return false;
    measured.value = null;
    return true;
  }

  /// [a] to [b] in words: the distance, then across, up and along.
  static String describe(jge.Vector3 a, jge.Vector3 b) {
    final d = b - a;
    String m(double v) => v.abs() < 0.005 ? '0' : v.toStringAsFixed(2);
    return '${m(d.length)} m  (across ${m(d.x)}, up ${m(-d.y)}, along ${m(d.z)})';
  }
}

/// Measure's line and its length, over the scene.
class Ruler3DOverlay extends DesignerOverlay {
  Ruler3DOverlay(this.tool);

  final Measure3DTool tool;

  // What a tool in use draws: it stays with the gizmos hidden.
  @override
  GizmoKind? get gizmoKind => null;

  @override
  String get id => 'designer3d.ruler';

  @override
  String get label => 'Measurement';

  @override
  IconData get icon => Icons.straighten;

  @override
  jge.Dimensions get dimensions => jge.Dimensions.threeD;

  @override
  int get order => OverlayOrder.selection;

  @override
  void paint(OverlayPaintContext context) {
    final m = tool.measured.value;
    if (m == null) return;
    final view = context.draw.camera;
    final a = view.projectToScreen(m.$1), b = view.projectToScreen(m.$2);
    if (a == null || b == null) return;
    final colour = const Color(0xFFFFD54F);
    final line = Paint()
      ..color = colour
      ..strokeWidth = 2;
    context.draw.canvas
      ..drawLine(a, b, line)
      ..drawCircle(a, 4, Paint()..color = colour)
      ..drawCircle(b, 4, Paint()..color = colour);
    final label = TextPainter(
      text: TextSpan(
        text: Measure3DTool.describe(m.$1, m.$2),
        style: const TextStyle(color: Color(0xFFFFE082), fontSize: 11, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = Offset.lerp(a, b, 0.5)! + const Offset(8, -18);
    final box = Rect.fromLTWH(at.dx - 4, at.dy - 2, label.width + 8, label.height + 4);
    context.draw.canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(3)),
      Paint()..color = const Color(0xDD1E1F24),
    );
    label.paint(context.draw.canvas, at);
  }
}

/// Where the game kit puts back what falls (its kill height): a dashed
/// square round the view's focus at that height, named — so a designer
/// sees how far below a fall is lost.
class KillHeight3DOverlay extends DesignerOverlay {
  KillHeight3DOverlay(this.scope);

  final EditorScope scope;

  @override
  String get id => 'designer3d.killHeight';

  @override
  String get label => 'Kill height';

  @override
  IconData get icon => Icons.vertical_align_bottom;

  @override
  jge.Dimensions get dimensions => jge.Dimensions.threeD;

  @override
  void paint(OverlayPaintContext context) {
    final height = scope.killHeight;
    if (height == null) return;
    final view = context.draw.camera;
    final focus = view.focus;
    const half = 20.0;
    final colour = const Color(0xFFE57373);
    final dash = Paint()
      ..color = colour.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;
    final corners = [
      jge.Vector3(focus.x - half, height, focus.z - half),
      jge.Vector3(focus.x + half, height, focus.z - half),
      jge.Vector3(focus.x + half, height, focus.z + half),
      jge.Vector3(focus.x - half, height, focus.z + half),
    ];
    for (var i = 0; i < 4; i++) {
      final from = corners[i], to = corners[(i + 1) % 4];
      for (var k = 0; k < 20; k += 2) {
        final a = view.projectToScreen(from + (to - from) * (k / 20));
        final b = view.projectToScreen(from + (to - from) * ((k + 1) / 20));
        if (a != null && b != null) context.draw.canvas.drawLine(a, b, dash);
      }
    }
    final at = view.projectToScreen(corners.first);
    if (at == null) return;
    final label = TextPainter(
      text: TextSpan(
        text: 'Kill height ${(-height).toStringAsFixed(1)} m',
        style: TextStyle(color: colour, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(context.draw.canvas, at + const Offset(4, 2));
  }
}

/// How much the scene asks of the GPU, in the 3-D designer's status bar:
/// draws a frame against a phone's budget (about 100), triangles and
/// instances beside it. Green within, amber near, red past it.
class PerformanceMeter extends StatefulWidget {
  const PerformanceMeter({super.key, required this.scope});

  final EditorScope scope;

  /// Draws a frame a phone takes in its stride.
  static const int drawBudget = 100;

  @override
  State<PerformanceMeter> createState() => _PerformanceMeterState();
}

class _PerformanceMeterState extends State<PerformanceMeter> {
  Timer? _timer;
  (int, int, int)? _seen;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _read());
  }

  void _read() {
    final service = widget.scope.engine?.services.maybe<Graphics3D>();
    final stats = service == null || !service.isStarted ? null : service.renderer.stats;
    final next = stats == null ? null : (stats.drawCalls + stats.shadowDrawCalls, stats.triangles, stats.instances);
    if (next != _seen && mounted) setState(() => _seen = next);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    if (seen == null) return const SizedBox.shrink();
    final (draws, triangles, instances) = seen;
    final share = draws / PerformanceMeter.drawBudget;
    final colour = share < 0.7
        ? const Color(0xFF81C784)
        : share < 1
        ? const Color(0xFFFFD54F)
        : const Color(0xFFE57373);
    String count(int n) => n >= 1000000
        ? '${(n / 1000000).toStringAsFixed(1)}M'
        : n >= 1000
        ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k'
        : '$n';
    return Tooltip(
      message:
          'Draws a frame (shadows included) against a phone\'s budget of '
          '${PerformanceMeter.drawBudget}; triangles and instances drawn',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed, size: 13, color: colour),
            const SizedBox(width: 4),
            Text(
              '$draws/${PerformanceMeter.drawBudget} draws · ${count(triangles)} tris · ${count(instances)}',
              style: TextStyle(color: colour, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
