import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../ui/level_designer/level_designer_session.dart';
import '../../ui/overlay/gizmo_painter.dart';
import '../state/editor_scene_state.dart';

/// Turns pointer events on the game canvas into edits: gizmo drags, camera
/// pan and zoom, and, when the Level Designer is open, its tools and chrome.
///
/// Everything it needs from the plugin is read through a callback at the time
/// of the event, never captured, so it can never act on a stale camera,
/// designer or visibility.
class ViewportInput {
  ViewportInput({
    required World Function() world,
    required this.sceneState,
    required Camera Function() camera,
    required LevelDesignerSession? Function() designer,
    required this.gridSize,
    required this.isActive,
    required this.isAuthoring,
    GizmoHitTester? hitTester,
  }) : _worldOf = world,
       cameraOf = camera,
       designerOf = designer,
       hitTester = hitTester ?? GizmoHitTester();

  final World Function() _worldOf;

  /// The world being edited. Read on use: an engine's world does not exist
  /// until it initialises, and the overlay builds before that.
  World get world => _worldOf();
  final EditorSceneState sceneState;
  final Camera Function() cameraOf;
  final LevelDesignerSession? Function() designerOf;
  final double Function() gridSize;

  /// Whether the editor is initialised and visible.
  final bool Function() isActive;

  /// Whether the editor is authoring rather than play-testing.
  final bool Function() isAuthoring;
  final GizmoHitTester hitTester;

  GizmoHandle? _activeHandle;
  Offset? _dragStartScreen;

  /// Size of the game canvas, updated each frame by the overlay.
  Size canvasSize = Size.zero;

  // Middle-mouse-drag camera pan, mirroring Blender/Unity/Godot conventions.
  bool _isPanningCamera = false;

  /// Whether a gizmo drag is in progress: what keeps a dragged physics body
  /// from being fought by the simulation.
  bool get isDragging => _activeHandle != null;

  /// What is under [localPosition] in the viewport, or null for bare
  /// level. The same hit test a click uses, so the menu opens on what a
  /// click would have selected.
  Entity? entityAt(Offset localPosition) {
    if (canvasSize == Size.zero) return null;
    final camera = cameraOf()..viewportSize = canvasSize;
    final hit = hitTester.hitTest(
      localPosition,
      sceneState.selectedEntity.value,
      world.query([TransformComponent]).where((e) => e.isActive).toList(),
      camera,
      canvasSize,
    );
    return hit.entity;
  }

  /// Turns a point on the canvas into a point in the level.
  Offset worldPointAt(Offset localPosition) {
    final camera = cameraOf()..viewportSize = canvasSize;
    return camera.screenToWorld(localPosition);
  }

  /// Must be called with the canvas size so coordinate conversions are correct.
  void updateCanvasSize(Size size) {
    canvasSize = size;
  }

