import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../debugger/engine_debugger.dart';
import '../ecs/components/editor_components_registrant.dart';
import '../ecs/systems/editor_animated_sprite_system.dart';
import '../ecs/systems/editor_animation_controller_system.dart';
import '../ecs/systems/editor_log_capture_system.dart';
import '../ecs/systems/editor_sprite_system.dart';
import '../ecs/systems/physics_body_binding_system.dart';
import '../ecs/systems/physics_joint_binding_system.dart';
import '../ecs/systems/simple_movement_system.dart';
import '../serialization/scene_file_generator.dart';
import '../serialization/scene_manager.dart';
import '../services/editor_log_service.dart';
import '../state/editor_scene_state.dart';
import '../../ui/overlay/gizmo_painter.dart';
import '../ecs/generator/component_registry.dart';

/// Hypothetical plugin contract used by runtime editor integrations.
abstract interface class EnginePlugin {
  Future<void> onInitialize();
  void onUpdate(double dt);
  void onRender(Canvas canvas, Size size);
}

/// Play/Pause/Stop state for the editor's in-scene play-test feature.
enum EditorPlayState { stopped, playing, paused }

/// Debug-only runtime editor plugin scaffold.
class JustGameEditorPlugin extends ChangeNotifier implements EnginePlugin {
  JustGameEditorPlugin({
    required this.engine,
    this.componentRegistrar,
    this.spawnRegistry = const {},
    this.bindPhysicsBodies = true,
    LogicalKeyboardKey toggleKey = LogicalKeyboardKey.f1,
    LogicalKeyboardKey statusPanelToggleKey = LogicalKeyboardKey.f2,
    Set<String> protectedSceneNames = const {},
  }) : _toggleKey = toggleKey,
       _statusPanelToggleKey = statusPanelToggleKey,
       debuggerController = engine.createDebuggerController(
         overlayVisible: false,
         attachImmediately: false,
       ),
       sceneState = EditorSceneState()
         ..setGridSnapping(enabled: true, gridSize: 32),
       sceneManager = SceneManager(protectedSceneNames: protectedSceneNames),
       _gizmoPainter = GizmoPainter(),
       _hitTester = GizmoHitTester();

  final Engine engine;

  /// Scene lifecycle operations (list/delete/rename/duplicate) for the
  /// scene picker.
  final SceneManager sceneManager;

  /// Optional callback that registers all game custom components with
  /// [CustomComponentRegistry.instance]. Called automatically during
  /// [onInitialize] and again on [reassemble] (hot-reload) and after a
  /// successful component codegen refresh.
  final VoidCallback? componentRegistrar;

  /// Maps a [SpawnComponent.tag] to a function that creates the entity for
  /// it. The editor's Play button calls this for every [SpawnComponent]
  /// entity in the world (once per play session) — the app owns what
  /// actually gets created (a player, a zombie, ...), the editor just knows
  /// where and when to ask for it.
  final Map<String, Entity Function(World world, Entity spawnPoint)>
  spawnRegistry;

  /// Whether to enable gizmo-drag-to-move authoring for physics bodies
  /// (registers [PhysicsBodyBindingSystem]/[PhysicsJointBindingSystem]).
  ///
  /// [PhysicsSystem] (core engine) always owns physics-body lifecycle and
  /// [Engine.physics] stepping when it's present in the game's `World` —
  /// this flag doesn't affect that. It only gates the thin authoring
  /// override that makes a selected/dragged body feel immediate (zeroing
  /// residual velocity, waking the body) and joint authoring. Safe to leave
  /// at its default in any game.
  final bool bindPhysicsBodies;

  // ── Static project-component registration ──────────────────────────────────

  static final List<VoidCallback> _staticProjectRegistrants = [];

  /// Registers [fn] as a project-level component registrant.
  ///
  /// Call this **once** at app startup, before or after the plugin is
  /// created. The editor calls [fn] automatically on every
  /// [reassemble] (hot-reload) so newly generated descriptors are
  /// picked up without any extra setup.
  ///
  /// Typical usage:
  /// ```dart
  /// // Import your generated registrant once:
  /// import 'game/custom_components/generated_component_registrant.dart';
  ///
  /// JustGameEditorPlugin.registerProjectComponents(registerCustomComponents);
  /// ```
  static void registerProjectComponents(VoidCallback fn) {
    if (!_staticProjectRegistrants.contains(fn)) {
      _staticProjectRegistrants.add(fn);
    }
  }

  /// Removes a previously registered project-component registrant.
  static void unregisterProjectComponents(VoidCallback fn) {
    _staticProjectRegistrants.remove(fn);
  }

