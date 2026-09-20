import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

import '../../debugger/engine_debugger.dart';
import '../assets/file_sprite_asset_loader.dart';
import '../ecs/systems/editor_log_capture_system.dart';
import '../ecs/systems/physics_body_binding_system.dart';
import '../entity/entity_ops.dart';
import '../input/viewport_input.dart';
import '../play/play_controller.dart';
import '../scene/scene_io.dart';
import '../scope/editor_scope.dart';
import '../serialization/scene_manager.dart';
import '../services/editor_log_service.dart';
import '../state/editor_scene_state.dart';
import '../../ui/overlay/gizmo_painter.dart';
import '../../ui/level_designer/commands/designer_command.dart';
import '../../ui/level_designer/level_designer_session.dart';
import '../../ui/level_designer/tools/tool_registry.dart';
import '../../extension/editor_module.dart';
import '../../ui/overlay/camera_rig_painter.dart';
import '../../ui/level_designer/painters/designer_canvas.dart';
import '../constants/editor_constants.dart';

export '../play/play_controller.dart' show EditorPlayState, EntitySpawner;

/// Debug-only runtime editor plugin scaffold.
class JustGameEditorPlugin implements EnginePlugin {
  // EnginePlugin — the engine's contract, forwarded to the older names the
  // editor's own code and tests still use.
  @override
  String get id => 'editor';

  @override
  Future<void> attach(Engine engine) => onInitialize();

  @override
  void update(double dt) => onUpdate(dt);

  @override
  void renderOverlay(Canvas canvas, Size size) => onRender(canvas, size);

  @override
  void detach() {}

  JustGameEditorPlugin({
    required Engine engine,
    EditorScope? scope,
    List<EditorModule> modules = const [],
    Map<String, Entity Function(World world, Entity spawnPoint)> spawnRegistry =
        const {},
    bool bindPhysicsBodies = true,
    LogicalKeyboardKey toggleKey = LogicalKeyboardKey.f1,
    LogicalKeyboardKey statusPanelToggleKey = LogicalKeyboardKey.f2,
    Set<String> protectedSceneNames = const {},
    bool startVisible = true,
  }) : this._(
         engine: engine,
         scope:
             scope ??
             EditorScope(
               engine: engine,
               modules: [..._staticModules, ...modules],
             ),
         ownsScope: scope == null,
         lateModules: scope == null ? const [] : modules,
         spawnRegistry: spawnRegistry,
         bindPhysicsBodies: bindPhysicsBodies,
         toggleKey: toggleKey,
         statusPanelToggleKey: statusPanelToggleKey,
         protectedSceneNames: protectedSceneNames,
         startVisible: startVisible,
       );

  JustGameEditorPlugin._({
    required this.engine,
    required this.scope,
    required bool ownsScope,
    required List<EditorModule> lateModules,
    required this.spawnRegistry,
    required this.bindPhysicsBodies,
    required LogicalKeyboardKey toggleKey,
    required LogicalKeyboardKey statusPanelToggleKey,
    required Set<String> protectedSceneNames,
    required bool startVisible,
  }) : _ownsScope = ownsScope,
       _toggleKey = toggleKey,
       _startVisible = startVisible,
       _statusPanelToggleKey = statusPanelToggleKey,
       debuggerController = engine.createDebuggerController(
         overlayVisible: false,
         attachImmediately: false,
       ),
       sceneManager = SceneManager(
         store: scope.scenes,
         protectedSceneNames: protectedSceneNames,
       ),
       _gizmoPainter = GizmoPainter() {
    // Modules handed to the plugin alongside a scope someone else built join
    // that scope; a scope the plugin built already has them.
    if (lateModules.isNotEmpty) {
      scope.modules.registerAll(lateModules);
      scope.reload();
    }
  }

  final Engine engine;

  /// Everything this editor owns: registries, codec, scene files, log and
  /// scene state. Shared with the overlay and the designer.
  final EditorScope scope;

  /// Whether [dispose] disposes [scope]: true unless one was passed in.
  final bool _ownsScope;

  /// Scene lifecycle operations (list/delete/rename/duplicate) for the
  /// scene picker.
  final SceneManager sceneManager;

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

  // ── Static registration (compatibility) ───────────────────────────────────
  //
  // Process-wide, which is exactly what EditorScope exists to avoid. It
  // survives so a 0.1.0 app keeps working: the constructor folds it into the
  // scope it builds. Prefer `modules:` on the constructor.

  static final List<EditorModule> _staticModules = [];

