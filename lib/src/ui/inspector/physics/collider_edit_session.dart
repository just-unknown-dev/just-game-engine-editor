import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import '../../../core/scope/editor_scope.dart';
import '../../../core/state/editor_scene_state.dart';
import '../../../core/view/editor_view.dart';
import '../../level_designer/state/editor_history.dart';

/// What a collider handle does when dragged.
enum ColliderHandleKind {
  /// Moves the whole collider: its offset.
  center,

  /// A box's corner: resizes it, the opposite corner staying put.
  corner,

  /// A box's side: resizes it along one axis.
  side,

  /// A circle's edge, or a capsule's side: sets the radius.
  radius,

  /// A capsule's end: moves that end.
  end,

  /// A polygon's, chain's or segment's point: moves it.
  vertex,

  /// Between two points: adds a point there, then moves it.
  insert,
}

/// One handle of the collider being edited: what it does, which point or
/// side it is ([index]), and where it is in the body's own space (scaled,
/// not turned).
@immutable
class ColliderHandle {
  const ColliderHandle(this.kind, this.index, this.local);

  final ColliderHandleKind kind;
  final int index;
  final Offset local;

  bool same(ColliderHandle? other) =>
      other != null && other.kind == kind && other.index == index;
}

/// Editing a physics body's collider in the viewport: handles for its size,
/// its points and its position on the entity, each drag one undo step.
///
/// One per editor ([of]). On while [target] is set — by the inspector's
/// Edit collider button — and off when the selection moves to something
/// else, a play-test starts, the body goes, or Esc is pressed.
class ColliderEditSession {
  ColliderEditSession(this.scope) {
    _stops = [
      scope.sceneState.selectedEntity.watch(() {
        final t = target.value;
        if (t != null && !identical(scope.sceneState.selectedEntity.value, t)) {
          stop();
        }
      }),
      scope.isPlayTesting.watch(() {
        if (scope.isPlayTesting.value) stop();
      }),
    ];
  }

  static final Expando<ColliderEditSession> _sessions = Expando(
    'colliderEditSession',
  );

  /// The session of [scope]'s editor.
  static ColliderEditSession of(EditorScope scope) =>
      _sessions[scope] ??= ColliderEditSession(scope);

  final EditorScope scope;
  late final List<void Function()> _stops;

  /// Whose collider is being edited, or null.
  final Signal<jge.Entity?> target = Signal(null, debugLabel: 'colliderEdit');

  /// The handle under the pointer, drawn lit.
  ColliderHandle? hovered;

  ColliderHandle? _drag;
  late jge.CollisionShape _startShape;
  late Offset _startOffset;
  late Offset _startPointer; // entity space, unscaled
  int _dragId = 0;

  /// Screen pixels within which a press takes a handle.
  static const double grabRadius = 8;

  bool get isActive => body != null;

  bool get isDragging => _drag != null;

  /// The body being edited, while its entity is alive and has one.
  jge.PhysicsBodyComponent? get body {
    final e = target.value;
    if (e == null || !e.isAlive) return null;
    return e.getComponent<jge.PhysicsBodyComponent>();
  }

  /// Whether [entity]'s collider is the one being edited.
  bool isEditing(jge.Entity? entity) =>
      entity != null && identical(target.value, entity) && isActive;

  /// Edits [entity]'s collider, or stops when it already is.
  void toggle(jge.Entity entity) {
    if (isEditing(entity)) {
      stop();
    } else {
      scope.sceneState.selectEntity(entity);
      target.value = entity;
    }
    scope.sceneState.refresh();
  }

  void stop() {
    if (target.value == null) return;
    _drag = null;
    hovered = null;
    target.value = null;
    scope.sceneState.refresh();
  }

  void dispose() {
    for (final s in _stops) {
      s();
    }
    target.dispose();
  }

  // ── Where things are ─────────────────────────────────────────────────────

  jge.TransformComponent? get _transform =>
      target.value?.getComponent<jge.TransformComponent>();

  (double, double) get _scale {
    final t = _transform;
    double clean(double v) =>
        v.abs() < 1e-3 ? (v.isNegative ? -1e-3 : 1e-3) : v;
    return (clean(t?.scale.x ?? 1), clean(t?.scale.y ?? 1));
  }

  /// A point in the body's own space (scaled, not turned) → the world.
  Offset toWorld(Offset local) {
    final t = _transform;
    if (t == null) return local;
    final c = math.cos(t.angle), s = math.sin(t.angle);
    return Offset(
      t.position.x + local.dx * c - local.dy * s,
      t.position.y + local.dx * s + local.dy * c,
    );
  }

