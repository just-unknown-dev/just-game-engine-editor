/// The open timeline's motion, drawn in the viewport: where a position
/// track takes its entity, with a dot at every key to drag.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import 'timeline_session.dart';

/// The path one entity's position tracks describe.
class MotionPath {
  MotionPath._(
    this.session,
    this.binding,
    this.entity,
    this.x,
    this.y,
    this.base,
  );

  final TimelineSession session;
  final jge.TrackBinding binding;
  final jge.Entity entity;

  /// The track indices of the x and y channels; either may be missing.
  final int? x, y;

  /// Where the entity stands in the scene — not where a preview has put it.
  final Offset base;

  jge.PropertyTrack? _track(int? index) => index == null
      ? null
      : session.asset.value!.tracks[index] as jge.PropertyTrack;

  /// The key times of either channel, in order.
  List<double> get keyTimes {
    final times = <double>{
      for (final k in _track(x)?.curve.keys ?? const <jge.TimelineKey>[])
        k.time,
      for (final k in _track(y)?.curve.keys ?? const <jge.TimelineKey>[])
        k.time,
    }.toList()..sort();
    return times;
  }

  double _axis(int? index, double time, double base) {
    final track = _track(index);
    if (track == null || track.curve.isEmpty || track.muted) return base;
    final v = track.curve.numberAt(time);
    return track.isRelative ? base + v : v;
  }

  /// Where the entity is at [time], in world units.
  Offset at(double time) =>
      Offset(_axis(x, time, base.dx), _axis(y, time, base.dy));

  /// Every position path in [session]'s timeline, one per bound entity.
  static List<MotionPath> of(TimelineSession session) {
    final asset = session.asset.value;
    if (asset == null) return const [];
    final byBinding = <jge.TrackBinding, (int?, int?)>{};
    for (var i = 0; i < asset.tracks.length; i++) {
      final t = asset.tracks[i];
      if (t is! jge.PropertyTrack ||
          t.component != 'TransformComponent' ||
          t.field != 'position' ||
          t.curve.isEmpty) {
        continue;
      }
      final (x, y) = byBinding[t.binding] ?? (null, null);
      byBinding[t.binding] = (
        t.channel == 'x' ? i : x,
        t.channel == 'y' ? i : y,
      );
    }
    final out = <MotionPath>[];
    for (final MapEntry(key: binding, value: (x, y)) in byBinding.entries) {
      final entity = binding.resolve(session.scope.world, session.owner);
      final transform = entity?.getComponent<jge.TransformComponent>();
      if (entity == null || transform == null) continue;
      var base = Offset(transform.position.x, transform.position.y);
      // While previewing, the transform is wherever the timeline put it; the
      // path hangs off where the scene has it.
      final definition = session.scope.definitions.definitionFor(transform);
      for (final f in definition?.fields ?? const <jge.SchemaField>[]) {
        if (f.name != 'position') continue;
        final authored = session.authoredValue(transform, f);
        if (authored is Map) {
          base = Offset(
            (authored['x'] as num).toDouble(),
            (authored['y'] as num).toDouble(),
          );
        }
      }
      out.add(MotionPath._(session, binding, entity, x, y, base));
    }
    return out;
  }
}

class MotionPathOverlay extends DesignerOverlay with InteractiveOverlay {
  MotionPathOverlay(this.session);

  final TimelineSession Function() session;

  static const Color _color = Color(0xFFFFCA28);
  static const double _hit = 8;

  @override
  String get id => 'timeline.motion_paths';

  @override
  String get label => 'Motion paths';

  @override
  IconData get icon => Icons.timeline_rounded;

  @override
  String? get description =>
      'Where the open timeline moves things, with its keys to drag.';

  @override
  int get order => OverlayOrder.measurement;

  @override
  void paint(OverlayPaintContext context) {
    final s = session();
    final draw = context.draw;
    for (final path in MotionPath.of(s)) {
      final duration = s.duration;
      if (duration <= 0) continue;
      final line = Path();
      const steps = 96;
      for (var i = 0; i <= steps; i++) {
        final p = draw.toScreen(path.at(duration * i / steps));
        i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
      }
      draw.canvas.drawPath(
        line,
        Paint()
          ..color = _color.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      // A tick every few frames says how fast it goes: close together is
      // slow.
      final fps = s.fps;
      for (var f = 0; f <= duration * fps; f += 2) {
        draw.canvas.drawCircle(
          draw.toScreen(path.at(f / fps)),
          1.2,
          Paint()..color = _color.withValues(alpha: 0.55),
        );
      }
      for (final time in path.keyTimes) {
        final p = draw.toScreen(path.at(time));
        final here = (time - s.playhead.value).abs() < 1e-6;
        draw.canvas
          ..drawCircle(p, 4.5, Paint()..color = EditorTheme.panelBg)
          ..drawCircle(
            p,
            4.5,
            Paint()
              ..color = here ? GizmoConstants.colSel : _color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
      }
      draw.canvas.drawCircle(
        draw.toScreen(path.at(s.playhead.value)),
        3,
        Paint()..color = EditorTheme.primaryBright,
      );
    }
  }

  // ── Dragging a key's dot ─────────────────────────────────────────────────

  MotionPath? _path;
  double _time = 0;
  jge.TimelineAsset? _start;

  @override
  bool onPointerDown(OverlayPointerContext context) {
    final s = session();
    if (!s.isAuthoring()) return false;
    for (final path in MotionPath.of(s)) {
      for (final time in path.keyTimes) {
        final p = context.camera.worldToScreen(path.at(time));
        if ((p - context.screen).distance > _hit) continue;
        _path = path;
        _time = time;
        _start = s.beginDrag();
        s
          ..pause()
          ..scrubTo(time);
        return true;
      }
    }
    return false;
  }

  @override
  void onPointerMove(OverlayPointerContext context) {
    final path = _path, start = _start;
    if (path == null || start == null) return;
    var world = context.camera.screenToWorld(context.screen);
    if (context.snapping && context.gridSize > 0) {
      world = Offset(
        (world.dx / context.gridSize).round() * context.gridSize,
        (world.dy / context.gridSize).round() * context.gridSize,
      );
    }
    session().dragPathPoint(start, path, _time, world);
  }

  @override
  void onPointerUp(OverlayPointerContext context) {
    final start = _start;
    if (start != null) session().endDrag(start);
    onCancel();
  }

  @override
  void onCancel() {
    _path = null;
    _start = null;
  }
}