  final LogicalKeyboardKey _toggleKey;
  final LogicalKeyboardKey _statusPanelToggleKey;
  final JustDebuggerController debuggerController;

  /// Shared scene state — read by overlay widgets and gizmo logic.
  final EditorSceneState sceneState;
  final EditorLogService logService = EditorLogService.instance;

  final GizmoPainter _gizmoPainter;
  final GizmoHitTester _hitTester;

  // Guards openScene()/saveScene() against re-entrancy: without it, a
  // double-click in the scene picker (or Ctrl+S fired again before a prior
  // save's file writes complete) can interleave two scene-file writes, or
  // let a save-in-flight's markClean() land against a scene opened after it
  // started.
  bool _isSceneIOBusy = false;
  bool _isInitialized = false;
  bool _isVisible = false;
  bool _isStatusPanelVisible = false;
  bool _isDebuggerAttached = false;
  bool _showGrid = true;
  bool _gridSnappingEnabled = true;
  double _gridSize = 32.0;

  /// [engine.time.timeScale] captured when the editor is opened, restored
  /// when it's closed again.
  double? _preEditorTimeScale;

  // ── Play / Pause / Stop (editor-only play-test) ───────────────────────────

  EditorPlayState _playState = EditorPlayState.stopped;
  final List<EntityId> _spawnedRuntimeEntityIds = [];

  EditorPlayState get playState => _playState;

  /// True whenever the editor should behave as "authoring" (camera-entity
  /// sync, transform→physics-body pushes, and the Timeline preview's
  /// timeScale bump all pause/suppress) rather than "simulating" — i.e. the
  /// editor is open and no play-test is in progress.
  bool get _isAuthoring => _isVisible && _playState == EditorPlayState.stopped;

  // ── Pointer / drag state ──────────────────────────────────────────────────

  GizmoHandle? _activeHandle;
  Offset? _dragStartScreen;

  // Size of the game canvas area (updated each frame from the Listener widget)
  Size _canvasSize = Size.zero;

  // Middle-mouse-drag camera pan, mirroring Blender/Unity/Godot conventions.
  bool _isPanningCamera = false;

  // ── Focus nodes ───────────────────────────────────────────────────────────

  final FocusScopeNode gameFocusScopeNode = FocusScopeNode(
    debugLabel: 'just-game-editor-game-scope',
  );
  final FocusNode editorFocusNode = FocusNode(
    debugLabel: 'just-game-editor-overlay-focus',
  );

  bool get isInitialized => _isInitialized;
  bool get isVisible => _isVisible;
  bool get isStatusPanelVisible => _isStatusPanelVisible;
  LogicalKeyboardKey get toggleKey => _toggleKey;
  LogicalKeyboardKey get statusPanelToggleKey => _statusPanelToggleKey;

  /// Factory for debug-only plugin registration.
  ///
  /// Pass [componentRegistrar] to automatically register game-specific
  /// custom components when the editor initializes and on hot-reload.
  static Future<JustGameEditorPlugin?> register({
    required Engine engine,
    VoidCallback? componentRegistrar,
    Map<String, Entity Function(World world, Entity spawnPoint)> spawnRegistry =
        const {},
    bool bindPhysicsBodies = true,
    LogicalKeyboardKey toggleKey = LogicalKeyboardKey.f1,
    LogicalKeyboardKey statusPanelToggleKey = LogicalKeyboardKey.f2,
    Set<String> protectedSceneNames = const {},
  }) async {
    if (!kDebugMode) return null;

    final plugin = JustGameEditorPlugin(
      engine: engine,
      componentRegistrar: componentRegistrar,
      spawnRegistry: spawnRegistry,
      bindPhysicsBodies: bindPhysicsBodies,
      toggleKey: toggleKey,
      statusPanelToggleKey: statusPanelToggleKey,
      protectedSceneNames: protectedSceneNames,
    );
    await plugin.onInitialize();
    return plugin;
  }