  void onPointerDown(PointerDownEvent event) {
    if (!isActive()) return;
    if (canvasSize == Size.zero) return;
    // The right button belongs to the context menu, which the overlay
    // opens: selecting and dragging are the left button's business.
    if ((event.buttons & kSecondaryButton) != 0) return;

    // Middle-mouse-drag pans the camera — only while pure-authoring (Play
    // not pressed): during Play the camera brain owns the output camera and
    // would overwrite a manual pan the next frame.
    if ((event.buttons & kMiddleMouseButton) != 0 && isAuthoring()) {
      _isPanningCamera = true;
      _activeHandle = null;
      return;
    }

    final camera = cameraOf();
    camera.viewportSize = canvasSize;

    // The Level Designer's active tool gets first refusal. A tool that claims
    // the gesture (marquee, draw, paint) handles it entirely; one that
    // declines falls through to the gizmo handling below, which is what keeps
    // single-entity translate/rotate/scale working inside the designer.
    final designer = designerOf();
    if (designer != null && isAuthoring()) {
      // Rulers and the minimap are screen-space chrome and sit on top of the
      // level, so they are offered the press before any tool.
      if (designer.onChromePointerDown(
        event.localPosition,
        canvasSize,
        gridSize: gridSize(),
      )) {
        _activeHandle = null;
        return;
      }
      final worldPoint = camera.screenToWorld(event.localPosition);
      if (designer.onPointerDown(
        worldPoint,
        gridSize(),
        screen: event.localPosition,
        canvasSize: canvasSize,
      )) {
        _activeHandle = null;
        return;
      }
    }

    final entities = world
        .query([TransformComponent])
        .where((e) => e.isActive)
        .toList();

    final hit = hitTester.hitTest(
      event.localPosition,
      sceneState.selectedEntity.value,
      entities,
      camera,
      canvasSize,
    );

    if (hit.handle == GizmoHandle.none) {
      sceneState.clearSelection();
      _activeHandle = null;
      return;
    }

    if (hit.handle == GizmoHandle.body) {
      // Body click selects; dragging selected body enables free XY move.
      if (hit.entity != null) {
        final wasSelected =
            sceneState.selectedEntity.value?.id == hit.entity!.id;
        sceneState.selectEntity(hit.entity!);
        if (wasSelected) {
          _activeHandle = GizmoHandle.translateXY;
          _dragStartScreen = event.localPosition;
          return;
        }
      }
      _activeHandle = null;
      return;
    }

    {
      // Begin gizmo drag
      _activeHandle = hit.handle;
      _dragStartScreen = event.localPosition;
    }
  }

  void onPointerMove(PointerMoveEvent event) {
    final designer = designerOf();
    if (designer != null && designer.hasChromeGesture) {
      cameraOf().viewportSize = canvasSize;
      designer.onChromePointerMove(event.localPosition, canvasSize, gridSize());
      return;
    }
    if (designer != null && designer.hasActiveGesture) {
      final camera = cameraOf();
      camera.viewportSize = canvasSize;
      designer.onPointerMove(
        camera.screenToWorld(event.localPosition),
        gridSize(),
        screen: event.localPosition,
        canvasSize: canvasSize,
      );
      return;
    }

    if (!isActive()) return;

    if (_isPanningCamera) {
      final camera = cameraOf();
      // Drag right/down should move the view (and thus the world under the
      // cursor) right/down, i.e. the camera moves the opposite way.
      camera.moveBy(-event.delta / camera.zoom);
      return;
    }

    if (_activeHandle == null || _activeHandle == GizmoHandle.none) return;

    final entity = sceneState.selectedEntity.value;
    if (entity == null) return;

    final camera = cameraOf();
    camera.viewportSize = canvasSize;

    switch (_activeHandle!) {
      case GizmoHandle.translateXY:
        final worldNow = camera.screenToWorld(event.localPosition);
        final worldStart = camera.screenToWorld(_dragStartScreen!);
        var dx = worldNow.dx - worldStart.dx;
        var dy = worldNow.dy - worldStart.dy;

        // Hold Shift to constrain free move to the dominant axis.
        if (HardwareKeyboard.instance.isShiftPressed) {
          if (dx.abs() >= dy.abs()) {
            dy = 0;
          } else {
            dx = 0;
          }
        }

        sceneState.applyTranslation(entity, Offset(dx, dy));
        _dragStartScreen = event.localPosition;

      case GizmoHandle.translateX:
        final worldNow = camera.screenToWorld(event.localPosition);
        final worldStart = camera.screenToWorld(_dragStartScreen!);
        sceneState.applyTranslation(
          entity,
          Offset(worldNow.dx - worldStart.dx, 0),
        );
        _dragStartScreen = event.localPosition;

      case GizmoHandle.translateY:
        final worldNow = camera.screenToWorld(event.localPosition);
        final worldStart = camera.screenToWorld(_dragStartScreen!);
        sceneState.applyTranslation(
          entity,
          Offset(0, worldNow.dy - worldStart.dy),
        );
        _dragStartScreen = event.localPosition;

      case GizmoHandle.rotate:
        final transform = entity.getComponent<TransformComponent>();
        if (transform == null) break;
        final center = camera.worldToScreen(transform.position.toOffset());
        final prev = _dragStartScreen! - center;
        final curr = event.localPosition - center;
        final delta =
            math.atan2(curr.dy, curr.dx) - math.atan2(prev.dy, prev.dx);
        sceneState.applyRotation(entity, delta);
        _dragStartScreen = event.localPosition;

      case GizmoHandle.scaleNW:
      case GizmoHandle.scaleNE:
      case GizmoHandle.scaleSE:
      case GizmoHandle.scaleSW:
        final transform = entity.getComponent<TransformComponent>();
        if (transform == null) break;
        final center = camera.worldToScreen(transform.position.toOffset());
        final prevDist = (_dragStartScreen! - center).distance;
        final currDist = (event.localPosition - center).distance;
        if (prevDist > 0) {
          sceneState.applyScale(entity, currDist / prevDist);
        }
        _dragStartScreen = event.localPosition;

      case GizmoHandle.scaleX:
        final transform = entity.getComponent<TransformComponent>();
        if (transform == null) break;
        final center = camera.worldToScreen(transform.position.toOffset());
        final prevDistX = (_dragStartScreen!.dx - center.dx).abs();
        final currDistX = (event.localPosition.dx - center.dx).abs();
        if (prevDistX > 0.5) {
          final newSx = (transform.scale.x * currDistX / prevDistX).clamp(
            0.01,
            50.0,
          );
          sceneState.setScaleX(entity, newSx);
        }
        _dragStartScreen = event.localPosition;

      case GizmoHandle.scaleY:
        final transform = entity.getComponent<TransformComponent>();
        if (transform == null) break;
        final center = camera.worldToScreen(transform.position.toOffset());
        final prevDistY = (_dragStartScreen!.dy - center.dy).abs();
        final currDistY = (event.localPosition.dy - center.dy).abs();
        if (prevDistY > 0.5) {
          final newSy = (transform.scale.y * currDistY / prevDistY).clamp(
            0.01,
            50.0,
          );
          sceneState.setScaleY(entity, newSy);
        }
        _dragStartScreen = event.localPosition;

      case GizmoHandle.body:
      case GizmoHandle.none:
        break;
    }
  }