  /// Registers [module] for every plugin created after this call.
  @Deprecated('Pass modules: [...] to JustGameEditorPlugin or EditorScope')
  static void registerExtension(EditorModule module) {
    _staticModules.removeWhere((m) => m.id == module.id);
    _staticModules.add(module);
  }

  /// Removes a module registered with [registerExtension].
  @Deprecated('Pass modules: [...] to JustGameEditorPlugin or EditorScope')
  static void unregisterExtension(String id) =>
      _staticModules.removeWhere((m) => m.id == id);

  final LogicalKeyboardKey _toggleKey;
  final LogicalKeyboardKey _statusPanelToggleKey;
  final JustDebuggerController debuggerController;

  /// Shared scene state — read by overlay widgets and gizmo logic.
  EditorSceneState get sceneState => scope.sceneState;

  /// The editor log.
  EditorLogService get logService => scope.log;

  final GizmoPainter _gizmoPainter;

  bool _isInitialized = false;

  /// Whether the editor is open. The overlay follows it.
  final Signal<bool> isVisible = Signal(false, debugLabel: 'editorVisible');

  /// Whether the editor opens itself, with its status panel, once
  /// initialized — see [register].
  final bool _startVisible;

  /// Whether the compact status dock is shown; it can be on its own
  /// while the editor is closed.
  final Signal<bool> isStatusPanelVisible = Signal(
    false,
    debugLabel: 'statusPanelVisible',
  );
  bool _isDebuggerAttached = false;

  /// Whether the authoring grid is wanted; [isGridVisible] is whether it
  /// is drawn right now.
  final Signal<bool> showGrid = Signal(true, debugLabel: 'showGrid');
  bool _gridSnappingEnabled = true;

  /// Whether a small view through the game's live camera is drawn over
  /// the editor while authoring.
  final Signal<bool> showGamePreview = Signal(true, debugLabel: 'gamePreview');

  /// The authoring grid size, in world units.
  final Signal<double> gridSize = Signal(32.0, debugLabel: 'gridSize');

  /// [engine.time.timeScale] captured when the editor is opened, restored
  /// when it's closed again.
  double? _preEditorTimeScale;

  EditorPlayState get playState => playController.state.value;

  /// True whenever the editor should behave as "authoring" (camera-entity
  /// sync, transform→physics-body pushes, and the Timeline preview's
  /// timeScale bump all pause/suppress) rather than "simulating" — i.e. the
  /// editor is open and no play-test is in progress.
  late final Computed<bool> isAuthoring = Computed(
    () => isVisible.value && !playController.isRunning,
    debugLabel: 'isAuthoring',
  );

  // ── Services ──────────────────────────────────────────────────────────────
  //
  // Each owns one concern and takes only what it needs. The plugin is what
  // ties them to the editor's visibility, the designer session and the
  // overlay; panels take the service they need rather than the plugin.

  /// The play-test: Play, Pause, Stop, and the authored snapshot a save
  /// during play writes.
  late final PlayController playController = PlayController(
    engine: engine,
    scope: scope,
    spawnRegistry: spawnRegistry,
  );

  /// Opens and saves scenes through the scope's store.
  late final SceneIO sceneIO = SceneIO(
    scope: scope,
    world: () => engine.world,
    sceneState: sceneState,
  );

  /// Create, delete, group, re-parent and clipboard operations.
  late final EntityOps entities = EntityOps(
    scope: scope,
    world: () => engine.world,
    sceneState: sceneState,
    camera: () => engine.cameraSystem.mainCamera,
    onChanged: sceneState.refresh,
  );

  /// Pointer handling for the game canvas: gizmos, pan, zoom, designer tools.
  late final ViewportInput viewport = ViewportInput(
    world: () => engine.world,
    sceneState: sceneState,
    camera: () => engine.cameraSystem.mainCamera,
    designer: () => designer.value,
    gridSize: () => gridSize.value,
    isActive: () => _isInitialized && isVisible.value,
    isAuthoring: () => isAuthoring.value,
  );

  // ── Focus nodes ───────────────────────────────────────────────────────────

  final FocusScopeNode gameFocusScopeNode = FocusScopeNode(
    debugLabel: 'just-game-editor-game-scope',
  );
  final FocusNode editorFocusNode = FocusNode(
    debugLabel: 'just-game-editor-overlay-focus',
  );

  bool get isInitialized => _isInitialized;
  LogicalKeyboardKey get toggleKey => _toggleKey;
  LogicalKeyboardKey get statusPanelToggleKey => _statusPanelToggleKey;