  /// The world → the body's own space (scaled, not turned).
  Offset toLocal(Offset world) {
    final t = _transform;
    if (t == null) return world;
    final d = world - Offset(t.position.x, t.position.y);
    final c = math.cos(-t.angle), s = math.sin(-t.angle);
    return Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }

  /// The body's own space → the entity's (unscaled), where shapes and
  /// offsets are kept.
  Offset _unscale(Offset local) {
    final (sx, sy) = _scale;
    return Offset(local.dx / sx, local.dy / sy);
  }

  Offset _scaled(Offset p) {
    final (sx, sy) = _scale;
    return Offset(p.dx * sx, p.dy * sy);
  }

  /// Every handle of the collider, in the body's own space.
  List<ColliderHandle> handles() {
    final b = body;
    if (b == null) return const [];
    final o = b.offset;
    Offset at(Offset p) => _scaled(p + o);
    final (sx, sy) = _scale;
    final grow = math.max(sx.abs(), sy.abs());
    final out = <ColliderHandle>[];
    switch (b.shape) {
      case jge.CircleShape c:
        final centre = at(c.center);
        final r = c.radius * grow;
        for (final (i, d) in const [
          (0, Offset(1, 0)),
          (1, Offset(0, 1)),
          (2, Offset(-1, 0)),
          (3, Offset(0, -1)),
        ]) {
          out.add(ColliderHandle(ColliderHandleKind.radius, i, centre + d * r));
        }
      case jge.RectangleShape r:
        final hw = r.width / 2, hh = r.height / 2;
        const corners = [
          Offset(-1, -1),
          Offset(1, -1),
          Offset(1, 1),
          Offset(-1, 1),
        ];
        for (var i = 0; i < 4; i++) {
          final k = corners[i];
          out.add(
            ColliderHandle(
              ColliderHandleKind.corner,
              i,
              at(Offset(k.dx * hw, k.dy * hh)),
            ),
          );
        }
        const sides = [
          Offset(0, -1),
          Offset(1, 0),
          Offset(0, 1),
          Offset(-1, 0),
        ];
        for (var i = 0; i < 4; i++) {
          final k = sides[i];
          out.add(
            ColliderHandle(
              ColliderHandleKind.side,
              i,
              at(Offset(k.dx * hw, k.dy * hh)),
            ),
          );
        }
      case jge.CapsuleShape c:
        final axis = c.center2 - c.center1;
        final len = axis.distance;
        final u = len < 1e-9 ? const Offset(0, 1) : axis / len;
        out
          ..add(
            ColliderHandle(
              ColliderHandleKind.end,
              0,
              at(c.center1 - u * c.radius),
            ),
          )
          ..add(
            ColliderHandle(
              ColliderHandleKind.end,
              1,
              at(c.center2 + u * c.radius),
            ),
          )
          ..add(
            ColliderHandle(
              ColliderHandleKind.radius,
              0,
              at((c.center1 + c.center2) / 2 + Offset(-u.dy, u.dx) * c.radius),
            ),
          );
      case jge.PolygonShape p:
        _points(out, p.vertices, closed: true, at: at);
      case jge.SegmentShape s:
        out
          ..add(ColliderHandle(ColliderHandleKind.vertex, 0, at(s.point1)))
          ..add(ColliderHandle(ColliderHandleKind.vertex, 1, at(s.point2)));
      case jge.ChainShape c:
        _points(out, c.vertices, closed: c.loop, at: at);
    }
    out.add(ColliderHandle(ColliderHandleKind.center, 0, _scaled(o)));
    return out;
  }

  void _points(
    List<ColliderHandle> out,
    List<Offset> points, {
    required bool closed,
    required Offset Function(Offset) at,
  }) {
    for (var i = 0; i < points.length; i++) {
      out.add(ColliderHandle(ColliderHandleKind.vertex, i, at(points[i])));
    }
    final edges = closed ? points.length : points.length - 1;
    if (!_canInsert) return;
    for (var i = 0; i < edges; i++) {
      final a = points[i], b = points[(i + 1) % points.length];
      out.add(ColliderHandle(ColliderHandleKind.insert, i, at((a + b) / 2)));
    }
  }

  /// A Box2D polygon has at most eight points.
  bool get _canInsert => switch (body?.shape) {
    jge.RoundedPolygonShape p => p.vertices.length < 8,
    jge.PolygonShape p => p.vertices.length < 8,
    jge.ChainShape _ => true,
    _ => false,
  };

