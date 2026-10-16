import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../ui/overlay/gizmo_painter.dart';
import 'package:just_editor_core/host.dart';

/// Turns a drag of a gizmo handle into an edit of the entity's transform.
///
/// The viewport finds the handle under the pointer and hands every move to
/// one of these, so how a drag becomes a move, a turn or a scale is in one
/// place — and a 3-D gizmo, dragging along rays instead of across the
/// screen, is another solver behind the same three calls.
abstract interface class GizmoDragSolver {
  /// A drag of [entity]'s gizmo begins at the pixel [screen].
  void begin(Entity entity, Offset screen);

  /// The pointer is at [screen]: apply [handle]'s drag to [entity], seen
  /// through [view]. [constrain] (Shift) limits a free move to one axis.
  void update(
    GizmoHandle handle,
    Entity entity,
    Offset screen,
    EditorView view, {
    bool constrain = false,
  });

  /// The drag is over.
  void end();
}

/// The 2-D gizmo: moves across the view, turns about Z, scales x and y —
/// through [sceneState], so snapping applies and the hierarchy follows.
class PlanarGizmoDragSolver implements GizmoDragSolver {
  PlanarGizmoDragSolver(this.sceneState);

  final EditorSceneState sceneState;

  Offset? _dragStartScreen;

  /// Where a turn or a scale began, and what it began from: each is worked
  /// out from there, not step by step, so a snapped one moves a whole step
  /// when the pointer has gone far enough rather than never.
  Offset? _dragOriginScreen;
  double _startRotation = 0;
  double _turned = 0;
  Offset _startScale = const Offset(1, 1);
  Offset _startPosition = Offset.zero;

  @override
  void begin(Entity entity, Offset screen) {
    _dragStartScreen = screen;
    _dragOriginScreen = screen;
    final transform = entity.getComponent<TransformComponent>();
    _startRotation = transform?.angle ?? 0;
    _turned = 0;
    _startScale = transform == null
        ? const Offset(1, 1)
        : Offset(transform.scale.x, transform.scale.y);
    _startPosition = transform?.position.toOffset() ?? Offset.zero;
  }

  @override
  void end() {
    _dragStartScreen = null;
    _dragOriginScreen = null;
  }

  @override
  void update(
    GizmoHandle handle,
    Entity entity,
    Offset screen,
    EditorView view, {
    bool constrain = false,
  }) {
    if (_dragStartScreen == null) begin(entity, screen);
    switch (handle) {
      // Moves are measured from where the drag began, so a snapped one
      // steps once the pointer has gone far enough — step by step, each
      // small move would snap back to where it was.
      case GizmoHandle.translateXY:
        final worldNow = view.screenToWorld(screen);
        final worldStart = view.screenToWorld(
          _dragOriginScreen ?? _dragStartScreen!,
        );
        var dx = worldNow.dx - worldStart.dx;
        var dy = worldNow.dy - worldStart.dy;

        // Hold Shift to constrain free move to the dominant axis.
        if (constrain) {
          if (dx.abs() >= dy.abs()) {
            dy = 0;
          } else {
            dx = 0;
          }
        }

        sceneState.setPosition(entity, _startPosition + Offset(dx, dy));
        _dragStartScreen = screen;

      case GizmoHandle.translateX:
        final worldNow = view.screenToWorld(screen);
        final worldStart = view.screenToWorld(
          _dragOriginScreen ?? _dragStartScreen!,
        );
        sceneState.setPosition(
          entity,
          _startPosition + Offset(worldNow.dx - worldStart.dx, 0),
        );
        _dragStartScreen = screen;

      case GizmoHandle.translateY:
        final worldNow = view.screenToWorld(screen);
        final worldStart = view.screenToWorld(
          _dragOriginScreen ?? _dragStartScreen!,
        );
        sceneState.setPosition(
          entity,
          _startPosition + Offset(0, worldNow.dy - worldStart.dy),
        );
        _dragStartScreen = screen;

      case GizmoHandle.rotate:
        final transform = entity.getComponent<TransformComponent>();
        if (transform == null) break;
        final center = view.worldToScreen(transform.position.toOffset());
        final prev = _dragStartScreen! - center;
        final curr = screen - center;
        var delta = math.atan2(curr.dy, curr.dx) - math.atan2(prev.dy, prev.dx);
        // Across the ±π seam the difference jumps by a whole turn.
        if (delta > math.pi) delta -= 2 * math.pi;
        if (delta < -math.pi) delta += 2 * math.pi;
        _turned += delta;
        final target = sceneState.snapRotation(_startRotation + _turned);
        sceneState.applyRotation(entity, target - transform.angle);
        _dragStartScreen = screen;

      case GizmoHandle.scaleNW:
      case GizmoHandle.scaleNE:
      case GizmoHandle.scaleSE:
      case GizmoHandle.scaleSW:
        final transform = entity.getComponent<TransformComponent>();
        if (transform == null) break;
        final center = view.worldToScreen(transform.position.toOffset());
        final fromDist =
            ((_dragOriginScreen ?? _dragStartScreen!) - center).distance;
        final currDist = (screen - center).distance;
        if (fromDist > 0) {
          final ratio = currDist / fromDist;
          sceneState.setScale(
            entity,
            Offset(
              (_startScale.dx * ratio).clamp(0.01, 50.0),
              (_startScale.dy * ratio).clamp(0.01, 50.0),
            ),
          );
        }
        _dragStartScreen = screen;

      case GizmoHandle.scaleX:
        final transform = entity.getComponent<TransformComponent>();
        if (transform == null) break;
        final center = view.worldToScreen(transform.position.toOffset());
        final fromDistX =
            ((_dragOriginScreen ?? _dragStartScreen!).dx - center.dx).abs();
        final currDistX = (screen.dx - center.dx).abs();
        if (fromDistX > 0.5) {
          final newSx = (_startScale.dx * currDistX / fromDistX).clamp(
            0.01,
            50.0,
          );
          sceneState.setScaleX(entity, newSx);
        }
        _dragStartScreen = screen;

      case GizmoHandle.scaleY:
        final transform = entity.getComponent<TransformComponent>();
        if (transform == null) break;
        final center = view.worldToScreen(transform.position.toOffset());
        final fromDistY =
            ((_dragOriginScreen ?? _dragStartScreen!).dy - center.dy).abs();
        final currDistY = (screen.dy - center.dy).abs();
        if (fromDistY > 0.5) {
          final newSy = (_startScale.dy * currDistY / fromDistY).clamp(
            0.01,
            50.0,
          );
          sceneState.setScaleY(entity, newSy);
        }
        _dragStartScreen = screen;

      // Only a 3-D gizmo has these; a 3-D solver moves along them.
      case GizmoHandle.translateZ:
      case GizmoHandle.rotateX:
      case GizmoHandle.rotateY:
      case GizmoHandle.scaleZ:
      case GizmoHandle.translateXZ:
      case GizmoHandle.translateYZ:
      case GizmoHandle.scaleUniform:
      case GizmoHandle.body:
      case GizmoHandle.none:
        break;
    }
  }
}
