import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';

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
///
/// A handle changes only what it stands for — a box's size, a circle's
/// radius, a polygon's point, the offset — and leaves the collider its kind,
/// its turn, its own scale and its rounded corners: a turned box stays a
/// box, a rounded polygon keeps its points.
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

  /// The session of [scope]'s editor, kept in the scope's container so it
  /// is disposed with the scope.
  static ColliderEditSession of(EditorScope scope) {
    final container = scope.container;
    if (!container.isRegistered<ColliderEditSession>()) {
      container.registerLazySingleton<ColliderEditSession>(
        () => ColliderEditSession(scope),
        dispose: (session) => session.dispose(),
      );
    }
    return container.get<ColliderEditSession>();
  }

  final EditorScope scope;
  late final List<void Function()> _stops;

  /// Whose collider is being edited, or null.
  final Signal<jge.Entity?> target = Signal(null, debugLabel: 'colliderEdit');

  /// The handle under the pointer, drawn lit.
  ColliderHandle? hovered;

  ColliderHandle? _drag;
  late _ColliderFields _start;
  late Offset _startPointer; // entity space, unscaled
  int _dragId = 0;

  /// Screen pixels within which a press takes a handle.
  static const double grabRadius = 8;

  bool get isActive => body != null;

  bool get isDragging => _drag != null;

  /// The collider being edited, while its entity is alive and has one with
  /// a shape of its own — one matching what is drawn has none to edit.
  jge.Collider2D? get body {
    final e = target.value;
    if (e == null || !e.isAlive) return null;
    final c = e.getComponent<jge.Collider2D>();
    return c == null || c.shape == jge.ColliderShape2D.matchShape ? null : c;
  }

  /// Whether [entity]'s collider is the one being edited.
  bool isEditing(jge.Entity? entity) =>
      entity != null && identical(target.value, entity) && isActive;

  /// Edits [entity]'s collider, or stops when it already is.
  void toggle(jge.Entity entity) {
    if (isEditing(entity)) {
      stop();
    } else if (entity.getComponent<jge.Collider2D>()?.shape ==
        jge.ColliderShape2D.matchShape) {
      scope.log.log(
        'Its collider matches what is drawn: change what is drawn, or pick a shape for the collider to edit it.',
        source: 'editor',
        category: 'physics',
      );
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
  //
  // Three spaces: the collider's own (its shape with its own scale, not
  // turned and not moved — where sizes and points are measured), the
  // entity's (turned by the collider's rotation and moved by its offset,
  // before the entity's scale), and the body's (the entity's, scaled).

  jge.TransformComponent? get _transform =>
      target.value?.getComponent<jge.TransformComponent>();

  (double, double) get _scale {
    final t = _transform;
    double clean(double v) =>
        v.abs() < 1e-3 ? (v.isNegative ? -1e-3 : 1e-3) : v;
    return (clean(t?.scale.x ?? 1), clean(t?.scale.y ?? 1));
  }

  /// [c]'s own scale, as its shape is built with it.
  static (double, double) _ownScale(jge.Collider2D c) {
    double clean(double v) => v.abs() < jge.ColliderGeometry.minScale
        ? (v.isNegative
              ? -jge.ColliderGeometry.minScale
              : jge.ColliderGeometry.minScale)
        : v;
    return (clean(c.scale.x), clean(c.scale.y));
  }

  static Offset _rotate(Offset p, double angle) {
    if (angle == 0) return p;
    final c = math.cos(angle), s = math.sin(angle);
    return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
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

  /// [c]'s points in its own space: its saved points with its own scale.
  static List<Offset> _ownPoints(jge.Collider2D c) {
    final (cx, cy) = _ownScale(c);
    return [for (final p in c.points) Offset(p.dx * cx, p.dy * cy)];
  }

  /// [c]'s capsule in its own space: upright about its middle.
  static jge.CapsuleShape _capsuleOf(jge.Collider2D c) {
    final (cx, cy) = _ownScale(c);
    final r = math.max(c.radius.abs() * cx.abs(), 1e-3);
    final h = math.max(c.height.abs() * cy.abs(), 2 * r);
    return jge.CapsuleShape.vertical(height: h, radius: r);
  }

  /// [c]'s box in its own space, rounded corners and all: (width, height).
  static (double, double) _boxOf(jge.Collider2D c) {
    final (cx, cy) = _ownScale(c);
    return (
      math.max(c.size.x.abs() * cx.abs(), 1e-3),
      math.max(c.size.y.abs() * cy.abs(), 1e-3),
    );
  }

  /// Every handle of the collider, in the body's own space.
  List<ColliderHandle> handles() {
    final b = body;
    if (b == null) return const [];
    final o = b.offset;
    final turn = b.rotation;
    // A point of the collider's own space, in the body's.
    Offset at(Offset p) => _scaled(_rotate(p, turn) + o);
    final (sx, sy) = _scale;
    final grow = math.max(sx.abs(), sy.abs());
    final out = <ColliderHandle>[];
    switch (b.shape) {
      case jge.ColliderShape2D.circle:
        final (cx, cy) = _ownScale(b);
        final r = math.max(b.radius.abs() * math.max(cx.abs(), cy.abs()), 1e-3);
        final centre = _scaled(o);
        for (final (i, d) in const [
          (0, Offset(1, 0)),
          (1, Offset(0, 1)),
          (2, Offset(-1, 0)),
          (3, Offset(0, -1)),
        ]) {
          out.add(
            ColliderHandle(ColliderHandleKind.radius, i, centre + d * r * grow),
          );
        }
      case jge.ColliderShape2D.box:
        final (w, h) = _boxOf(b);
        final hw = w / 2, hh = h / 2;
        for (var i = 0; i < 4; i++) {
          final k = _corners[i];
          out.add(
            ColliderHandle(
              ColliderHandleKind.corner,
              i,
              at(Offset(k.dx * hw, k.dy * hh)),
            ),
          );
        }
        for (var i = 0; i < 4; i++) {
          final k = _sides[i];
          out.add(
            ColliderHandle(
              ColliderHandleKind.side,
              i,
              at(Offset(k.dx * hw, k.dy * hh)),
            ),
          );
        }
      case jge.ColliderShape2D.capsule:
        final c = _capsuleOf(b);
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
      case jge.ColliderShape2D.polygon:
        _points(
          out,
          _ownPoints(b),
          closed: true,
          at: at,
          canInsert: _canInsert,
        );
      case jge.ColliderShape2D.segment:
        final points = _ownPoints(b);
        for (var i = 0; i < math.min(2, points.length); i++) {
          out.add(ColliderHandle(ColliderHandleKind.vertex, i, at(points[i])));
        }
      case jge.ColliderShape2D.chain:
        _points(
          out,
          _ownPoints(b),
          closed: b.loop,
          at: at,
          canInsert: _canInsert,
        );
      case jge.ColliderShape2D.matchShape:
        break;
    }
    out.add(ColliderHandle(ColliderHandleKind.center, 0, _scaled(o)));
    return out;
  }

  static const _corners = [
    Offset(-1, -1),
    Offset(1, -1),
    Offset(1, 1),
    Offset(-1, 1),
  ];
  static const _sides = [
    Offset(0, -1),
    Offset(1, 0),
    Offset(0, 1),
    Offset(-1, 0),
  ];

  void _points(
    List<ColliderHandle> out,
    List<Offset> points, {
    required bool closed,
    required Offset Function(Offset) at,
    required bool canInsert,
  }) {
    for (var i = 0; i < points.length; i++) {
      out.add(ColliderHandle(ColliderHandleKind.vertex, i, at(points[i])));
    }
    if (!canInsert || points.length < 2) return;
    final edges = closed ? points.length : points.length - 1;
    for (var i = 0; i < edges; i++) {
      final a = points[i], b = points[(i + 1) % points.length];
      out.add(ColliderHandle(ColliderHandleKind.insert, i, at((a + b) / 2)));
    }
  }

  /// Points can be added to a polygon (a Box2D polygon has eight at most)
  /// and to a chain — not to a box, rounded or not.
  bool get _canInsert {
    final b = body;
    return switch (b?.shape) {
      jge.ColliderShape2D.polygon => b!.points.length < 8,
      jge.ColliderShape2D.chain => true,
      _ => false,
    };
  }

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
    _startPointer = _unscale(toLocal(view.screenToWorld(screen)));
    if (h.kind == ColliderHandleKind.insert) {
      // The new point goes in between, and is what the drag moves.
      _insertPoint(b, h.index);
      h = ColliderHandle(ColliderHandleKind.vertex, h.index + 1, h.local);
    }
    _start = _ColliderFields.of(b);
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
    if (!p.dx.isFinite || !p.dy.isFinite) return;
    _push(b, (c) => _dragged(c, h, p, symmetric: symmetric));
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

  /// Sets [c]'s fields to what dragging [h] to [p] (entity space) from
  /// where the drag began makes — only those the handle stands for.
  void _dragged(
    jge.Collider2D c,
    ColliderHandle h,
    Offset p, {
    required bool symmetric,
  }) {
    final start = _start;
    final o = start.offset;
    final turn = start.rotation;
    // The pointer in the collider's own space, as it was at the start.
    final q = _rotate(p - o, -turn);
    final (cx, cy) = _ownScale(c);
    final (sx, sy) = _scale;
    final grow = math.max(sx.abs(), sy.abs());
    switch (h.kind) {
      case ColliderHandleKind.center:
        c.offset = _snapP(o + (p - _startPointer));
      case ColliderHandleKind.corner || ColliderHandleKind.side
          when c.shape == jge.ColliderShape2D.box:
        final w = math.max(start.size.x.abs() * cx.abs(), 1e-3);
        final hgt = math.max(start.size.y.abs() * cy.abs(), 1e-3);
        final k = h.kind == ColliderHandleKind.corner
            ? _corners[h.index]
            : _sides[h.index];
        var left = -w / 2, right = w / 2;
        var top = -hgt / 2, bottom = hgt / 2;
        if (k.dx != 0) {
          final x = _snap(q.dx);
          if (symmetric) {
            left = -x.abs();
            right = x.abs();
          } else if (k.dx > 0) {
            right = x;
          } else {
            left = x;
          }
        }
        if (k.dy != 0) {
          final y = _snap(q.dy);
          if (symmetric) {
            top = -y.abs();
            bottom = y.abs();
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
        c
          ..size = jge.Vector2(
            math.max(rect.width, 1) / cx.abs(),
            math.max(rect.height, 1) / cy.abs(),
          )
          ..offset = o + _rotate(rect.center, turn);
      case ColliderHandleKind.radius when c.shape == jge.ColliderShape2D.circle:
        final r = (_scaled(p) - _scaled(o)).distance / grow;
        c.radius = math.max(_snap(r), 0.5) / math.max(cx.abs(), cy.abs());
      case ColliderHandleKind.radius
          when c.shape == jge.ColliderShape2D.capsule:
        final shape = start.capsule;
        final axis = _rotate(shape.center2 - shape.center1, turn);
        final len = axis.distance;
        final n = len < 1e-9
            ? const Offset(1, 0)
            : Offset(-axis.dy, axis.dx) / len;
        final across = sx * sy == 0
            ? 1.0
            : (n.dx.abs() > n.dy.abs() ? sx.abs() : sy.abs());
        final d = _scaled(p) - _scaled(o);
        final r =
            (d.dx * n.dx * sx.sign + d.dy * n.dy * sy.sign).abs() / across;
        c.radius = math.max(_snap(r), 0.5) / cx.abs();
      case ColliderHandleKind.end when c.shape == jge.ColliderShape2D.capsule:
        final shape = start.capsule;
        final other = h.index == 0 ? shape.center2 : shape.center1;
        final out = q - other;
        final len = out.distance;
        // The end's centre sits a radius back from the tip.
        final moved = len <= shape.radius
            ? other
            : _snapP(q - out / len * shape.radius);
        final c1 = h.index == 0 ? moved : shape.center1;
        final c2 = h.index == 0 ? shape.center2 : moved;
        final d = c2 - c1;
        // Still upright in its own space: the capsule turns instead.
        final extra = d.distance < 1e-9 ? 0.0 : math.atan2(-d.dx, d.dy);
        c
          ..height = (d.distance + 2 * shape.radius) / cy.abs()
          ..rotation = turn + extra
          ..offset = o + _rotate((c1 + c2) / 2, turn);
      case ColliderHandleKind.vertex:
        final points = start.points;
        if (h.index < 0 || h.index >= points.length) return;
        final at = _snapP(q);
        c.points = [
          for (var i = 0; i < points.length; i++)
            i == h.index ? Offset(at.dx / cx, at.dy / cy) : points[i],
        ];
      default:
        return;
    }
  }

  void _insertPoint(jge.Collider2D b, int edge) {
    if (!_canInsert) return;
    final v = b.points;
    if (edge < 0 || edge >= v.length) return;
    final a = v[edge], next = v[(edge + 1) % v.length];
    _push(b, (c) {
      c.points = [...v.take(edge + 1), (a + next) / 2, ...v.skip(edge + 1)];
    });
  }

  void _removePoint(jge.Collider2D b, int i) {
    final least = switch (b.shape) {
      jge.ColliderShape2D.polygon => 4,
      jge.ColliderShape2D.chain => 3,
      _ => null,
    };
    if (least == null || b.points.length < least) return;
    if (i < 0 || i >= b.points.length) return;
    scope.history.breakMerge();
    _dragId++;
    final v = b.points;
    _push(b, (c) {
      c.points = [
        for (var k = 0; k < v.length; k++)
          if (k != i) v[k],
      ];
    });
    hovered = null;
  }

  /// Makes [change] to [b] as part of this gesture's one undo step.
  void _push(jge.Collider2D b, void Function(jge.Collider2D) change) {
    final definition = scope.definitions.definitionFor(b);
    final before = ComponentEdit.snapshot(scope, b);
    if (definition == null || before == null) return;
    change(b);
    scope.history.push(
      ColliderEditCommand(
        collider: b,
        definition: definition,
        before: before,
        after: ComponentEdit.snapshot(scope, b)!,
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
      jge.ColliderGeometry.shapeOf(b) ?? jge.RectangleShape(1, 1),
      offset: b.offset,
      rotation: b.rotation,
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
    tip
      ..paint(canvas, box.topLeft + const Offset(6, 3))
      ..dispose();
  }
}

/// What a drag of a collider handle is measured from: the fields as they
/// were when it began.
class _ColliderFields {
  _ColliderFields.of(jge.Collider2D c)
    : offset = c.offset,
      rotation = c.rotation,
      size = jge.Vector2(c.size.x, c.size.y),
      points = List.unmodifiable(c.points),
      capsule = ColliderEditSession._capsuleOf(c);

  final Offset offset;
  final double rotation;
  final jge.Vector2 size;
  final List<Offset> points;

  /// The capsule in the collider's own space.
  final jge.CapsuleShape capsule;
}

/// A change to a collider — its shape, sizes and offset together, every
/// saved field as it was and as it is. One drag of one handle is one of
/// these, however many times the pointer moved.
class ColliderEditCommand extends EditorCommand {
  ColliderEditCommand({
    required this.collider,
    required this.definition,
    required this.before,
    required this.after,
    required this.sceneState,
    required this.gesture,
  });

  final jge.Collider2D collider;

  /// How [collider]'s fields are read and written.
  final jge.ComponentDefinition definition;

  /// Its saved fields before, and after.
  final Map<String, Object?> before;
  Map<String, Object?> after;
  final EditorSceneState sceneState;

  /// Which drag this belongs to: the moves of one merge.
  final int gesture;

  @override
  String get label => 'Edit collider';

  @override
  void redo() => _apply(after);

  @override
  void undo() => _apply(before);

  void _apply(Map<String, Object?> value) {
    for (final field in definition.fields) {
      if (field.write != null && value.containsKey(field.name)) {
        field.decodeInto(collider, value[field.name]);
      }
    }
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  bool mergeWith(EditorCommand next) {
    if (next is! ColliderEditCommand) return false;
    if (!identical(next.collider, collider) || next.gesture != gesture) {
      return false;
    }
    after = next.after;
    return true;
  }
}
