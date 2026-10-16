import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';
import '../../ui/inspector/physics/collider_edit_session.dart';
import '../../ui/level_designer/level_designer_session.dart';
import '../../ui/overlay/gizmo_3d.dart';
import '../../ui/overlay/gizmo_painter.dart';
import '../view/orbit_fly_editor_view.dart';
import 'gizmo_drag_solver.dart';
import 'ray_gizmo_drag_solver.dart';

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
    required EditorView Function() camera,
    required LevelDesignerSession? Function() designer,
    required this.gridSize,
    required this.isActive,
    required this.isAuthoring,
    this.isPickable,
    this.transformMode,
    this.transformModes,
    this.colliderEdit,
    this.handles,
    this.handleDrags,
    this.commitTransform,
    GizmoHitTester? hitTester,
    GizmoDragSolver? dragSolver,
    GizmoHitTester? hitTester3D,
    GizmoDragSolver? dragSolver3D,
    List<EntityRayTest> Function()? pickTests,
  }) : _worldOf = world,
       dragSolver = dragSolver ?? PlanarGizmoDragSolver(sceneState),
       dragSolver3D = dragSolver3D ?? RayGizmoDragSolver(sceneState),
       cameraOf = camera,
       designerOf = designer,
       hitTester = hitTester ?? GizmoHitTester(),
       hitTester3D =
           hitTester3D ??
           RayGizmoHitTester(tests: pickTests, local: () => sceneState.localGizmo);

  /// Whether an entity can be picked at all. The padlock in the scene
  /// tree answers false here; without it the lock did nothing outside
  /// the Level Designer, whose tools asked their own question.
  final bool Function(Entity entity)? isPickable;

  /// Which gizmo the selection shows, so a press takes only its handles.
  /// All when not given.
  final TransformMode Function()? transformMode;

  /// What the selection can take: All leaves off the handles of the rest.
  final Set<TransformMode> Function()? transformModes;

  /// Editing a body's collider, when that is on: its handles take a press
  /// before anything else, and the transform gizmo takes none.
  final ColliderEditSession Function()? colliderEdit;

  /// The points the selection lets the author drag ([ViewportHandles]):
  /// a press on one takes it before any tool or the gizmo.
  final List<ViewportHandle> Function()? handles;

  /// Drags of [handles], each one undo step.
  final HandleDragSession? handleDrags;

  /// The collider session, while one is editing something and the editor
  /// is authoring.
  ColliderEditSession? get _collider {
    final session = colliderEdit?.call();
    return session != null && session.isActive && isAuthoring()
        ? session
        : null;
  }

  final World Function() _worldOf;

  /// The world being edited. Read on use: an engine's world does not exist
  /// until it initialises, and the overlay builds before that.
  World get world => _worldOf();
  final EditorSceneState sceneState;
  final EditorView Function() cameraOf;
  final LevelDesignerSession? Function() designerOf;
  final double Function() gridSize;

  /// Whether the editor is initialised and visible.
  final bool Function() isActive;

  /// Whether the editor is authoring rather than play-testing.
  final bool Function() isAuthoring;
  final GizmoHitTester hitTester;

  /// What picks and finds gizmo handles when the view is in space.
  final GizmoHitTester hitTester3D;

  GizmoHandle? _activeHandle;

  /// What turns a drag of a gizmo handle into an edit.
  final GizmoDragSolver dragSolver;

  /// What turns a drag of a 3-D gizmo handle into an edit.
  final GizmoDragSolver dragSolver3D;

  // The solver of the drag under way: the view's kind when it began.
  GizmoDragSolver? _solver;

  GizmoHitTester _hitTesterFor(EditorView view) => view.isPlanar ? hitTester : hitTester3D;

  /// Opens the context menu at a pointer's local and global positions:
  /// set by the overlay. In 3-D a right-press is a look, so the menu opens
  /// on a right-click that did not drag.
  void Function(Offset local, Offset global)? openMenu;

  // 3-D navigation under way: a right-drag look (WASD flies while it
  // lasts), an Alt-drag orbit.
  bool _looking = false;
  double _lookTravel = 0;
  bool _orbiting = false;

  /// Whether the right button is held for a look: WASD flies, and the
  /// keys are not shortcuts meanwhile.
  bool get isLooking => _looking;

  /// While [isLooking], moves the 3-D view by the movement keys held:
  /// W/S ahead and back, A/D sideways, E/Q up and down; Shift faster.
  /// Called once a frame.
  void flyTick(double dt, Set<LogicalKeyboardKey> keys) {
    final view = cameraOf();
    if (!_looking || view is! OrbitFlyEditorView || dt <= 0) return;
    double axis(LogicalKeyboardKey plus, LogicalKeyboardKey minus) =>
        (keys.contains(plus) ? 1.0 : 0.0) - (keys.contains(minus) ? 1.0 : 0.0);
    final move = Vector3(
      axis(LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyA),
      axis(LogicalKeyboardKey.keyE, LogicalKeyboardKey.keyQ),
      axis(LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyS),
    );
    if (move.lengthSquared == 0) return;
    final fast = keys.contains(LogicalKeyboardKey.shiftLeft) || keys.contains(LogicalKeyboardKey.shiftRight);
    final speed = view.distance.clamp(2.0, 60.0) * (fast ? 3 : 1);
    view.fly(move * (speed * dt));
  }

  /// Records a finished gizmo drag as one undo step: given the drag's
  /// [TransformCommand], already applied. Without it a drag in the viewport
  /// cannot be undone.
  final void Function(TransformCommand command)? commitTransform;

  // The entity a gizmo drag is moving, and its transform when it began.
  Entity? _dragEntity;
  TransformSnapshot? _dragBefore;
  GizmoOp _dragOp = GizmoOp.none;

  /// Remembers where a drag of the selection began, and what it began from.
  void _beginDrag(Offset at) {
    final entity = sceneState.selectedEntity.value;
    if (entity == null) return;
    final solver = _solver = cameraOf().isPlanar ? dragSolver : dragSolver3D;
    solver.begin(entity, at);
    if (entity.getComponent<TransformComponent>() != null) {
      _dragEntity = entity;
      _dragBefore = TransformSnapshot.of(entity);
      _dragOp = _activeHandle?.op ?? GizmoOp.translate;
    }
  }

  /// Hands a finished drag to [commitTransform], when it changed anything.
  void _commitDrag() {
    final entity = _dragEntity, before = _dragBefore;
    _dragEntity = null;
    _dragBefore = null;
    final commit = commitTransform;
    if (entity == null || before == null || commit == null) return;
    if (!entity.isAlive) return;
    final after = TransformSnapshot.of(entity);
    if (before.matches(after)) return;
    final verb = switch (_dragOp) {
      GizmoOp.rotate => 'Rotate',
      GizmoOp.scale => 'Scale',
      _ => 'Move',
    };
    commit(
      TransformCommand(
        label: '$verb ${entity.name ?? 'entity'}',
        entities: [entity],
        before: [before],
        after: [after],
        sceneState: sceneState,
      ),
    );
  }

  /// Size of the game canvas, updated each frame by the overlay.
  Size canvasSize = Size.zero;

  // Middle-mouse-drag camera pan, mirroring Blender/Unity/Godot conventions.
  bool _isPanningCamera = false;

  /// Whether a gizmo drag is in progress: what keeps a dragged physics body
  /// from being fought by the simulation.
  bool get isDragging => _activeHandle != null;

  /// The gizmo handle being dragged, or [GizmoHandle.none].
  GizmoHandle get activeHandle => _activeHandle ?? GizmoHandle.none;

  /// What is under [localPosition] in the viewport, or null for bare
  /// level. The same hit test a click uses, so the menu opens on what a
  /// click would have selected.
  Entity? entityAt(Offset localPosition) {
    if (canvasSize == Size.zero) return null;
    final camera = cameraOf()..viewportSize = canvasSize;
    final pickable = isPickable;
    final hit = _hitTesterFor(camera).hitTest(
      localPosition,
      sceneState.selectedEntity.value,
      world
          .query([TransformComponent])
          .where((e) => e.isActive && (pickable == null || pickable(e)))
          .toList(),
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

  /// Handles a press on the canvas. Returns whether something took it — a
  /// right-button press nothing took opens the context menu.
  bool onPointerDown(PointerDownEvent event) {
    if (!isActive()) return false;
    if (canvasSize == Size.zero) return false;
    final view = cameraOf()..viewportSize = canvasSize;
    if (view is OrbitFlyEditorView && isAuthoring()) {
      // In 3-D: right-drag looks (a click without a drag opens the menu),
      // Alt-drag orbits.
      if ((event.buttons & kSecondaryButton) != 0) {
        _looking = true;
        _lookTravel = 0;
        _activeHandle = null;
        return true;
      }
      if ((event.buttons & kPrimaryButton) != 0 && HardwareKeyboard.instance.isAltPressed) {
        _orbiting = true;
        _activeHandle = null;
        return true;
      }
    }
    // The right button belongs to the context menu, which the overlay
    // opens — unless the Level Designer's tool asks for it: a tile brush
    // picks up tiles with a right-drag, as in Tiled.
    if ((event.buttons & kSecondaryButton) != 0) {
      final designer = designerOf();
      if (designer == null || !isAuthoring() || !designer.claimsSecondary()) {
        return false;
      }
      final camera = cameraOf()..viewportSize = canvasSize;
      final claimed = designer.onPointerDown(
        camera.screenToWorld(event.localPosition),
        gridSize(),
        screen: event.localPosition,
        canvasSize: canvasSize,
        button: ToolButton.secondary,
        time: event.timeStamp,
      );
      if (claimed) _activeHandle = null;
      return claimed;
    }

    // Middle-mouse-drag pans the camera — only while pure-authoring (Play
    // not pressed): during Play the camera brain owns the output camera and
    // would overwrite a manual pan the next frame.
    if ((event.buttons & kMiddleMouseButton) != 0 && isAuthoring()) {
      _isPanningCamera = true;
      _activeHandle = null;
      return true;
    }

    final camera = cameraOf();
    camera.viewportSize = canvasSize;

    // A collider being edited: its handles first, before any tool.
    final collider = _collider;
    if (collider != null &&
        collider.onPointerDown(
          event.localPosition,
          camera,
          remove: HardwareKeyboard.instance.isAltPressed,
        )) {
      _activeHandle = null;
      return true;
    }

    // A point of the selection to drag: before any tool, and the gizmo.
    final drags = handleDrags;
    if (drags != null &&
        isAuthoring() &&
        (event.buttons & kPrimaryButton) != 0 &&
        drags.down(
          event.localPosition,
          handles?.call() ?? const [],
          camera,
          alt: HardwareKeyboard.instance.isAltPressed,
        )) {
      _activeHandle = null;
      return true;
    }

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
        return true;
      }
      final worldPoint = camera.screenToWorld(event.localPosition);
      if (designer.onPointerDown(
        worldPoint,
        gridSize(),
        screen: event.localPosition,
        canvasSize: canvasSize,
        time: event.timeStamp,
      )) {
        _activeHandle = null;
        return true;
      }
    }

    final pickable = isPickable;
    final entities = world
        .query([TransformComponent])
        .where((e) => e.isActive && (pickable == null || pickable(e)))
        .toList();

    final hit = _hitTesterFor(camera).hitTest(
      event.localPosition,
      // While a collider is edited the gizmo is not there to take hold of.
      collider != null ? null : sceneState.selectedEntity.value,
      entities,
      camera,
      canvasSize,
      mode: transformMode?.call() ?? TransformMode.all,
      allows: transformModes?.call(),
    );

    // A press on the entity whose collider is edited leaves it where it is.
    if (collider != null && collider.isEditing(hit.entity)) {
      _activeHandle = null;
      return true;
    }

    if (hit.handle == GizmoHandle.none) {
      sceneState.clearSelection();
      _activeHandle = null;
      return false;
    }

    if (hit.handle == GizmoHandle.body) {
      // Body click selects; dragging selected body enables free XY move.
      if (hit.entity != null) {
        final wasSelected =
            sceneState.selectedEntity.value?.id == hit.entity!.id;
        sceneState.selectEntity(hit.entity!);
        if (wasSelected) {
          // A second press drags it: on the screen plane in 2-D, along
          // the ground in 3-D.
          _activeHandle = camera.isPlanar ? GizmoHandle.translateXY : GizmoHandle.translateXZ;
          _beginDrag(event.localPosition);
          return true;
        }
      }
      _activeHandle = null;
      return true;
    }

    {
      // Begin gizmo drag
      _activeHandle = hit.handle;
      _beginDrag(event.localPosition);
    }
    return true;
  }

  /// The pointer moved over the canvas with no button down: the Level
  /// Designer's tool may show what a click would do.
  void onPointerHover(PointerHoverEvent event) {
    if (!isActive() || canvasSize == Size.zero || !isAuthoring()) return;
    final collider = _collider;
    if (collider != null) {
      collider.onHover(
        event.localPosition,
        cameraOf()..viewportSize = canvasSize,
      );
    }
    final designer = designerOf();
    if (designer == null || designer.hasActiveGesture) return;
    final camera = cameraOf()..viewportSize = canvasSize;
    designer.onPointerHover(
      camera.screenToWorld(event.localPosition),
      gridSize(),
      screen: event.localPosition,
      canvasSize: canvasSize,
    );
  }

  /// The pointer left the canvas.
  void onPointerExit() => designerOf()?.onPointerExit();

  void onPointerMove(PointerMoveEvent event) {
    final drags = handleDrags;
    if (drags != null && drags.isDragging) {
      drags.move(
        event.localPosition,
        cameraOf()..viewportSize = canvasSize,
        snap: HardwareKeyboard.instance.isControlPressed,
        grid: gridSize(),
      );
      return;
    }
    final collider = colliderEdit?.call();
    if (collider != null && collider.isDragging) {
      collider.onPointerMove(
        event.localPosition,
        cameraOf()..viewportSize = canvasSize,
        symmetric: HardwareKeyboard.instance.isAltPressed,
      );
      return;
    }
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

    final view = cameraOf();
    if (view is OrbitFlyEditorView) {
      if (_looking) {
        _lookTravel += event.delta.distance;
        view.look(event.delta);
        return;
      }
      if (_orbiting) {
        view.orbit(event.delta);
        return;
      }
      if (_isPanningCamera) {
        view.pan(event.delta);
        return;
      }
    }

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

    (_solver ?? dragSolver).update(
      _activeHandle!,
      entity,
      event.localPosition,
      camera,
      constrain: HardwareKeyboard.instance.isShiftPressed,
    );
  }

  void onPointerUp(PointerUpEvent event) {
    if (_looking) {
      final clicked = _lookTravel < 4;
      _looking = false;
      if (clicked) openMenu?.call(event.localPosition, event.position);
      _resetPointerDragState();
      return;
    }
    final drags = handleDrags;
    if (drags != null && drags.isDragging) {
      drags.up();
      _resetPointerDragState();
      return;
    }
    final collider = colliderEdit?.call();
    if (collider != null && collider.isDragging) {
      collider.onPointerUp();
      _resetPointerDragState();
      return;
    }
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
    // A drag the OS cancels has still moved the entity, so it is recorded
    // too: undo is how to take it back.
    _commitDrag();
    handleDrags?.cancel();
    colliderEdit?.call().cancel();
    designerOf()?.onPointerCancel();
    _activeHandle = null;
    (_solver ?? dragSolver).end();
    _solver = null;
    _isPanningCamera = false;
    _looking = false;
    _orbiting = false;
  }

  /// Mouse-wheel zoom, centered on the cursor so the point under it stays
  /// fixed on screen. Same authoring-only gate as [onPointerDown]'s pan.
  void onPointerScroll(PointerSignalEvent event) {
    if (!isActive() || !isAuthoring()) return;
    if (event is! PointerScrollEvent) return;
    if (canvasSize == Size.zero) return;

    final camera = cameraOf();
    camera.viewportSize = canvasSize;
    if (camera is OrbitFlyEditorView) {
      // Scrolling up (negative dy) moves in.
      camera.dolly(-event.scrollDelta.dy * 0.0015);
      return;
    }

    final worldPoint = camera.screenToWorld(event.localPosition);
    // Scrolling up (negative dy) zooms in.
    final factor = math.exp(-event.scrollDelta.dy * 0.0015);
    camera.zoomToPoint(worldPoint, camera.zoom * factor);
  }
}
