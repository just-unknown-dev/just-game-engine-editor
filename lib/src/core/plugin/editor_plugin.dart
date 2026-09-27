import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

import '../../debugger/engine_debugger.dart';
import '../../ui/level_designer/state/editor_commands.dart';
import '../assets/file_sprite_asset_loader.dart';
import '../../ui/level_designer/state/map_placement.dart';
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
import '../state/play_snapshot.dart';
import '../../ui/overlay/gizmo_painter.dart';
import '../../ui/level_designer/commands/designer_command.dart';
import '../../ui/level_designer/level_designer_session.dart';
import '../level_map/tiled_import.dart';
import '../../extension/built_in_tile_contributions.dart';
import '../level_map/level_map_documents.dart';
import '../level_map/level_map_focus.dart';
import '../level_map/level_map_provision.dart';
import '../level_map/tile_commands.dart';
import '../../ui/level_designer/state/editor_history.dart';
import '../../ui/level_designer/ui_mode/ui_mode_session.dart';
import '../../ui/level_designer/ui_mode/ui_workspace.dart';
import '../../ui/level_designer/tools/level_tool.dart';
import '../../ui/level_designer/tools/tiles/tile_tool_base.dart';
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

  /// Whether the status bar is shown. It comes and goes with the editor
  /// (F1); F2 opens and shuts the dock panel above it.
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

  /// Create, delete, group, re-parent and clipboard operations — the
  /// scope's, shared with the windows that open over the editor.
  EntityOps get entities => scope.entities;

  /// Pointer handling for the game canvas: gizmos, pan, zoom, designer tools.
  late final ViewportInput viewport = ViewportInput(
    world: () => engine.world,
    sceneState: sceneState,
    camera: () => engine.cameraSystem.mainCamera,
    designer: () => designer.value,
    gridSize: () => gridSize.value,
    isActive: () => _isInitialized && isVisible.value,
    isAuthoring: () => isAuthoring.value,
    // Locked in the tree, or hidden: neither can be picked in the
    // viewport, which is what the padlock is for.
    // Nor can anything the Level Designer has put out of reach.
    isPickable: (entity) =>
        !scope.view.isLocked(entity.id) &&
        !scope.view.isHidden(entity.id) &&
        !PlaySnapshot.isGenerated(entity) &&
        sceneState.canSelect(entity),
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
    TimelineAssets.loader = spriteAssets.loadTimeline;
    UiThemes.loader = spriteAssets.loadUiTheme;
    UiFonts.read = spriteAssets.loadFontData;
    TileAssets.readText = spriteAssets.readText;
    // Tile maps draw in the editor as in the game; their collision is built
    // only in a play-test (see _syncRuntimeSystems).
    registerLevelMapSystems(engine.world);
    // The fonts in the project, so the text-style editor can offer them by
    // name from the first inspector that opens.
    unawaited(reloadFonts());
    registerSpriteSystems(engine.world);
    // While authoring, the output camera is the editor's view: the brain
    // keeps thinking but does not write to it. Play hands it over.
    isAuthoring.addListener(_syncCameraOwnership);
    _syncCameraOwnership();
    keepsToLevelMap.addListener(_syncLevelMapFocus);
    _syncLevelMapFocus();
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
    // From the start, not only once a designer has been opened: the eye
    // in the scene tree works whether or not one ever is.
    _updateRenderFilter();
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

  /// The UI mode: the viewport showing the scene's interface, on a device
  /// frame, instead of the world.
  ///
  /// It needs no Level Designer — a HUD is built from the scene tree and
  /// the inspector — so it keeps an undo stack of its own for the drags
  /// made in it.
  UiModeSession get uiMode => scope.uiMode;

  /// Undo for everything the editor does. The scope owns it; this is the
  /// name the rest of the editor reaches it by.
  EditorHistory get history => scope.history;

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

  /// Whether only the Level Map can be worked on: the Level Designer is
  /// open and building, not play-testing, and no workspace — the
  /// interface editor, say, which works on the HUDs — is open over it.
  late final Computed<bool> keepsToLevelMap = Computed(
    () =>
        designer.value != null &&
        isAuthoring.value &&
        scope.activeWorkspace.value == null,
    debugLabel: 'keepsToLevelMap',
  );

  /// Puts everything but the Level Map out of reach while
  /// [keepsToLevelMap], and back when not.
  void _syncLevelMapFocus() => sceneState.setSelectable(
    keepsToLevelMap.value
        ? (entity) => LevelMapFocus.contains(engine.world, entity)
        : null,
  );

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

  /// Hides what the editor has hidden — the eye in the scene tree, and
  /// the designer's layers and isolated selection — without touching the
  /// entities. Only while authoring: a play-test shows the level as it
  /// ships.
  ///
  /// The eye used to work only with the Level Designer open, because
  /// this filter was installed only then; everywhere else the engine
  /// drew the world and knew nothing of it.
  void _updateRenderFilter() {
    final render = engine.world.getSystem<RenderSystem>();
    if (render == null) return;
    render.shouldRender = _isDrawn;
  }

  /// Whether [entity] is drawn in the viewport — its sprite, and the
  /// markers and frames the editor draws for it. Everything is during a
  /// play-test; while authoring, not what the eye hid, nor what the Level
  /// Designer has hidden: its layers, and everything but its Level Map.
  bool _isDrawn(Entity entity) {
    if (!isAuthoring.value) return true;
    if (scope.view.isHidden(entity.id)) return false;
    final session = designer.value;
    return session == null || session.controller.isShownInViewport(entity);
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
    // F2: the dock panel. The status bar itself comes and goes with the
    // editor, so there is nothing else for this key to switch.
    if (key == _statusPanelToggleKey) {
      if (!isVisible.value || scope.activeWorkspace.value != null) return false;
      scope.dockController.togglePanel(fallback: 'logs');
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

  /// The JSON files that are something other than a sprite atlas. Every
  /// other `.json` in a project is taken to be an atlas — the one kind of
  /// JSON that carries no suffix of its own.
  static const List<String> dataJsonSuffixes = [
    '.scene.json',
    '.animator.json',
    '.timeline.json',
    '.uitheme.json',
    '.tileset.json',
    LevelMapFiles.suffix,
    LevelMapFiles.legacySuffix,
    '/scenes.json',
  ];

  /// Whether [path] is a sprite atlas: a `.json` that is none of the
  /// editor's other data files.
  static bool isSpriteAtlasPath(String path) {
    final p = path.toLowerCase().replaceAll('\\', '/');
    if (!p.endsWith('.json') || p == 'scenes.json') return false;
    return !dataJsonSuffixes.any(p.endsWith);
  }

  /// Whether dropping [path] on the viewport makes something: an image, a
  /// sprite project, or a sprite atlas.
  static bool canDropAsset(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.tileset.json') ||
        LevelMapFiles.isMapFile(p) ||
        TiledImporter.isTiledMap(path) ||
        p.endsWith('.png') ||
        p.endsWith('.jpg') ||
        p.endsWith('.jpeg') ||
        p.endsWith('.webp') ||
        p.endsWith('.jsprite') ||
        isSpriteAtlasPath(path);
  }

  /// Makes an entity for the asset at [path], where it was dropped on the
  /// viewport ([canvasPosition], in the canvas's own pixels): a still sprite
  /// for an image, a sprite animation for an atlas or a sprite project (whose
  /// atlas sits beside it). One undo step while the Level Designer is open.
  /// Null when there is no scene, or the file is not something to place.
  Entity? dropAsset(String path, Offset canvasPosition) {
    if (!sceneState.hasScene || !canDropAsset(path)) return null;
    final at = engine.cameraSystem.mainCamera.screenToWorld(canvasPosition);
    final lower = path.toLowerCase();
    // What is dropped sits on the grid, as the Level Designer places it.
    final grid = sceneState.gridSize.value;
    double snap(double v) => grid > 0 ? (v / grid).round() * grid : v;
    final onGrid = Offset(snap(at.dx), snap(at.dy));
    if (lower.endsWith('.tileset.json')) return _dropTileset(path);
    if (LevelMapFiles.isMapFile(lower)) return _dropMapFile(path);
    if (TiledImporter.isTiledMap(path)) {
      unawaited(
        BuiltInTileContributions.importIntoScene(scope, path, at: onGrid),
      );
      return null;
    }
    final dot = path.lastIndexOf('.');
    final stem = path.substring(path.lastIndexOf('/') + 1, dot);
    final isImage = !lower.endsWith('.json') && !lower.endsWith('.jsprite');
    final components = <Component>[
      TransformComponent(position: Vector3(at.dx, at.dy, 0)),
      if (isImage)
        SpriteComponent(spritePath: path, pixelArt: true)
      else
        SpriteAnimationComponent(
          atlasPath: lower.endsWith('.json')
              ? path
              : '${path.substring(0, dot)}.json',
        ),
    ];
    final session = designer.value;
    if (session != null) {
      // Designing a level: what is dropped goes under its map, on a layer
      // at the depth being placed at.
      final placed = MapPlacement.place(
        scope,
        engine.world,
        [(stem, components)],
        depth: session.controller.activeLayerId.value,
        label: 'Place $stem',
        say: (message) => logService.log(message, source: 'assets'),
      );
      if (placed == null || placed.isEmpty) return null;
      logService.log('Placed $stem from $path.', source: 'assets');
      return placed.single;
    }
    final entity = engine.world.createEntityWithComponents(
      components,
      name: stem,
    );
    sceneState
      ..syncEntityNode(entity)
      ..markDirty()
      ..refresh()
      ..selectEntity(entity);
    history.pushApplied(
      CreateEntitiesCommand.adopting(
        label: 'Place $stem',
        world: engine.world,
        sceneState: sceneState,
        entities: [entity],
        codec: scope.codec,
      ),
    );
    logService.log('Placed $stem from $path.', source: 'assets');
    return entity;
  }

  /// Places an entity of [components] — named after [path], as a dropped
  /// sprite is, unless [name] is given — selected, as one undo step.
  Entity _place(String path, List<Component> components, {String? name}) {
    final entity = engine.world.createEntityWithComponents(
      components,
      name: name ?? tiledStem(path),
    );
    sceneState
      ..syncEntityNode(entity)
      ..markDirty()
      ..refresh()
      ..selectEntity(entity);
    history.pushApplied(
      CreateEntitiesCommand.adopting(
        label: 'Place ${entity.name}',
        world: engine.world,
        sceneState: sceneState,
        entities: [entity],
        codec: scope.codec,
      ),
    );
    logService.log('Placed ${entity.name} from $path.', source: 'assets');
    return entity;
  }

  /// A tileset dropped: the map being painted gets it, and the Tileset
  /// panel shows it. With no map yet, the scene's Level Map is made to hold
  /// it, its cells the tileset's size.
  Entity? _dropTileset(String path) {
    final tiles = scope.tiles;
    final provision = scope.mapProvision;
    final tileSize = TileAssets.loadedTileset(path)?.tileWidth;
    final target = provision.ensure(engine.world, tileSize: tileSize);
    if (target == null) {
      logService.log('The Level Map is still loading.', source: 'assets');
      return null;
    }
    if (target.isReadOnly) {
      logService.log(
        '${target.path} is a Tiled map: it cannot take another tileset.',
        source: 'assets',
      );
      return null;
    }
    var slot = target.data.slotOf(path);
    if (provision.isPending) {
      // One undo step: the map, and the tileset in it.
      slot = target.data.addTileset(path);
      provision.keep('Add tileset');
      logService.log(
        'Made the ${LevelMaps.primaryName} to paint ${tiledStem(path)} on.',
        source: 'assets',
      );
    } else if (slot < 0) {
      final command = MapStructureCommand.record(
        label: 'Add tileset',
        docs: scope.mapDocs,
        ref: target.ref,
        change: (map) => slot = map.addTileset(path),
      );
      if (command != null) history.pushApplied(command);
      logService.log(
        'Added ${tiledStem(path)} to ${target.entity.name}.',
        source: 'assets',
      );
    }
    tiles.slot.value = slot;
    return target.entity;
  }

  /// A map file dropped: it becomes the scene's Level Map — made for it, or
  /// the empty one switched to it. A map with something painted on it is
  /// kept, and the file is not used: a scene has one map.
  Entity? _dropMapFile(String path) {
    final existing = LevelMaps.primaryEntity(engine.world);
    if (existing == null) {
      final entity = _place(path, [
        TransformComponent(),
        LevelMapComponent(mapPath: path),
      ], name: LevelMaps.primaryName);
      scope.tiles.selectMap(entity);
      return entity;
    }
    final c = existing.getComponent<LevelMapComponent>()!;
    if (c.usesFile && c.mapPath.trim() == path) {
      scope.tiles.selectMap(existing);
      sceneState.selectEntity(existing);
      return existing;
    }
    final inline = c.usesFile ? null : c.inline;
    if (inline != null && LevelMapProvision.isBlank(inline)) {
      history.pushApplied(
        MapSourceCommand(
          label: 'Use ${tiledStem(path)}',
          docs: scope.mapDocs,
          entityId: existing.id,
          before: (path: '', inline: inline.toJson()),
          after: (path: path, inline: null),
        )..redo(),
      );
      scope.tiles.selectMap(existing);
      sceneState.selectEntity(existing);
      logService.log('${existing.name} is $path now.', source: 'assets');
      return existing;
    }
    logService.log(
      'The scene already has a map, ${existing.name}, with something on it: '
      'a scene has one. $path was not used.',
      level: DebuggerLogLevel.warning,
      source: 'assets',
    );
    return null;
  }

  /// A file a tool wrote changed: whatever in the level shows it, shows the
  /// new version.
  void reloadAsset(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.animator.json')) {
      reloadAnimators(path);
    } else if (lower.endsWith('.timeline.json')) {
      reloadTimelines(path);
    } else if (lower.endsWith('.uitheme.json')) {
      reloadUiThemes(path);
    } else if (lower.endsWith('.tileset.json') ||
        LevelMapFiles.isMapFile(lower) ||
        lower.endsWith('.tmx') ||
        lower.endsWith('.tmj') ||
        lower.endsWith('.tsx') ||
        lower.endsWith('.tsj')) {
      reloadLevelMaps(path);
    } else if (lower.endsWith('.ttf') ||
        lower.endsWith('.otf') ||
        lower.endsWith('.ttc')) {
      reloadFonts(path);
    } else if (isSpriteAtlasPath(path)) {
      reloadSprites(path);
    } else if (lower.endsWith('.json')) {
      // Some other data file: nothing a sprite shows.
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

  /// A tileset or map file changed on disk: every map using it reads it
  /// again. A Tiled `.tsx` could belong to any `.tmx`, so it reloads all.
  void reloadLevelMaps([String? path]) {
    final lower = path?.toLowerCase() ?? '';
    final all =
        path == null || lower.endsWith('.tsx') || lower.endsWith('.tsj');
    // A map file being edited here is the document: re-reading it would
    // throw the edits away. It is written by a save, not read back.
    if (!all && scope.mapDocs.dirtyPaths.value.contains(path)) return;
    for (final system in engine.world.systems) {
      if (system is LevelMapSystem) system.reload(all ? null : path);
    }
    // A tileset's images may have changed with it.
    if (all || lower.endsWith('.tileset.json')) spriteAssets.clear();
  }

  /// A timeline changed on disk: players of it start over with the new one.
  void reloadTimelines([String? timelinePath]) {
    for (final system in engine.world.systems) {
      if (system is TimelineSystem) system.reload(timelinePath);
    }
  }

  /// A UI theme changed on disk: every canvas drawn with it is restyled on
  /// the next frame, without reopening the scene.
  Future<void> reloadUiThemes([String? themePath]) async {
    UiThemes.evict(themePath);
    final paths = <String>{
      ?themePath,
      for (final entity in engine.world.query([UiCanvasComponent]))
        if (entity.getComponent<UiCanvasComponent>()!.theme.isNotEmpty)
          entity.getComponent<UiCanvasComponent>()!.theme,
    };
    for (final path in paths) {
      await UiThemes.load(path);
    }
    for (final entity in engine.world.query([UiCanvasComponent])) {
      entity.getComponent<UiCanvasComponent>()!.markDirty();
    }
  }

  /// A font file appeared or changed: load it so the inspector offers it
  /// and anything using it redraws with it.
  ///
  /// Without a path, everything in `assets/fonts` — which is how a font
  /// dropped into the project becomes available with no rebuild and no
  /// line in pubspec.yaml.
  Future<void> reloadFonts([String? fontPath]) async {
    UiFonts.reset();
    await UiFonts.loadAll(
      fontPath != null ? [fontPath] : spriteAssets.fontFiles(),
    );
  }

  // Systems that must not run on the scene being edited:
  //
  // * A timeline writes to the fields it animates. While authoring those
  //   fields are the scene being edited, so timelines only run in a
  //   play-test (whose changes are thrown away) — the Timeline dock
  //   previews by itself.
  // * Tile collision builds bodies from the maps. While authoring they
  //   would be rebuilt on every stroke for nothing; they are built when
  //   play starts, and destroyed with the play-test.
  //
  // Tile animation runs either way — on the game's clock in a play-test,
  // on the wall clock while authoring, when the game's time stands still.
  void _syncRuntimeSystems(double dt) {
    if (!engine.isInitialized) return;
    final run = !isAuthoring.value;
    for (final system in engine.world.systems) {
      if (system is TimelineSystem) system.isActive = run;
      if (system is MapCollisionSystem && system.isActive != run) {
        system.isActive = run;
        if (!run) system.clearGenerated();
      }
      if (system is LevelMapSystem) {
        system.advanceClock = run;
        if (!run) system.clockMs += dt * 1000;
      }
    }
    scope.mapDocs.pollAssets();
    // Only the layer being painted at full strength, while painting.
    scope.tiles.syncHighlight(
      engine.world,
      active:
          !run &&
          scope.activeWorkspace.value == null &&
          designer.value?.controller.activeTool?.group == ToolGroups.tiles,
    );
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
    if (_isInitialized) _syncRuntimeSystems(dt);
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
        (entity.getComponent<SpriteAnimationComponent>()?.isPlaying ?? false);
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
        isShown: _isDrawn,
      );
    }

    _gizmoPainter.paintCameraMarkers(
      canvas,
      engine.world
          .query([TransformComponent, VirtualCameraComponent])
          .where(_isDrawn)
          .toList(),
      camera,
      size,
    );

    _gizmoPainter.paintSpawnMarkers(
      canvas,
      engine.world
          .query([TransformComponent, SpawnComponent])
          .where(_isDrawn)
          .toList(),
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

  /// Puts the viewport on [entity] — what double-clicking a row in the
  /// scene tree does.
  ///
  /// A piece of interface is nowhere in the world, so for one of those the
  /// interface editor opens instead, where it *is* somewhere. A HUD is
  /// the door to it: a canvas sits in the world and has a transform, but
  /// putting the camera on it would show nothing worth seeing.
  void focusOn(Entity entity) {
    if (entity.hasComponent<LevelMapComponent>()) {
      designLevelMap(entity);
      return;
    }
    if (entity.getComponent<UiCanvasComponent>() != null) {
      scope.openWorkspace(BuiltInWorkspaces.ui);
      sceneState.selectEntity(entity);
      return;
    }
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) {
      if (entity.getComponent<UiSlotComponent>() != null) {
        scope.openWorkspace(BuiltInWorkspaces.ui);
      }
      sceneState.selectEntity(entity);
      return;
    }
    engine.cameraSystem.mainCamera.position = Offset(
      transform.position.x,
      transform.position.y,
    );
    sceneState.selectEntity(entity);
  }

  /// Opens the Level Designer on the map on [entity], ready to paint: the
  /// map selected and painted, the Stamp in hand unless a tile tool already
  /// is, and the view on what is painted — what double-clicking the Level
  /// Map in the scene tree does.
  void designLevelMap(Entity entity) {
    sceneState.selectEntity(entity);
    openLevelDesigner();
    scope.tiles.selectMap(entity);
    final session = designer.value;
    if (session != null && session.controller.activeGroup != ToolGroups.tiles) {
      session.setTool(TileTools.stamp);
    }
    final target = scope.mapDocs.resolve(entity);
    if (target == null) return;
    var centre = target.origin;
    final layer = scope.tiles.peekLayer(target);
    final used = layer?.cells.usedBounds;
    if (layer != null && used != null) {
      final g = target.geometry;
      final a = g.cellCenter(used.left.toInt(), used.top.toInt());
      final b = g.cellCenter(used.right.toInt() - 1, used.bottom.toInt() - 1);
      centre += Offset(layer.offsetX, layer.offsetY) + Offset.lerp(a, b, 0.5)!;
    }
    engine.cameraSystem.mainCamera.position = centre;
  }

  /// Deletes everything selected, as one undoable action.
  void deleteSelection() => entities.deleteSelection(history);

  /// Duplicates everything selected, offset by one grid cell so the copies
  /// are visible rather than hidden exactly behind the originals.
  void duplicateSelection() =>
      entities.duplicateSelection(history, gridSize: gridSize.value);

  /// Repeats the selection [count] times, each copy [step] further along.
  void arraySelection({required int count, required Offset step}) =>
      entities.arraySelection(history, count: count, step: step);

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
  ///
  /// Map files edited alongside it are saved too: one save, one unsaved
  /// mark, for the scene and the maps it uses.
  Future<void> saveScene() async {
    await scope.mapDocs.saveDirty();
    await sceneIO.save(
      asAuthored: playController.snapshot?.entities,
      editorData: designer.value?.editorData() ?? sceneIO.editorData,
    );
  }

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
    keepsToLevelMap.removeListener(_syncLevelMapFocus);
    playController.state.removeListener(_focusGameOnPlay);
    if (identical(SpriteAssets.loader, spriteAssets)) {
      SpriteAssets.loader = _previousSpriteLoader ?? BundleSpriteAssetLoader();
      AnimatorAssets.useBundle();
      TimelineAssets.useBundle();
      TileAssets.useBundle();
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