  /// The handle within [grabRadius] of [screen], points before the rest.
  ColliderHandle? hitTest(Offset screen, EditorView view) {
    ColliderHandle? best;
    var bestD = grabRadius;
    for (final h in handles()) {
      final d = (view.worldToScreen(toWorld(h.local)) - screen).distance;
      // A point wins a tie over the "add a point" marker beside it.
      final bias = h.kind == ColliderHandleKind.insert ? 2.0 : 0.0;
      if (d + bias < bestD) {
        bestD = d + bias;
        best = h;
      }
    }
    return best;
  }

  // ── Pointer ──────────────────────────────────────────────────────────────

  /// Lights the handle under the pointer. Returns whether that changed.
  bool onHover(Offset screen, EditorView view) {
    if (!isActive || isDragging) return false;
    final next = hitTest(screen, view);
    if (next == null && hovered == null) return false;
    if (next != null && next.same(hovered)) return false;
    hovered = next;
    scope.sceneState.refresh();
    return true;
  }

  /// A press: takes a handle and starts dragging it — or, with [remove]
  /// (Alt), takes a point away. Returns whether a handle took it.
  bool onPointerDown(Offset screen, EditorView view, {bool remove = false}) {
    final b = body;
    if (b == null) return false;
    var h = hitTest(screen, view);
    if (h == null) return false;
    if (remove) {
      if (h.kind == ColliderHandleKind.vertex) _removePoint(b, h.index);
      return true;
    }
    scope.history.breakMerge();
    _dragId++;
    _startShape = b.shape;
    _startOffset = b.offset;
    _startPointer = _unscale(toLocal(view.screenToWorld(screen)));
    if (h.kind == ColliderHandleKind.insert) {
      // The new point goes in between, and is what the drag moves.
      _insertPoint(b, h.index);
      _startShape = b.shape;
      h = ColliderHandle(ColliderHandleKind.vertex, h.index + 1, h.local);
    }
    _drag = h;
    hovered = h;
    return true;
  }

  /// The pointer moved while a handle is held. [symmetric] (Alt) resizes a
  /// box about its centre.
  void onPointerMove(Offset screen, EditorView view, {bool symmetric = false}) {
    final h = _drag, b = body;
    if (h == null || b == null) return;
    final p = _unscale(toLocal(view.screenToWorld(screen)));
    final (shape, offset) = _dragged(h, p, symmetric: symmetric);
    _push(b, shape, offset);
  }

  void onPointerUp() {
    _drag = null;
    scope.sceneState.refresh();
  }

  void cancel() => _drag = null;

  /// Esc stops editing; Delete takes away the point under the pointer.
  bool handleKey(LogicalKeyboardKey key) {
    if (!isActive) return false;
    if (key == LogicalKeyboardKey.escape) {
      stop();
      return true;
    }
    final h = hovered, b = body;
    if ((key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace) &&
        h != null &&
        b != null &&
        h.kind == ColliderHandleKind.vertex) {
      _removePoint(b, h.index);
      return true;
    }
    return false;
  }

  // ── Edits ────────────────────────────────────────────────────────────────

  static double _snap(double v) => (v * 2).roundToDouble() / 2;
  static Offset _snapP(Offset p) => Offset(_snap(p.dx), _snap(p.dy));