  @override
  Future<void> onInitialize() async {
    if (!kDebugMode || _isInitialized) return;
    _isInitialized = true;
    await logService.startSession(controller: debuggerController);
    if (!engine.world.systems.any((system) => system is SimpleMovementSystem)) {
      engine.world.addSystem(SimpleMovementSystem(engine.input));
    }
    if (bindPhysicsBodies) {
      // No PhysicsBridgeSystem here — PhysicsSystem (core engine) now owns
      // syncing PhysicsBody results back to TransformComponent itself, for
      // every PhysicsBodyComponent entity, not just editor-authored ones.
      if (!engine.world.systems.any(
        (system) => system is PhysicsBodyBindingSystem,
      )) {
        engine.world.addSystem(
          PhysicsBodyBindingSystem(
            sceneState: sceneState,
            isAuthoringActive: () => _isAuthoring,
            isDraggingActive: () => _activeHandle != null,
          ),
        );
      }
      if (!engine.world.systems.any(
        (system) => system is PhysicsJointBindingSystem,
      )) {
        engine.world.addSystem(PhysicsJointBindingSystem(engine.physics));
      }
    }
    if (!engine.world.systems.any(
      (system) => system is EditorLogCaptureSystem,
    )) {
      engine.world.addSystem(EditorLogCaptureSystem(logService));
    }
    if (!engine.world.systems.any((system) => system is EditorSpriteSystem)) {
      engine.world.addSystem(EditorSpriteSystem());
    }
    if (!engine.world.systems.any(
      (system) => system is EditorAnimatedSpriteSystem,
    )) {
      engine.world.addSystem(EditorAnimatedSpriteSystem());
    }
    if (!engine.world.systems.any(
      (system) => system is EditorAnimationControllerSystem,
    )) {
      engine.world.addSystem(EditorAnimationControllerSystem());
    }
    // A scene's camera entity should only drive the real camera during
    // actual play — while authoring (editor open, Play not pressed) there's
    // no manual pan/zoom to fall back on, so these (added by the app's own
    // system registration, if present) must not hijack the authoring
    // viewport. Pressing Play un-suppresses them so the test camera follows
    // the player properly.
    engine.world.getSystem<CameraFollowSystem>()?.isAuthoringActive = () =>
        _isAuthoring;
    engine.world
        .getSystem<CameraTransformSyncSystem>()
        ?.isAuthoringActive = () =>
        _isAuthoring;
    _attachDebuggerIfReady();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    // Register game custom components and wire post-refresh re-registration.
    _runComponentRegistrar();
    sceneState.onComponentsRefreshed = _runComponentRegistrar;
    logService.log(
      'Runtime editor initialized.',
      source: 'editor',
      category: 'lifecycle',
    );
  }

  /// Re-registers all game custom components. Clears first so stale
  /// descriptors from a previous build are removed before the new ones land.
  void _runComponentRegistrar() {
    CustomComponentRegistry.instance.clear();
    registerAllEditorComponents();
    // Call all static project registrants (registered via
    // JustGameEditorPlugin.registerProjectComponents).
    for (final fn in _staticProjectRegistrants) {
      fn();
    }
    // Legacy per-instance callback for backward compatibility.
    componentRegistrar?.call();
    logService.log(
      'Custom component registries reloaded.',
      source: 'editor',
      category: 'components',
      mirrorToDebugger: false,
    );
  }

  /// Called by [State.reassemble] on hot-reload to pick up newly generated
  /// component descriptors without restarting the app.
  void reassemble() => _runComponentRegistrar();