  void onPointerUp(PointerUpEvent event) {
    final designer = designerOf();
    if (designer != null && designer.hasChromeGesture) {
      designer.onChromePointerUp(
        event.localPosition,
        canvasSize,
        gridSize: gridSize(),
      );
      _resetPointerDragState();
      return;
    }
    if (designer != null && designer.hasActiveGesture) {
      final camera = cameraOf();
      camera.viewportSize = canvasSize;
      designer.onPointerUp(
        camera.screenToWorld(event.localPosition),
        gridSize(),
        screen: event.localPosition,
        canvasSize: canvasSize,
      );
    }
    _resetPointerDragState();
  }

  /// A gesture the OS/Flutter interrupts (window loses focus mid-drag, the
  /// gesture arena is stolen by another widget, a second touch cancels the
  /// first) is delivered as [PointerCancelEvent], not [PointerUpEvent] — if
  /// this weren't wired up too, [_activeHandle]/[_isPanningCamera] would get
  /// stuck "on" and silently hijack the next unrelated pointer gesture.
  void onPointerCancel(PointerCancelEvent event) => _resetPointerDragState();

  void _resetPointerDragState() {
    designerOf()?.onPointerCancel();
    _activeHandle = null;
    _dragStartScreen = null;
    _isPanningCamera = false;
  }

  /// Mouse-wheel zoom, centered on the cursor so the point under it stays
  /// fixed on screen. Same authoring-only gate as [onPointerDown]'s pan.
  void onPointerScroll(PointerSignalEvent event) {
    if (!isActive() || !isAuthoring()) return;
    if (event is! PointerScrollEvent) return;
    if (canvasSize == Size.zero) return;

    final camera = cameraOf();
    camera.viewportSize = canvasSize;

    final worldPoint = camera.screenToWorld(event.localPosition);
    // Scrolling up (negative dy) zooms in.
    final factor = math.exp(-event.scrollDelta.dy * 0.0015);
    camera.zoomToPoint(worldPoint, camera.zoom * factor);
  }
}