  /// The shape and offset [h] dragged to [p] (entity space) makes.
  (jge.CollisionShape, Offset) _dragged(
    ColliderHandle h,
    Offset p, {
    required bool symmetric,
  }) {
    final shape = _startShape;
    final o = _startOffset;
    final (sx, sy) = _scale;
    final grow = math.max(sx.abs(), sy.abs());
    switch (h.kind) {
      case ColliderHandleKind.center:
        return (shape, _snapP(o + (p - _startPointer)));
      case ColliderHandleKind.corner || ColliderHandleKind.side
          when shape is jge.RectangleShape:
        final hw = shape.width / 2, hh = shape.height / 2;
        final k = h.kind == ColliderHandleKind.corner
            ? const [
                Offset(-1, -1),
                Offset(1, -1),
                Offset(1, 1),
                Offset(-1, 1),
              ][h.index]
            : const [
                Offset(0, -1),
                Offset(1, 0),
                Offset(0, 1),
                Offset(-1, 0),
              ][h.index];
        var left = o.dx - hw, right = o.dx + hw;
        var top = o.dy - hh, bottom = o.dy + hh;
        if (k.dx != 0) {
          final x = _snap(p.dx);
          if (symmetric) {
            final half = (x - o.dx).abs();
            left = o.dx - half;
            right = o.dx + half;
          } else if (k.dx > 0) {
            right = x;
          } else {
            left = x;
          }
        }
        if (k.dy != 0) {
          final y = _snap(p.dy);
          if (symmetric) {
            final half = (y - o.dy).abs();
            top = o.dy - half;
            bottom = o.dy + half;
          } else if (k.dy > 0) {
            bottom = y;
          } else {
            top = y;
          }
        }
        final rect = Rect.fromLTRB(
          math.min(left, right),
          math.min(top, bottom),
          math.max(left, right),
          math.max(top, bottom),
        );
        return (
          jge.RectangleShape(math.max(rect.width, 1), math.max(rect.height, 1)),
          rect.center,
        );
      case ColliderHandleKind.radius when shape is jge.CircleShape:
        final centre = _scaled(shape.center + o);
        final r = (_scaled(p) - centre).distance / grow;
        return (
          jge.CircleShape(math.max(_snap(r), 0.5), center: shape.center),
          o,
        );
      case ColliderHandleKind.radius when shape is jge.CapsuleShape:
        final mid = (shape.center1 + shape.center2) / 2 + o;
        final axis = shape.center2 - shape.center1;
        final len = axis.distance;
        final n = len < 1e-9
            ? const Offset(1, 0)
            : Offset(-axis.dy, axis.dx) / len;
        final across = sx * sy == 0
            ? 1.0
            : (n.dx.abs() > n.dy.abs() ? sx.abs() : sy.abs());
        final d = (_scaled(p) - _scaled(mid));
        final r =
            (d.dx * n.dx * sx.sign + d.dy * n.dy * sy.sign).abs() / across;
        return (
          jge.CapsuleShape(
            center1: shape.center1,
            center2: shape.center2,
            radius: math.max(_snap(r), 0.5),
          ),
          o,
        );
      case ColliderHandleKind.end when shape is jge.CapsuleShape:
        final other = h.index == 0 ? shape.center2 : shape.center1;
        final tip = p - o;
        final out = tip - other;
        final len = out.distance;
        // The end's centre sits a radius back from the tip.
        final c = len <= shape.radius
            ? other
            : _snapP(tip - out / len * shape.radius);
        return (
          jge.CapsuleShape(
            center1: h.index == 0 ? c : shape.center1,
            center2: h.index == 0 ? shape.center2 : c,
            radius: shape.radius,
          ),
          o,
        );
      case ColliderHandleKind.vertex:
        final q = _snapP(p - o);
        return (_withPoint(shape, h.index, q), o);
      default:
        return (shape, o);
    }
  }

  static jge.CollisionShape _withPoint(
    jge.CollisionShape shape,
    int i,
    Offset q,
  ) {
    List<Offset> set(List<Offset> v) => [
      for (var k = 0; k < v.length; k++) k == i ? q : v[k],
    ];
    return switch (shape) {
      jge.RoundedPolygonShape p => jge.RoundedPolygonShape(
        set(p.vertices),
        p.cornerRadius,
      ),
      // A box whose corner moves is no longer a box.
      jge.PolygonShape p => jge.PolygonShape(set(p.vertices)),
      jge.SegmentShape s => jge.SegmentShape(
        i == 0 ? q : s.point1,
        i == 1 ? q : s.point2,
        thickness: s.thickness,
      ),
      jge.ChainShape c => jge.ChainShape(
        set(c.vertices),
        loop: c.loop,
        thickness: c.thickness,
      ),
      _ => shape,
    };
  }

  void _insertPoint(jge.PhysicsBodyComponent b, int edge) {
    List<Offset> add(List<Offset> v) {
      final a = v[edge], c = v[(edge + 1) % v.length];
      return [...v.take(edge + 1), (a + c) / 2, ...v.skip(edge + 1)];
    }

    final next = switch (b.shape) {
      jge.RoundedPolygonShape p => jge.RoundedPolygonShape(
        add(p.vertices),
        p.cornerRadius,
      ),
      jge.PolygonShape p => jge.PolygonShape(add(p.vertices)),
      jge.ChainShape c => jge.ChainShape(
        add(c.vertices),
        loop: c.loop,
        thickness: c.thickness,
      ),
      _ => null,
    };
    if (next != null) _push(b, next, b.offset);
  }

  void _removePoint(jge.PhysicsBodyComponent b, int i) {
    List<Offset> drop(List<Offset> v) => [
      for (var k = 0; k < v.length; k++)
        if (k != i) v[k],
    ];
    final next = switch (b.shape) {
      jge.RoundedPolygonShape p when p.vertices.length > 3 =>
        jge.RoundedPolygonShape(drop(p.vertices), p.cornerRadius),
      jge.PolygonShape p when p.vertices.length > 3 => jge.PolygonShape(
        drop(p.vertices),
      ),
      jge.ChainShape c when c.vertices.length > 2 => jge.ChainShape(
        drop(c.vertices),
        loop: c.loop,
        thickness: c.thickness,
      ),
      _ => null,
    };
    if (next == null) return;
    scope.history.breakMerge();
    _dragId++;
    _push(b, next, b.offset);
    hovered = null;
  }