  void _attachDebuggerIfReady() {
    if (_isDebuggerAttached || !engine.isInitialized) return;
    engine.attachDebugger(debuggerController);
    _isDebuggerAttached = true;
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!_isInitialized) return false;
    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == _toggleKey) {
      toggleVisibility();
      return true;
    }

    if (event.logicalKey == _statusPanelToggleKey) {
      toggleStatusPanelVisibility();
      return true;
    }

    if (!_isVisible) return false;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      final selected = sceneState.selectedEntity;
      if (selected != null) copyEntity(selected);
      return true;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      pasteEntity();
      return true;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyS) {
      saveScene();
      return true;
    }

    return false;
  }

  @override
  void onUpdate(double dt) {
    _attachDebuggerIfReady();
    if (!_isInitialized || !_isVisible) return;
    _syncTimeScaleForPreview();
  }

  /// While the editor is open and authoring (Play not pressed),
  /// [engine.time.timeScale] is held at 0 so the game underneath is
  /// effectively paused. If the selected entity's animation preview
  /// (Timeline dock's Play button) is running, the preview systems ride on
  /// the same scaled deltaTime as gameplay — so timeScale is bumped back to
  /// 1 for as long as it's playing, and dropped back to 0 once it
  /// stops/pauses. Deliberately skipped outside pure authoring — [play]/
  /// [pause]/[stop] own timeScale once a play-test session has started.
  void _syncTimeScaleForPreview() {
    if (!engine.isInitialized) return;
    if (_playState != EditorPlayState.stopped) return;
    final entity = sceneState.selectedEntity;
    final isPreviewPlaying =
        entity != null &&
        ((entity.getComponent<AnimatedSpriteComponent>()?.isPlaying ?? false) ||
            (entity.getComponent<AnimationControllerComponent>()?.isPlaying ??
                false));
    engine.time.timeScale = isPreviewPlaying ? 1.0 : 0.0;
  }

  /// Called by [GameEditorAdapter] via the [onRenderOverlay] chain,
  /// AFTER [engine.world.render].  Applies the camera transform so gizmos
  /// render in world space on top of all ECS entities.
  ///
  /// [size] is the actual canvas size [RenderingEngine] just rendered with —
  /// used here (rather than the separately-tracked [_canvasSize], which is
  /// only updated via a post-frame callback from pointer-event plumbing and
  /// can drift/lag a frame behind) so gizmo/marker positions always match
  /// where entities were actually drawn.
  @override
  void onRender(Canvas canvas, Size size) {
    if (!_isInitialized || !_isVisible) return;
    if (size == Size.zero) return;

    final camera = engine.cameraSystem.mainCamera;

    if (_showGrid) {
      _gizmoPainter.paintInfiniteGrid(
        canvas,
        camera,
        size,
        gridSize: _gridSize,
      );
    }

    _gizmoPainter.paintCameraMarkers(
      canvas,
      engine.world.query([TransformComponent, CameraComponent]),
      camera,
      size,
    );

    _gizmoPainter.paintSpawnMarkers(
      canvas,
      engine.world.query([TransformComponent, SpawnComponent]),
      camera,
      size,
    );

    final selected = sceneState.selectedEntity;
    if (selected == null || !selected.isActive) return;
    _gizmoPainter.paintGizmos(canvas, selected, camera, size);
  }

  void applyOverlaySettings({
    required bool showGrid,
    required bool gridSnappingEnabled,
    required double gridSize,
  }) {
    final nextGridSize = gridSize <= 0 ? 32.0 : gridSize;
    _showGrid = showGrid;
    _gridSnappingEnabled = gridSnappingEnabled;
    _gridSize = nextGridSize;
    sceneState.setGridSnapping(
      enabled: _gridSnappingEnabled,
      gridSize: _gridSize,
    );
  }

  // ── Pointer events (called from _GameCanvasArea Listener) ────────────────

  /// Must be called with the canvas size so coordinate conversions are correct.
  void updateCanvasSize(Size size) {
    _canvasSize = size;
  }

  void onPointerDown(PointerDownEvent event) {
    if (!_isInitialized || !_isVisible) return;
    if (_canvasSize == Size.zero) return;

    // Middle-mouse-drag pans the camera — only while pure-authoring (Play
    // not pressed): once a scene has a camera entity, CameraTransformSyncSystem
    // re-asserts mainCamera's position from it every frame during Play, which
    // would fight a manual pan immediately.
    if ((event.buttons & kMiddleMouseButton) != 0 && _isAuthoring) {
      _isPanningCamera = true;
      _activeHandle = null;
      return;
    }

    final camera = engine.cameraSystem.mainCamera;
    camera.viewportSize = _canvasSize;

    final entities = engine.world
        .query([TransformComponent])
        .where((e) => e.isActive)
        .toList();

    final hit = _hitTester.hitTest(
      event.localPosition,
      sceneState.selectedEntity,
      entities,
      camera,
      _canvasSize,
    );

    if (hit.handle == GizmoHandle.none) {
      sceneState.clearSelection();
      _activeHandle = null;
      return;
    }

    if (hit.handle == GizmoHandle.body) {
      // Body click selects; dragging selected body enables free XY move.
      if (hit.entity != null) {
        final wasSelected = sceneState.selectedEntity?.id == hit.entity!.id;
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
    if (!_isInitialized || !_isVisible) return;

    if (_isPanningCamera) {
      final camera = engine.cameraSystem.mainCamera;
      // Drag right/down should move the view (and thus the world under the
      // cursor) right/down, i.e. the camera moves the opposite way.
      camera.moveBy(-event.delta / camera.zoom);
      return;
    }

    if (_activeHandle == null || _activeHandle == GizmoHandle.none) return;

    final entity = sceneState.selectedEntity;
    if (entity == null) return;

    final camera = engine.cameraSystem.mainCamera;
    camera.viewportSize = _canvasSize;

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

  void onPointerUp(PointerUpEvent event) => _resetPointerDragState();

  /// A gesture the OS/Flutter interrupts (window loses focus mid-drag, the
  /// gesture arena is stolen by another widget, a second touch cancels the
  /// first) is delivered as [PointerCancelEvent], not [PointerUpEvent] — if
  /// this weren't wired up too, [_activeHandle]/[_isPanningCamera] would get
  /// stuck "on" and silently hijack the next unrelated pointer gesture.
  void onPointerCancel(PointerCancelEvent event) => _resetPointerDragState();

  void _resetPointerDragState() {
    _activeHandle = null;
    _dragStartScreen = null;
    _isPanningCamera = false;
  }

  /// Mouse-wheel zoom, centered on the cursor so the point under it stays
  /// fixed on screen. Same authoring-only gate as [onPointerDown]'s pan.
  void onPointerScroll(PointerSignalEvent event) {
    if (!_isInitialized || !_isVisible || !_isAuthoring) return;
    if (event is! PointerScrollEvent) return;
    if (_canvasSize == Size.zero) return;

    final camera = engine.cameraSystem.mainCamera;
    camera.viewportSize = _canvasSize;

    final worldPoint = camera.screenToWorld(event.localPosition);
    // Scrolling up (negative dy) zooms in.
    final factor = math.exp(-event.scrollDelta.dy * 0.0015);
    camera.zoomToPoint(worldPoint, camera.zoom * factor);
  }

  // ── Scene management helpers ──────────────────────────────────────────────

  /// Generates a `prefix_N` name that doesn't collide with any currently
  /// live entity.
  ///
  /// Using the live entity count as `N` (the old approach) collides as soon
  /// as an entity is deleted and a new one created afterwards — e.g. delete
  /// `entity_1` out of `entity_0`/`entity_1`/`entity_2` and the next create
  /// (count now 2) is named `entity_2`, duplicating the survivor. Duplicate
  /// names silently corrupt [openScene]'s name-keyed parent/child relinking
  /// on the next scene load.
  String _uniqueEntityName(String prefix) {
    final existingNames = engine.world
        .query([TransformComponent])
        .map((e) => e.name)
        .whereType<String>()
        .toSet();
    var index = existingNames.length;
    var candidate = '${prefix}_$index';
    while (existingNames.contains(candidate)) {
      index++;
      candidate = '${prefix}_$index';
    }
    return candidate;
  }

  /// Creates a new entity at the camera centre, adds a visible
  /// [RectangleComponent] so it immediately appears on canvas, selects it,
  /// and registers it in the authoring scene graph.
  void createEntity() {
    if (!sceneState.hasScene) return;

    final camera = engine.cameraSystem.mainCamera;
    final spawnPos = camera.position;

    final entity = engine.world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromOffset(spawnPos)),
    ], name: _uniqueEntityName('entity'));

    sceneState.registerEntity(entity);
    sceneState.selectEntity(entity);
    logService.log(
      'Created entity ${entity.name ?? entity.id}.',
      source: 'editor',
      category: 'entity',
    );
  }

  // ── Entity operations ─────────────────────────────────────────────────────

  /// Destroys [entity] from the ECS world and removes its authoring node.
  void deleteEntity(Entity entity) {
    // Clean up parent link before destroying.
    detachFromParent(entity);
    // Detach all children so they become root entities.
    final children = entity.getComponent<ChildrenComponent>();
    if (children != null) {
      for (final childId in List.of(children.childIds)) {
        final child = engine.world.getEntity(childId);
        if (child != null) detachFromParent(child);
      }
    }
    sceneState.removeEntityNode(entity.id);
    engine.world.destroyEntity(entity);
    logService.log(
      'Deleted entity ${entity.name ?? entity.id}.',
      source: 'editor',
      category: 'entity',
      level: DebuggerLogLevel.warning,
    );
    notifyListeners();
  }

  // ── Group operations ──────────────────────────────────────────────────────

  /// Creates an empty group entity and optionally adds [children] to it.
  ///
  /// When [children] is null and a multi-selection is active, all
  /// multi-selected entities are grouped automatically.
  void createGroup({List<Entity>? children}) {
    if (!sceneState.hasScene) return;

    final camera = engine.cameraSystem.mainCamera;
    final spawnPos = camera.position;

    final groupEntity = engine.world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromOffset(spawnPos)),
      ChildrenComponent(),
    ], name: _uniqueEntityName('group'));

    sceneState.registerEntity(groupEntity);

    final targets =
        children ??
        (sceneState.hasMultiSelection
            ? sceneState.multiSelectedIds
                  .map(engine.world.getEntity)
                  .whereType<Entity>()
                  .toList()
            : null);

    if (targets != null) {
      for (final child in targets) {
        reparentEntity(child, groupEntity);
      }
    }

    sceneState.clearMultiSelection();
    sceneState.selectEntity(groupEntity);
    sceneState.refresh();
    logService.log(
      'Created group ${groupEntity.name ?? groupEntity.id}.',
      source: 'editor',
      category: 'group',
    );
  }

  /// Makes [child] a child of [newParent], auto-computing localOffset.
  void reparentEntity(Entity child, Entity newParent) {
    if (child.id == newParent.id) return;

    // Prevent circular parenting: newParent must not be a descendant of child.
    if (_isDescendantOf(newParent, child)) return;

    // Detach from existing parent first.
    final existing = child.getComponent<ParentComponent>();
    if (existing?.parentId != null) {
      final oldParent = engine.world.getEntity(existing!.parentId!);
      oldParent?.getComponent<ChildrenComponent>()?.removeChild(child.id);
    }

    // Compute localOffset so the child keeps its world position.
    final childT = child.getComponent<TransformComponent>();
    final parentT = newParent.getComponent<TransformComponent>();
    final localOffset = (childT != null && parentT != null)
        ? Vector3.fromXY(
            childT.position.x - parentT.position.x,
            childT.position.y - parentT.position.y,
          )
        : Vector3.zero();

    // Set ParentComponent on child.
    if (existing != null) {
      existing.parentId = newParent.id;
      existing.localOffset = localOffset;
    } else {
      child.addComponent(
        ParentComponent(parentId: newParent.id, localOffset: localOffset),
      );
    }

    // Ensure parent has ChildrenComponent.
    if (!newParent.hasComponent<ChildrenComponent>()) {
      newParent.addComponent(ChildrenComponent());
    }
    newParent.getComponent<ChildrenComponent>()!.addChild(child.id);

    sceneState.markDirty();
    sceneState.refresh();
    logService.log(
      'Reparented ${child.name ?? child.id} under ${newParent.name ?? newParent.id}.',
      source: 'editor',
      category: 'hierarchy',
      mirrorToDebugger: false,
    );
  }

  /// Removes [child] from its parent, making it a root entity.
  void detachFromParent(Entity child) {
    final pc = child.getComponent<ParentComponent>();
    if (pc?.parentId == null) return;

    final parentEntity = engine.world.getEntity(pc!.parentId!);
    parentEntity?.getComponent<ChildrenComponent>()?.removeChild(child.id);

    child.removeComponent<ParentComponent>();

    sceneState.markDirty();
    sceneState.refresh();
    logService.log(
      'Detached ${child.name ?? child.id} from parent.',
      source: 'editor',
      category: 'hierarchy',
      mirrorToDebugger: false,
    );
  }

  bool _isDescendantOf(Entity candidate, Entity ancestor) {
    final pc = candidate.getComponent<ParentComponent>();
    if (pc?.parentId == null) return false;
    if (pc!.parentId == ancestor.id) return true;
    final parent = engine.world.getEntity(pc.parentId!);
    if (parent == null) return false;
    return _isDescendantOf(parent, ancestor);
  }

  /// Copies [entity]'s components to the clipboard as serialised JSON.
  void copyEntity(Entity entity) {
    final components = entity.components
        .map(SceneFileGenerator.componentToJson)
        .whereType<Map<String, dynamic>>()
        .toList();
    sceneState.setClipboard(components);
    logService.log(
      'Copied entity ${entity.name ?? entity.id} to clipboard.',
      source: 'editor',
      category: 'clipboard',
      mirrorToDebugger: false,
    );
  }

  /// Spawns a new entity from the clipboard, offset from the camera centre.
  void pasteEntity() {
    if (!sceneState.hasClipboard) return;

    final components = (sceneState.clipboardJson ?? [])
        .map((j) => SceneFileGenerator.componentFromJson(j))
        .whereType<Component>()
        .toList();

    final pastePosOffset =
        engine.cameraSystem.mainCamera.position + const Offset(30, 30);
    final pastePos = Vector3.fromOffset(pastePosOffset);

    final transform = components.whereType<TransformComponent>().firstOrNull;
    if (transform != null) {
      transform.position.setFrom(pastePos);
    } else {
      components.insert(0, TransformComponent(position: pastePos));
    }

    final entity = engine.world.createEntityWithComponents(
      components,
      name: _uniqueEntityName('entity'),
    );

    sceneState.registerEntity(entity);
    sceneState.selectEntity(entity);
    logService.log(
      'Pasted entity ${entity.name ?? entity.id} from clipboard.',
      source: 'editor',
      category: 'clipboard',
    );
    notifyListeners();
  }

  /// Opens [sceneName]: loads the `.scene.json` sidecar (if present) and
  /// links live ECS entities to their authoring [SceneNode]s.
  ///
  /// If the sidecar contains entity data AND the world currently has no
  /// [TransformComponent] entities, those entities are spawned automatically
  /// so the editor shows the previously saved state on first open.
  ///
  /// File creation is intentionally NOT done here — use [CreateSceneOverlay]
  /// to create new scenes; that overlay writes the stub files before calling
  /// this method.
  Future<void> openScene(String sceneName) async {
    if (_isSceneIOBusy) return;
    _isSceneIOBusy = true;
    try {
      await _openScene(sceneName);
    } finally {
      _isSceneIOBusy = false;
    }
  }

  Future<void> _openScene(String sceneName) async {
    // Destroy any entities left over from a previously open scene.
    for (final e
        in engine.world
            .query([TransformComponent])
            .where((e) => e.isActive)
            .toList()) {
      engine.world.destroyEntity(e);
    }

    final rawJson = await SceneFileGenerator.loadRawSidecar(sceneName);

    final Scene scene = rawJson != null
        ? (Scene.fromJson(rawJson))
        : Scene(name: sceneName);

    if (rawJson != null) {
      final entityList = (rawJson['entities'] as List<dynamic>? ?? []);
      for (final item in entityList) {
        final entityData = item as Map<String, dynamic>;
        final entityName = entityData['name'] as String?;
        final components = (entityData['components'] as List<dynamic>? ?? [])
            .map(
              (c) => SceneFileGenerator.componentFromJson(
                c as Map<String, dynamic>,
              ),
            )
            .whereType<Component>()
            .toList();
        if (components.isNotEmpty) {
          engine.world.createEntityWithComponents(components, name: entityName);
        }
      }

      // Second pass: re-link parent-child relationships by name.
      final nameToEntity = <String?, Entity>{
        for (final e
            in engine.world
                .query([TransformComponent])
                .where((e) => e.isActive))
          e.name: e,
      };
      for (final item in entityList) {
        final entityData = item as Map<String, dynamic>;
        final parentName = entityData['parentName'] as String?;
        if (parentName == null) continue;
        final childEntity = nameToEntity[entityData['name'] as String?];
        final parentEntity = nameToEntity[parentName];
        if (childEntity == null || parentEntity == null) continue;
        childEntity.getComponent<ParentComponent>()?.parentId = parentEntity.id;
        if (!parentEntity.hasComponent<ChildrenComponent>()) {
          parentEntity.addComponent(ChildrenComponent());
        }
        parentEntity.getComponent<ChildrenComponent>()!.addChild(
          childEntity.id,
        );
      }
    }

    final entities = engine.world
        .query([TransformComponent])
        .where((e) => e.isActive)
        .toList();

    final nodeMap = <EntityId, SceneNode>{};
    for (final entity in entities) {
      final transform = entity.getComponent<TransformComponent>()!;
      final nodeName = entity.name ?? 'entity_${entity.id}';
      SceneNode? node = scene.findNode(nodeName);
      if (node == null) {
        node = SceneNode(nodeName)
          ..localPosition = transform.position.toOffset()
          ..localRotation = transform.rotation
          ..localScale = transform.scale.x;
        scene.addNode(node);
      }
      nodeMap[entity.id] = node;
    }

    sceneState.openScene(scene, nodeMap);
    logService.log(
      'Opened scene $sceneName with ${nodeMap.length} linked entities.',
      source: 'editor',
      category: 'scene',
    );
    notifyListeners();
  }

  /// Saves the active scene:
  /// 1. Regenerates `{name}.level.dart` from all live ECS entities.
  /// 2. Writes the `.scene.json` editor sidecar.
  Future<void> saveScene() async {
    if (_isSceneIOBusy) return;
    _isSceneIOBusy = true;
    try {
      await _saveScene();
    } finally {
      _isSceneIOBusy = false;
    }
  }

  Future<void> _saveScene() async {
    final scene = sceneState.activeScene;
    if (scene == null) return;

    final entities = engine.world
        .query([TransformComponent])
        .where((e) => e.isActive)
        .toList();

    await Future.wait([
      SceneFileGenerator.writeLevelFromEntities(scene.name, entities),
      SceneFileGenerator.writeJsonSidecar(scene.name, scene, entities),
    ]);

    sceneState.markClean();
    logService.log(
      'Saved scene ${scene.name} with ${entities.length} active entities.',
      source: 'editor',
      category: 'scene',
    );
  }

  // ── Play / Pause / Stop ────────────────────────────────────────────────────
  //
  // Editor-only play-test: never runs in a release build (this whole plugin
  // is debug-gated), and has no effect on the shipped game's own startNewRun
  // flow — it operates directly on the scene already live in the editor.

  /// Starts (or resumes) simulating the currently open scene.
  ///
  /// The first call in a session (from [EditorPlayState.stopped]) spawns one
  /// entity per [SpawnComponent] found in the world via [spawnRegistry],
  /// tracking what it created so [stop] can clean up precisely — the spawn
  /// point entities themselves are never touched, same as the camera entity.
  /// Calling this again while already playing/paused just resumes time.
  void play() {
    if (!_isInitialized || !engine.isInitialized) return;

    if (_playState == EditorPlayState.stopped) {
      for (final spawnPoint in engine.world.query([SpawnComponent])) {
        final tag = spawnPoint.getComponent<SpawnComponent>()!.tag;
        final spawner = spawnRegistry[tag];
        if (spawner == null) continue;
        final spawned = spawner(engine.world, spawnPoint);
        _spawnedRuntimeEntityIds.add(spawned.id);
      }
      logService.log(
        'Play: spawned ${_spawnedRuntimeEntityIds.length} entities.',
        source: 'editor',
        category: 'play',
      );
    }

    _playState = EditorPlayState.playing;
    engine.time.timeScale = 1.0;
    notifyListeners();
  }

  /// Freezes simulation without destroying anything — [play] resumes
  /// exactly where this left off.
  void pause() {
    if (_playState != EditorPlayState.playing) return;
    _playState = EditorPlayState.paused;
    engine.time.timeScale = 0.0;
    notifyListeners();
  }

  /// Destroys every entity [play] spawned this session and returns to pure
  /// authoring — the next [play] call starts completely fresh.
  void stop() {
    if (_playState == EditorPlayState.stopped) return;

    for (final id in _spawnedRuntimeEntityIds) {
      final entity = engine.world.getEntity(id);
      if (entity != null) engine.world.destroyEntity(entity);
    }
    logService.log(
      'Stop: destroyed ${_spawnedRuntimeEntityIds.length} entities.',
      source: 'editor',
      category: 'play',
    );
    _spawnedRuntimeEntityIds.clear();

    _playState = EditorPlayState.stopped;
    engine.time.timeScale = 0.0;
    notifyListeners();
  }

  // ── Visibility ────────────────────────────────────────────────────────────

  void toggleVisibility() => setVisible(!_isVisible);

  void toggleStatusPanelVisibility() =>
      setStatusPanelVisible(!_isStatusPanelVisible);

  void setStatusPanelVisible(bool visible) {
    final nextVisible = visible;
    if (_isStatusPanelVisible == nextVisible) return;
    if (nextVisible) {
      _attachDebuggerIfReady();
    }
    _isStatusPanelVisible = nextVisible;
    notifyListeners();
  }

  void setVisible(bool visible) {
    final shouldShowStatusPanel = visible && !_isStatusPanelVisible;
    final shouldHideStatusPanel = !visible && _isStatusPanelVisible;
    if (_isVisible == visible &&
        !shouldShowStatusPanel &&
        !shouldHideStatusPanel) {
      return;
    }
    _isVisible = visible;
    if (_isVisible) {
      _isStatusPanelVisible = true;
      _attachDebuggerIfReady();
      if (engine.isInitialized) {
        _preEditorTimeScale = engine.time.timeScale;
        engine.time.timeScale = 0.0;
      }
    } else {
      _isStatusPanelVisible = false;
      // Closing the editor mid-play-test would otherwise leave play-spawned
      // entities and a stale play state behind.
      if (_playState != EditorPlayState.stopped) stop();
      if (engine.isInitialized) {
        engine.time.timeScale = _preEditorTimeScale ?? 1.0;
      }
      _preEditorTimeScale = null;
    }
    if (kDebugMode) {
      debugPrint(
        '[JustGameEditor] editor ${_isVisible ? 'opened' : 'closed'} '
        '(toggle: ${toggleKey.keyLabel.isEmpty ? toggleKey.debugName : toggleKey.keyLabel})',
      );
    }
    logService.log(
      'Editor ${_isVisible ? 'opened' : 'closed'}.',
      source: 'editor',
      category: 'visibility',
      mirrorToDebugger: false,
    );
    _syncFocus();
    notifyListeners();
  }

  void _syncFocus() {
    if (_isVisible) {
      gameFocusScopeNode.unfocus(disposition: UnfocusDisposition.scope);
      if (!editorFocusNode.hasFocus) editorFocusNode.requestFocus();
      return;
    }
    if (editorFocusNode.hasFocus) editorFocusNode.unfocus();
    gameFocusScopeNode.requestFocus();
  }

  @override
  void dispose() {
    try {
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    } catch (_) {
      // The keyboard singleton is unavailable if no binding was initialized.
    }
    logService.stopSession();
    debuggerController.dispose();
    sceneState.dispose();
    editorFocusNode.dispose();
    gameFocusScopeNode.dispose();
    super.dispose();
  }
}