  /// Factory for debug-only plugin registration.
  static Future<JustGameEditorPlugin?> register({
    required Engine engine,
    EditorScope? scope,
    List<EditorModule> modules = const [],
    Map<String, Entity Function(World world, Entity spawnPoint)> spawnRegistry =
        const {},
    bool bindPhysicsBodies = true,
    LogicalKeyboardKey toggleKey = LogicalKeyboardKey.f1,
    LogicalKeyboardKey statusPanelToggleKey = LogicalKeyboardKey.f2,
    Set<String> protectedSceneNames = const {},
    bool startVisible = true,
  }) async {
    if (!kDebugMode) return null;

    final plugin = JustGameEditorPlugin(
      engine: engine,
      scope: scope,
      modules: modules,
      spawnRegistry: spawnRegistry,
      bindPhysicsBodies: bindPhysicsBodies,
      toggleKey: toggleKey,
      statusPanelToggleKey: statusPanelToggleKey,
      protectedSceneNames: protectedSceneNames,
      startVisible: startVisible,
    );
    await plugin.onInitialize();
    return plugin;
  }

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
            isAuthoringActive: () => isAuthoring.value,
            isDraggingActive: () => viewport.isDragging,
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
    // Sprites are shown and played by the engine's own systems, as in the
    // game — but read from the project's files, so a sheet saved a moment
    // ago shows without a rebuild.
    _previousSpriteLoader = SpriteAssets.loader;
    SpriteAssets.loader = spriteAssets;
    AnimatorAssets.loader = spriteAssets.loadGraph;
    registerSpriteSystems(engine.world);
    // While authoring, the output camera is the editor's view: the brain
    // keeps thinking but does not write to it. Play hands it over.
    isAuthoring.addListener(_syncCameraOwnership);
    _syncCameraOwnership();
    playController.state.addListener(_focusGameOnPlay);
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
    // Launching the editor entry point is asking for the editor: open it and
    // its status panel straight away rather than waiting for F1.
    if (_startVisible) setVisible(true);
  }

  /// Rebuilds every registry from scratch — built-ins, then modules — so
  /// nothing from a previous build survives.
  void _runComponentRegistrar() {
    scope.reload();
    designer.value?.reloadModules();
    logService.log(
      'Custom component registries reloaded.',
      source: 'editor',
      category: 'components',
      mirrorToDebugger: false,
    );
  }

  /// Called by [State.reassemble] on hot-reload to pick up edited
  /// definitions and modules without restarting the app.
  void reassemble() => _runComponentRegistrar();

  void _attachDebuggerIfReady() {
    if (_isDebuggerAttached || !engine.isInitialized) return;
    engine.attachDebugger(debuggerController);
    _isDebuggerAttached = true;
  }

  // ── Level Designer ────────────────────────────────────────────────────────

  /// The Level Designer session, created lazily the first time the designer is
  /// opened on a scene.
  ///
  /// Null until then, so a session that is never used costs nothing — and,
  /// more importantly, so the base editor's behaviour is completely unchanged
  /// for anyone who does not open the designer.
  final Signal<LevelDesignerSession?> designer = Signal(
    null,
    debugLabel: 'designer',
  );

  /// Changes the grid size from the Level Designer.
  ///
  /// Writes through to [sceneState] as well as the plugin's own copy, so the
  /// designer's control and the overlay settings dialog never disagree about
  /// what the grid is.
  void setGridSize(double size) {
    if (size <= 0 || size == gridSize.value) return;
    gridSize.value = size;
    sceneState.setGridSnapping(enabled: _gridSnappingEnabled, gridSize: size);
  }

  /// Whether the authoring grid should be drawn right now.
  ///
  /// The grid is an authoring aid, so it is hidden for the duration of a
  /// play-test — it covers the whole viewport, and judging how a jump reads or
  /// whether a gap is fair is exactly the thing a lattice of lines over
  /// everything gets in the way of. It comes back on Stop.
  ///
  /// Paused counts as playing: you are still in a play session, just a frozen
  /// one, and having the grid blink in and out on every pause would be worse
  /// than either state alone.
  late final Computed<bool> isGridVisible = Computed(
    () => showGrid.value && isAuthoring.value,
    debugLabel: 'gridVisible',
  );

  /// Whether the Level Designer workspace is currently open.
  bool get isLevelDesignerOpen => designer.value != null;

  /// Opens the Level Designer, creating its session if needed.
  void openLevelDesigner() {
    if (designer.value != null || !sceneState.hasScene) return;
    designer.value = LevelDesignerSession(
      scope: scope,
      uniqueName: entities.uniqueName.call,
      camera: () => engine.cameraSystem.mainCamera,
      onDuplicate: duplicateSelection,
      onDelete: deleteSelection,
      onArray: (count, step) => arraySelection(count: count, step: step),
    )..restoreEditorData(sceneIO.editorData);
    _updateRenderFilter();
  }

  /// Hides what the designer has hidden — layers, entities, everything
  /// outside an isolated selection — without touching the entities. Only
  /// while authoring: a play-test shows the level as it ships.
  void _updateRenderFilter() {
    final render = engine.world.getSystem<RenderSystem>();
    if (render == null) return;
    final session = designer.value;
    render.shouldRender = session == null
        ? null
        : (entity) =>
              !isAuthoring.value ||
              session.controller.isShownInViewport(entity);
  }

  /// Closes the Level Designer and releases its state.
  ///
  /// History is dropped rather than retained: its commands hold references to
  /// entities in this scene, and replaying one after a scene change would
  /// write into destroyed entities.
  void closeLevelDesigner() {
    final session = designer.value;
    if (session == null) return;
    sceneIO.editorData = session.editorData();
    designer.value = null;
    _updateRenderFilter();
    session.dispose();
  }

  /// Toggles the Level Designer workspace.
  void toggleLevelDesigner() =>
      isLevelDesignerOpen ? closeLevelDesigner() : openLevelDesigner();

  bool _onHardwareKey(KeyEvent event) {
    if (!_isInitialized) return false;
    // Holding a key keeps nudging; nothing else acts on a repeat.
    if (event is KeyRepeatEvent) {
      return scope.activeWorkspace.value == null &&
          isAuthoring.value &&
          !_isTypingInTextField &&
          (designer.value?.handleKey(
                event.logicalKey,
                gridSize: gridSize.value,
                isRepeat: true,
              ) ??
              false);
    }
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;

    if (key == _toggleKey) {
      toggleVisibility();
      return true;
    }
    if (key == _statusPanelToggleKey) {
      toggleStatusPanelVisibility();
      return true;
    }
    if (!isVisible.value) return false;
    // A workspace has the screen: every other key is its own — Ctrl+S saves
    // its file, not the scene; B is its brush, not the level's.
    if (scope.activeWorkspace.value != null) return false;

    final context = CommandContext(
      scope: scope,
      session: designer.value,
      plugin: this,
      modifiers: ModifierKeys.fromHardwareKeyboard(),
      gridSize: gridSize.value,
    );
    final commands = scope.commands;
    // Save works even from inside a text field.
    if (commands.dispatch(key, context, scopes: const {CommandScope.always})) {
      return true;
    }
    // Everything below means something else in a text field: Delete,
    // Ctrl+C, Ctrl+Z, every single-letter tool key. A HardwareKeyboard
    // handler sees keys before the focused widget does.
    if (_isTypingInTextField) return false;
    // Level-building keys, and only while authoring: during Play the keys
    // belong to the game.
    final session = designer.value;
    if (session != null &&
        isAuthoring.value &&
        session.handleKey(key, gridSize: gridSize.value)) {
      return true;
    }
    return commands.dispatch(key, context, scopes: const {CommandScope.editor});
  }

  /// Where sprites are read from while the editor runs: the project's files.
  final FileSpriteAssetLoader spriteAssets = FileSpriteAssetLoader();
  SpriteAssetLoader? _previousSpriteLoader;

  /// A sprite file changed on disk: show the new one. [atlasPath] limits it
  /// to one atlas (and the sheet beside it); without it everything reloads.
  void reloadSprites([String? atlasPath]) {
    if (atlasPath == null) spriteAssets.clear();
    for (final system in engine.world.systems) {
      if (system is SpriteAnimationSystem) system.reload(atlasPath);
      if (system is SpriteLoadSystem) system.reload();
    }
  }

  /// A file a tool wrote changed: whatever in the level shows it, shows the
  /// new version.
  void reloadAsset(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.animator.json')) {
      reloadAnimators(path);
    } else if (lower.endsWith('.json')) {
      reloadSprites(path);
    } else {
      reloadSprites();
    }
  }

  /// An animator graph changed on disk: animators running it start over
  /// with the new one.
  void reloadAnimators([String? graphPath]) {
    for (final system in engine.world.systems) {
      if (system is AnimatorSystem) system.reload(graphPath);
    }
  }

  void _focusGameOnPlay() {
    if (playController.state.value == EditorPlayState.playing) focusGame();
  }

  /// Gives the keyboard to the game.
  ///
  /// The game hears keys only while its own focus node is the primary focus,
  /// and nothing else hands that back: type a value in the inspector, press
  /// Play, and the keys kept going to the text field — the player stood
  /// still until the editor was restarted. Called when a play-test starts or
  /// resumes, and when the viewport is pressed during one (the editor's
  /// viewport absorbs the press the game would otherwise refocus on).
  void focusGame() {
    FocusNode? game;
    for (final node in gameFocusScopeNode.descendants) {
      final context = node.context;
      if (context == null || node.onKeyEvent == null) continue;
      if (context.findAncestorWidgetOfExactType<GameWidget>() != null) {
        game = node;
        break;
      }
    }
    if (game == null) {
      // No game view to find: at least stop a text field eating the keys.
      if (_isTypingInTextField) FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    if (!game.hasPrimaryFocus) game.requestFocus();
  }

  /// Whether a text field has keyboard focus.
  static bool get _isTypingInTextField {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void onUpdate(double dt) {
    scope.modules.notifyUpdate(dt);
    _attachDebuggerIfReady();
    // After the frame's game update: play time, and the end of a stepped frame.
    if (_isInitialized) playController.tick(dt);
    if (!_isInitialized || !isVisible.value) return;
    _syncTimeScaleForPreview();
    // The game is frozen while authoring, so the brain is asked directly:
    // every camera snaps to what it would frame, which is what the camera
    // gizmos and the game preview draw.
    if (isAuthoring.value &&
        engine.isInitialized &&
        engine.cameraSystem.isInitialized) {
      engine.cameraSystem.brain.evaluate(engine.world, 0, snap: true);
    }
  }

  /// The editor's view, kept across a play-test so Stop returns to exactly
  /// where the author was looking.
  CameraState? _editorView;

  /// Decides who writes the output camera. Authoring: the editor — its pan,
  /// zoom and bookmarks — while the brain only thinks. Otherwise the brain.
  void _syncCameraOwnership() {
    if (!engine.isInitialized || !engine.cameraSystem.isInitialized) return;
    final brain = engine.cameraSystem.brain;
    final authoring = isAuthoring.value;
    if (authoring == !brain.driveOutput) return;
    final camera = engine.cameraSystem.mainCamera;
    if (authoring) {
      brain.driveOutput = false;
      if (_editorView case final view?) camera.apply(view);
    } else {
      // Leaving for a play-test remembers the view; closing the editor
      // forgets it, so reopening starts from what the game shows.
      _editorView = isVisible.value ? camera.state : null;
      brain.driveOutput = true;
    }
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
    if (playController.isRunning) return;
    final entity = sceneState.selectedEntity.value;
    final isPreviewPlaying =
        entity != null &&
        ((entity.getComponent<SpriteAnimationComponent>()?.isPlaying ??
                false) ||
            (entity.getComponent<AnimationControllerComponent>()?.isPlaying ??
                false));
    engine.time.timeScale = isPreviewPlaying ? 1.0 : 0.0;
  }

  /// Called by [GameEditorAdapter] via the [onRenderOverlay] chain,
  /// AFTER [engine.world.render].  Applies the camera transform so gizmos
  /// render in world space on top of all ECS entities.
  ///
  /// [size] is the actual canvas size [RenderingEngine] just rendered with —
  /// used here (rather than the separately-tracked [ViewportInput.canvasSize], which is
  /// only updated via a post-frame callback from pointer-event plumbing and
  /// can drift/lag a frame behind) so gizmo/marker positions always match
  /// where entities were actually drawn.
  void onRender(Canvas canvas, Size size) {
    if (!_isInitialized || !isVisible.value) return;
    if (size == Size.zero) return;

    final camera = engine.cameraSystem.mainCamera;

    if (isGridVisible.value) {
      scope.grid.paintGrid(canvas, camera, size, cellSize: gridSize.value);
    }

    // Between the grid and the gizmos: level overlays sit above the grid so
    // they read as part of the level, and below the gizmo handles so those
    // stay visible and grabbable on top of everything.
    designer.value?.paint(canvas, size, camera);

    // The designer draws the camera rigs as one of its overlays; with it
    // closed the base editor draws them itself.
    if (designer.value == null && isAuthoring.value) {
      CameraRigPainter.paint(
        DesignerCanvas(canvas: canvas, size: size, camera: camera),
        engine.world,
        brain: scope.cameraBrain,
        isSelected: (entity) =>
            sceneState.selectedEntity.value?.id == entity.id ||
            sceneState.isInMultiSelection(entity.id),
      );
    }

    _gizmoPainter.paintCameraMarkers(
      canvas,
      engine.world.query([TransformComponent, VirtualCameraComponent]),
      camera,
      size,
    );

    _gizmoPainter.paintSpawnMarkers(
      canvas,
      engine.world.query([TransformComponent, SpawnComponent]),
      camera,
      size,
    );

    _paintGamePreview(canvas, size, camera);

    final selected = sceneState.selectedEntity.value;
    if (selected == null || !selected.isActive) return;
    // The designer's select tool draws its own resize and rotate handles, and
    // claims every press — the base gizmo would be a second set of handles
    // that cannot be grabbed.
    if (designer.value?.controller.toolId.value == BuiltInTools.select &&
        isAuthoring.value) {
      return;
    }
    _gizmoPainter.paintGizmos(canvas, selected, camera, size);
  }

  /// The preview's top-left corner on the canvas. The chrome publishes it on
  /// every layout, so the preview hangs directly below the play controls
  /// wherever they are.
  Offset gamePreviewOrigin = const Offset(16, 56);

  /// How the preview's panel is drawn. The chrome publishes it with the
  /// origin, from the same settings the play toolbar is drawn with, so the
  /// two read as one piece of UI.
  GamePreviewStyle gamePreviewStyle = const GamePreviewStyle();

  /// Height of the preview panel's header row: the LIVE chip and camera name.
  static const double gamePreviewHeaderHeight = 22;

  /// The whole preview **panel** on a canvas of [canvasSize], with its corner
  /// at [origin]: a fraction of the canvas wide, and as tall as its header
  /// plus a game view of the game's own aspect.
  static Rect gamePreviewRect(
    Size canvasSize, {
    Offset origin = const Offset(16, 56),
    GamePreviewStyle style = const GamePreviewStyle(),
  }) {
    final width = (canvasSize.width * 0.24).clamp(180.0, 420.0);
    final viewWidth = width - style.padding * 2;
    return Rect.fromLTWH(
      origin.dx,
      origin.dy,
      width,
      style.padding * 2 +
          gamePreviewHeaderHeight +
          viewWidth * canvasSize.height / canvasSize.width,
    );
  }

  /// The game view inside [panel]: below the header, inset by the padding.
  static Rect gamePreviewViewRect(
    Rect panel, {
    GamePreviewStyle style = const GamePreviewStyle(),
  }) => Rect.fromLTRB(
    panel.left + style.padding,
    panel.top + style.padding + gamePreviewHeaderHeight,
    panel.right - style.padding,
    panel.bottom - style.padding,
  );

  /// A small view through the game's live camera, in a panel that matches
  /// the play toolbar it hangs below.
  ///
  /// The world is rendered a second time with the output camera briefly
  /// showing what the brain wants, then handed back exactly as it was — so
  /// the author sees the shot they are composing without leaving the view
  /// they are composing it from.
  void _paintGamePreview(Canvas canvas, Size size, Camera camera) {
    if (!showGamePreview.value || !isAuthoring.value) return;
    final brain = scope.cameraBrain;
    final shot = brain?.liveState;
    final live = brain?.liveCamera;
    if (brain == null || shot == null || live == null) return;

    final style = gamePreviewStyle;
    final panel = gamePreviewRect(
      size,
      origin: gamePreviewOrigin,
      style: style,
    );
    final frame = RRect.fromRectAndRadius(
      panel,
      Radius.circular(style.cornerRadius),
    );
    // The toolbar's frame: same fill, same border, same corners.
    canvas
      ..drawRRect(frame, Paint()..color = EditorTheme.statusBadgeBg)
      ..drawRRect(
        frame.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = style.borderColor,
      );

    final viewRect = gamePreviewViewRect(panel, style: style);
    final viewFrame = RRect.fromRectAndRadius(
      viewRect,
      Radius.circular((style.cornerRadius - style.padding).clamp(2.0, 12.0)),
    );
    final view = camera.state;
    canvas
      ..save()
      ..clipRRect(viewFrame)
      ..drawRect(viewRect, Paint()..color = const Color(0xFF0E1216))
      ..translate(viewRect.left, viewRect.top)
      ..scale(viewRect.width / size.width);
    camera.apply(shot);
    try {
      engine.world.render(canvas, size);
    } finally {
      camera
        ..apply(view)
        ..viewportSize = size;
      canvas.restore();
    }
    canvas.drawRRect(
      viewFrame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = EditorTheme.border,
    );

    _paintGamePreviewHeader(
      canvas,
      Rect.fromLTWH(
        viewRect.left,
        panel.top + style.padding,
        viewRect.width,
        gamePreviewHeaderHeight,
      ),
      name: live.name ?? 'camera',
      isSolo: brain.soloEntity == live.id,
      isBlending: brain.activeBlend != null,
    );
  }

  /// `● LIVE  MainCamera` — the toolbar's status chip, then the camera.
  void _paintGamePreviewHeader(
    Canvas canvas,
    Rect row, {
    required String name,
    required bool isSolo,
    required bool isBlending,
  }) {
    const accent = CameraRigPainter.live;
    TextPainter text(String value, TextStyle style, double maxWidth) =>
        TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: maxWidth < 0 ? 0 : maxWidth);

    final state = text(
      isSolo ? 'SOLO' : 'LIVE',
      const TextStyle(
        color: accent,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
      row.width,
    );
    // The chip: a pill with a dot, as on the toolbar while playing.
    final chip = Rect.fromLTWH(
      row.left,
      row.top + (row.height - 16) / 2 - 2,
      7 + 6 + 5 + state.width + 7,
      16,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(chip, const Radius.circular(10)),
        Paint()..color = accent.withValues(alpha: 0.14),
      )
      ..drawCircle(
        Offset(chip.left + 10, chip.center.dy),
        3,
        Paint()..color = accent,
      );
    state.paint(
      canvas,
      Offset(chip.left + 18, chip.center.dy - state.height / 2),
    );

    final blending = isBlending
        ? text(
            'blending',
            const TextStyle(
              color: EditorTheme.textMuted,
              fontSize: 9,
              fontStyle: FontStyle.italic,
            ),
            row.width,
          )
        : null;
    final label = text(
      name,
      const TextStyle(
        color: EditorTheme.textBright,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
      row.right - chip.right - 8 - (blending == null ? 0 : blending.width + 8),
    );
    label.paint(
      canvas,
      Offset(chip.right + 8, chip.center.dy - label.height / 2),
    );
    blending?.paint(
      canvas,
      Offset(row.right - blending.width, chip.center.dy - blending.height / 2),
    );
  }

  void applyOverlaySettings({
    required bool showGrid,
    required bool gridSnappingEnabled,
    required double gridSize,
  }) {
    final nextGridSize = gridSize <= 0 ? 32.0 : gridSize;
    this.showGrid.value = showGrid;
    _gridSnappingEnabled = gridSnappingEnabled;
    this.gridSize.value = nextGridSize;
    sceneState.setGridSnapping(
      enabled: _gridSnappingEnabled,
      gridSize: nextGridSize,
    );
  }

  // ── Level Designer selection operations ───────────────────────────────────
  //
  // Thin on purpose: the designer session calls these, and each needs the
  // session's own history to be one undo step.

  /// Entities covered by the current selection.
  List<Entity> get selectionEntities => entities.selectionEntities;

  /// Deletes everything selected, as one undoable action.
  void deleteSelection() {
    final history = designer.value?.history;
    if (history != null) entities.deleteSelection(history);
  }

  /// Duplicates everything selected, offset by one grid cell so the copies
  /// are visible rather than hidden exactly behind the originals.
  void duplicateSelection() {
    final history = designer.value?.history;
    if (history != null) {
      entities.duplicateSelection(history, gridSize: gridSize.value);
    }
  }

  /// Repeats the selection [count] times, each copy [step] further along.
  void arraySelection({required int count, required Offset step}) {
    final history = designer.value?.history;
    if (history != null) {
      entities.arraySelection(history, count: count, step: step);
    }
  }

  /// Opens [sceneName] through [sceneIO], closing the Level Designer first:
  /// its undo commands hold entities of the scene being left, and it reopens
  /// cleanly on the new one.
  Future<void> openScene(String sceneName) async {
    if (sceneIO.isBusy) return;
    final wasDesignerOpen = isLevelDesignerOpen;
    closeLevelDesigner();
    if (!await sceneIO.open(sceneName)) return;
    if (wasDesignerOpen) openLevelDesigner();
  }

  /// Saves the active scene. During a play-test the level is saved as it was
  /// authored, not as the simulation has left it.
  Future<void> saveScene() => sceneIO.save(
    asAuthored: playController.snapshot?.entities,
    editorData: designer.value?.editorData() ?? sceneIO.editorData,
  );

  // ── Play / Pause / Stop ────────────────────────────────────────────────────

  /// Starts or resumes the play-test; see [PlayController.play].
  void play() {
    if (_isInitialized) playController.play();
  }

  /// Freezes the play-test; see [PlayController.pause].
  void pause() => playController.pause();

  /// Ends the play-test and restores the authored scene; see
  /// [PlayController.stop].
  void stop() => playController.stop();

  // ── Visibility ────────────────────────────────────────────────────────────

  void toggleVisibility() => setVisible(!isVisible.value);

  void toggleStatusPanelVisibility() =>
      setStatusPanelVisible(!isStatusPanelVisible.value);

  void setStatusPanelVisible(bool visible) {
    final nextVisible = visible;
    if (isStatusPanelVisible.value == nextVisible) return;
    if (nextVisible) {
      _attachDebuggerIfReady();
    }
    isStatusPanelVisible.value = nextVisible;
  }

  void setVisible(bool visible) {
    final shouldShowStatusPanel = visible && !isStatusPanelVisible.value;
    final shouldHideStatusPanel = !visible && isStatusPanelVisible.value;
    if (isVisible.value == visible &&
        !shouldShowStatusPanel &&
        !shouldHideStatusPanel) {
      return;
    }
    isVisible.value = visible;
    if (isVisible.value) {
      isStatusPanelVisible.value = true;
      _attachDebuggerIfReady();
      if (engine.isInitialized) {
        _preEditorTimeScale = engine.time.timeScale;
        engine.time.timeScale = 0.0;
      }
    } else {
      isStatusPanelVisible.value = false;
      // Closing the editor mid-play-test would otherwise leave play-spawned
      // entities and a stale play state behind.
      if (playController.isRunning) stop();
      if (engine.isInitialized) {
        engine.time.timeScale = _preEditorTimeScale ?? 1.0;
      }
      _preEditorTimeScale = null;
    }
    if (kDebugMode) {
      debugPrint(
        '[JustGameEditor] editor ${isVisible.value ? 'opened' : 'closed'} '
        '(toggle: ${toggleKey.keyLabel.isEmpty ? toggleKey.debugName : toggleKey.keyLabel})',
      );
    }
    logService.log(
      'Editor ${isVisible.value ? 'opened' : 'closed'}.',
      source: 'editor',
      category: 'visibility',
      mirrorToDebugger: false,
    );
    _syncFocus();
  }

  void _syncFocus() {
    if (isVisible.value) {
      gameFocusScopeNode.unfocus(disposition: UnfocusDisposition.scope);
      if (!editorFocusNode.hasFocus) editorFocusNode.requestFocus();
      return;
    }
    if (editorFocusNode.hasFocus) editorFocusNode.unfocus();
    gameFocusScopeNode.requestFocus();
  }

  void dispose() {
    closeLevelDesigner();
    isAuthoring.removeListener(_syncCameraOwnership);
    playController.state.removeListener(_focusGameOnPlay);
    if (identical(SpriteAssets.loader, spriteAssets)) {
      SpriteAssets.loader = _previousSpriteLoader ?? BundleSpriteAssetLoader();
      AnimatorAssets.useBundle();
    }
    if (engine.isInitialized && engine.cameraSystem.isInitialized) {
      engine.cameraSystem.brain.driveOutput = true;
    }
    try {
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    } catch (_) {
      // The keyboard singleton is unavailable if no binding was initialized.
    }
    logService.stopSession();
    playController.dispose();
    debuggerController.dispose();
    if (_ownsScope) scope.dispose();
    editorFocusNode.dispose();
    gameFocusScopeNode.dispose();
    isGridVisible.dispose();
    isAuthoring.dispose();
    for (final signal in [
      isVisible,
      isStatusPanelVisible,
      showGrid,
      gridSize,
    ]) {
      signal.dispose();
    }
    designer.dispose();
  }
}

/// The frame of the game camera preview: what makes it the same kind of panel
/// as the play toolbar above it.
class GamePreviewStyle {
  const GamePreviewStyle({
    this.cornerRadius = 12,
    this.borderColor = const Color(0xFFF5736F),
    this.padding = 5,
  });

  /// Corner radius of the panel — the toolbar's.
  final double cornerRadius;

  /// Border colour — the overlay's theme colour, as on the toolbar.
  final Color borderColor;

  /// Space between the panel's edge and what is in it.
  final double padding;
}