  void _push(
    jge.PhysicsBodyComponent b,
    jge.CollisionShape shape,
    Offset offset,
  ) {
    scope.history.push(
      ColliderEditCommand(
        body: b,
        before: (b.shape, b.offset),
        after: (shape, offset),
        sceneState: scope.sceneState,
        gesture: _dragId,
      ),
    );
  }

  // ── Drawing ──────────────────────────────────────────────────────────────

  /// The collider and its handles, in screen space.
  void paint(Canvas canvas, EditorView view) {
    final b = body;
    if (b == null) return;
    final t = _transform;
    if (t == null) return;
    final (sx, sy) = _scale;
    final built = jge.ColliderGeometry.build(
      b.shape,
      offset: b.offset,
      sx: sx,
      sy: sy,
    );
    const accent = Color(0xFFFFB300);
    final at = view.worldToScreen(Offset(t.position.x, t.position.y));
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(t.angle)
      ..scale(view.zoom);
    jge.ColliderGeometry.paint(
      canvas,
      built,
      Paint()
        ..color = accent.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );
    jge.ColliderGeometry.paint(
      canvas,
      built,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / view.zoom,
    );
    canvas.restore();

    final fill = Paint()..color = const Color(0xFF1E1E1E);
    final ring = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final lit = Paint()..color = accent;
    for (final h in handles()) {
      final p = view.worldToScreen(toWorld(h.local));
      final on = h.same(hovered) || h.same(_drag);
      switch (h.kind) {
        case ColliderHandleKind.insert:
          canvas
            ..drawCircle(p, 3.5, on ? lit : fill)
            ..drawCircle(p, 3.5, ring..strokeWidth = 1);
          ring.strokeWidth = 1.5;
        case ColliderHandleKind.center:
          final path = Path()
            ..moveTo(p.dx, p.dy - 6)
            ..lineTo(p.dx + 6, p.dy)
            ..lineTo(p.dx, p.dy + 6)
            ..lineTo(p.dx - 6, p.dy)
            ..close();
          canvas
            ..drawPath(path, on ? lit : fill)
            ..drawPath(path, ring);
        case ColliderHandleKind.vertex ||
            ColliderHandleKind.radius ||
            ColliderHandleKind.end:
          canvas
            ..drawCircle(p, 5, on ? lit : fill)
            ..drawCircle(p, 5, ring);
        case ColliderHandleKind.corner || ColliderHandleKind.side:
          final r = Rect.fromCenter(center: p, width: 9, height: 9);
          canvas
            ..drawRect(r, on ? lit : fill)
            ..drawRect(r, ring);
      }
    }

    // What can be done here, under the collider.
    final bounds = jge.ColliderGeometry.boundsOf(built);
    final below = view.worldToScreen(
      toWorld(Offset(bounds.center.dx, bounds.bottom)),
    );
    final tip = TextPainter(
      text: TextSpan(
        text: _canInsert
            ? 'Drag points · ○ adds one · Alt-click removes · Esc: done'
            : 'Drag the handles · ◆ moves it · Alt: from the centre · Esc: done',
        style: const TextStyle(color: accent, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromCenter(
      center: below + Offset(0, 16 + tip.height / 2),
      width: tip.width + 12,
      height: tip.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()..color = const Color(0xCC111111),
    );
    tip.paint(canvas, box.topLeft + const Offset(6, 3));
  }
}

/// A change to a body's collider — its shape and offset together. One drag
/// of one handle is one of these, however many times the pointer moved.
class ColliderEditCommand extends EditorCommand {
  ColliderEditCommand({
    required this.body,
    required this.before,
    required this.after,
    required this.sceneState,
    required this.gesture,
  });

  final jge.PhysicsBodyComponent body;
  final (jge.CollisionShape, Offset) before;
  (jge.CollisionShape, Offset) after;
  final EditorSceneState sceneState;

  /// Which drag this belongs to: the moves of one merge.
  final int gesture;

  @override
  String get label => 'Edit collider';

  @override
  void redo() => _apply(after);

  @override
  void undo() => _apply(before);

  void _apply((jge.CollisionShape, Offset) value) {
    body
      ..shape = value.$1
      ..offset = value.$2;
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  bool mergeWith(EditorCommand next) {
    if (next is! ColliderEditCommand) return false;
    if (!identical(next.body, body) || next.gesture != gesture) return false;
    after = next.after;
    return true;
  }
}
