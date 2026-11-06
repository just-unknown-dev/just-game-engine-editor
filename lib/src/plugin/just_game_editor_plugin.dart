import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerSignalEvent, kPrimaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_editor_core/io.dart' show FileSystemException, Platform;
import 'package:just_game_engine/just_game_engine.dart';

import 'engine_debugger.dart';
import '../physics/physics_2d/collider_2d_edit_session.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine/just_game_engine_3d.dart' as g3;
import '../physics/physics_3d/collider_3d_overlay.dart';
import '../viewport/selection_pivot.dart';
import '../viewport/translate_3d_snaps.dart';
import '../viewport/split_views.dart';
import '../assets/file_sprite_asset_loader.dart';
import '../level_map/map_placement.dart';
import 'editor_log_capture_system.dart';
import '../physics/physics_2d/physics_2d_body_binding_system.dart';
import '../entities/entity_ops.dart';
import '../physics/physics_bodies.dart';
import 'viewport_input.dart';
import '../play/play_controller.dart';
import 'editor_presence.dart';
import '../scenes/scene_io.dart';
import '../scenes/scene_loading.dart' show AssetTally;
import '../scenes/scene_manager.dart';
import '../play/play_snapshot.dart';
import 'built_in_docks.dart' show BuiltInDocks;
import '../viewport/gizmos/gizmo_3d_painter.dart';
import '../viewport/gizmos/gizmo_2d_painter.dart';
import '../level_designer/level_designer_session.dart';
import '../level_map/tiled/tiled_importer.dart';
import '../level_map/built_in_tile_contributions.dart';
import '../level_map/level_map_documents.dart';
import '../level_map/level_map_focus.dart';
import '../level_map/level_map_provision.dart';
import '../level_map/tile_commands.dart';
import '../level_designer/level_designer_2d/tools/tiles/tile_tool_base.dart';
import 'built_in_editor_module.dart';
import '../graphics/graphics_2d/built_in_lighting_2d_contributions.dart';
import '../asset_store/asset_store.dart';
import '../graphics/graphics_3d/built_in_graphics_3d_module.dart';
import '../materials/built_in_materials_module.dart';
import '../camera/camera_rig_painter.dart';
import '../scenes/recent_scenes.dart';
import '../entities/scope_entities.dart';
import '../docks/scope_docks.dart';
import '../level_map/scope_level_maps.dart';
import '../prefabs/scope_prefabs.dart';
import '../prefabs/prefab_placement.dart';
import 'commands/built_in_commands.dart';
import '../camera/game_preview_style.dart';
import '../problems/problem_scan.dart';
import '../project/flutter_pin_check.dart';

part 'editor_visibility.dart';
part 'editor_debugger_attach.dart';

part 'editor_designer.dart';
part 'editor_key_dispatch.dart';
part 'editor_asset_drops.dart';
part 'editor_asset_reloads.dart';
part 'editor_authoring.dart';
part 'editor_viewport_renderer.dart';
part 'editor_pane_router.dart';
part 'editor_game_preview.dart';
part 'editor_selection_ops.dart';
part 'editor_scene_session.dart';
part 'editor_settings_sync.dart';
part 'editor_reassembly.dart';

/// The level editor, as an engine plugin: it runs inside a debug build of
/// the game, over the running world, and saves the project's scenes on
/// disk.
///
/// A game's editor entry point makes it with [register] — null in a
/// profile or release build, and where the editor cannot run
/// ([supportsPlatform]) — and shows it with `JustGameEngineEditor`, which
/// registers it with the engine. It owns the editor's [scope] (registries,
/// undo [history], scene files, log), the play-test ([play], [pause],
/// [stop]), opening and saving scenes ([openScene], [saveScene]), and
/// whether the editor is shown ([isVisible], [toggleKey]).
///
/// What the editor can do comes from modules: the editor's own
/// ([BuiltInEditorModule], and [BuiltInMaterialsModule] of `materials.dart`)
/// and the game's, passed as `modules:` or later through [syncModules].
class JustGameEditorPlugin implements EnginePlugin {
  // EnginePlugin — the engine's contract.
  @override
  String get id => 'editor';

  /// The engine calls this when the plugin is registered with it: the first
  /// time it initializes the editor; put back after [detach], the editor
  /// takes up again where it left off.
  @override
  Future<void> attach(Engine engine) async {
    if (_isInitialized) {
      _resume();
      return;
    }
    await _initialize();
  }

  @override
  void update(double deltaTime) => _update(deltaTime);

  /// The engine calls this over the world every frame (its plugin overlay
  /// hook, order 100); the editor draws only while it is shown.
  @override
  void renderOverlay(Canvas canvas, Size size) {
    if (isVisible.value) _render(canvas, size);
  }

  /// The engine calls this when the plugin is taken off it — its widget
  /// went away. Until it is put back ([attach]) the editor leaves the game
  /// alone: it is closed (a play-test stopped, the game's time scale given
  /// back), its keys let go, the systems it holds off in authoring run
  /// again, its outlines and 3-D aids are gone, and the `just` tool is told
  /// the editor is no longer open. Nothing is disposed — the same plugin may
  /// be put back; [dispose] is for whoever made it.
  @override
  void detach() => _suspend();

  /// Makes the editor for [engine] without the checks [register] makes —
  /// a debug build, a desktop — and without starting it: it starts when it
  /// is registered with the engine ([attach]). [register] is the way a game
  /// makes one; this is for tests and for hosts that make those checks
  /// themselves.
  ///
  /// With no [scope], the plugin makes one over [engine] with the editor's
  /// own modules and [modules], and [dispose] disposes it. A [scope] passed
  /// in is the caller's to dispose; the editor's own modules and [modules]
  /// are added to it. The other parameters are as [register] has them.
  JustGameEditorPlugin({
    required Engine engine,
    EditorScope? scope,
    List<EditorModule> modules = const [],
    List<Spawner> spawners = const [],
    bool bindPhysicsBodies = true,
    LogicalKeyboardKey toggleKey = LogicalKeyboardKey.f1,
    LogicalKeyboardKey statusPanelToggleKey = LogicalKeyboardKey.f2,
    Set<String> protectedSceneNames = const {},
    bool startVisible = true,
    void Function(JustGameEditorPlugin plugin)? onReassemble,
  }) : this._(
         engine: engine,
         scope:
             scope ??
             EditorScope(
               engine: engine,
               builtIns: builtInsFor(engine),
               modules: modules,
             ),
         ownsScope: scope == null,
         lateModules: scope == null ? const [] : modules,
         spawners: spawners,
         bindPhysicsBodies: bindPhysicsBodies,
         toggleKey: toggleKey,
         statusPanelToggleKey: statusPanelToggleKey,
         protectedSceneNames: protectedSceneNames,
         startVisible: startVisible,
         onReassemble: onReassemble,
       );

  JustGameEditorPlugin._({
    required this.engine,
    required this.scope,
    required bool ownsScope,
    required List<EditorModule> lateModules,
    required List<Spawner> spawners,
    required this.bindPhysicsBodies,
    required LogicalKeyboardKey toggleKey,
    required LogicalKeyboardKey statusPanelToggleKey,
    required Set<String> protectedSceneNames,
    required bool startVisible,
    required void Function(JustGameEditorPlugin plugin)? onReassemble,
  }) : _ownsScope = ownsScope,
       _onReassemble = onReassemble,
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
       _gizmoPainter = Gizmo2DPainter() {
    scope.spawners.value = spawners;
    // A scope someone else built gets the editor's own tools, ahead of its
    // modules; one the plugin built already has them.
    builtInsFor(engine).forEach(scope.addBuiltIn);
    // Modules handed to the plugin alongside a scope someone else built join
    // that scope; a scope the plugin built already has them.
    if (lateModules.isNotEmpty) {
      scope.modules.registerAll(lateModules);
      scope.reload();
    }
  }

  /// The editor's own modules for [engine]'s game, as a scope takes them
  /// (`EditorScope(builtIns: …)`): the editor's tools, materials and the
  /// Asset Store ([BuiltInAssetStoreModule], for plugins, kits and assets)
  /// always, and 3-D graphics — models, lights, the environment — for a
  /// game that has them ([BuiltInGraphics3DModule.isFor]).
  static List<EditorModule Function(EditorScope scope)> builtInsFor(
    Engine engine,
  ) => [
    BuiltInEditorModule.make,
    BuiltInMaterialsModule.make,
    if (BuiltInGraphics3DModule.isFor(engine)) BuiltInGraphics3DModule.make,
    BuiltInAssetStoreModule.make,
  ];

  /// The game's engine: the editor edits its world and draws over it.
  final Engine engine;

  /// Everything this editor owns: registries, codec, scene files, log and
  /// scene state. Shared with the overlay and the designer.
  final EditorScope scope;

  /// Whether [dispose] disposes [scope]: true unless one was passed in.
  final bool _ownsScope;

  /// Scene lifecycle operations (list/delete/rename/duplicate) for the
  /// scene picker.
  @internal
  final SceneManager sceneManager;

  /// What a spawn point can create, as the app registers it. The editor's
  /// Play button calls the matching one for every [SpawnComponent] in the
  /// world (once per play session) — the app owns what actually gets created
  /// (a player, a zombie, ...), the editor just knows where and when to ask.
  /// A spawn point's "Spawns" field offers these, and their [Spawner.tags]
  /// tell the editor which tags exist only once the game is running.
  ///
  /// The scope's [EditorScope.spawners], read when they are needed: the
  /// app's [onReassemble] can hand new ones over after a hot reload.
  List<Spawner> get spawners => scope.spawners.value;

  /// What the app does after each hot reload — see [register].
  final void Function(JustGameEditorPlugin plugin)? _onReassemble;

  /// Whether to enable gizmo-drag-to-move for physics bodies (registers
  /// [Physics2DBodyBindingSystem]).
  ///
  /// [Physics2DSystem] (core engine) always owns physics-body lifecycle,
  /// the joints between bodies and [Engine.physics] stepping when it's
  /// present in the game's `World` — this flag doesn't affect that. It only
  /// gates the thin override that makes a body dragged during a play-test
  /// feel immediate (zeroing its velocity, waking it). Safe to leave at its
  /// default in any game.
  final bool bindPhysicsBodies;

  final LogicalKeyboardKey _toggleKey;
  final LogicalKeyboardKey _statusPanelToggleKey;

  /// The engine's debugger, attached while the editor is open; the log
  /// captures what it reports.
  @internal
  final JustDebuggerController debuggerController;

  /// Shared scene state — read by overlay widgets and gizmo logic.
  EditorSceneState get sceneState => scope.sceneState;

  /// The editor log.
  EditorLogService get logService => scope.log;

  /// When this editor started: the log also holds earlier sessions' lines,
  /// loaded back, and what is counted as wrong now starts here.
  @internal
  final DateTime sessionStartedAt = DateTime.now();

  final Gizmo2DPainter _gizmoPainter;

  bool _isInitialized = false;

  /// Whether the editor is open. The overlay follows it.
  final Signal<bool> isVisible = Signal(false, debugLabel: 'editorVisible');

  /// Whether the editor opens itself, with its status panel, once
  /// initialized — see [register].
  final bool _startVisible;

  /// Whether the status bar is shown. It comes and goes with the editor
  /// (F1); F2 opens and shuts the dock panel above it.
  @internal
  final Signal<bool> isStatusPanelVisible = Signal(
    false,
    debugLabel: 'statusPanelVisible',
  );
  bool _isDebuggerAttached = false;

  /// Whether the authoring grid is wanted; [isGridVisible] is whether it
  /// is drawn right now.
  @internal
  final Signal<bool> showGrid = Signal(true, debugLabel: 'showGrid');
  bool _gridSnappingEnabled = true;

  /// The gizmos of each mode, as the settings have them (the Gizmos button
  /// above the snapping, and its menu); [gizmoMode] is the mode now.
  @internal
  final Signal<GizmoSettings> gizmoSettings = Signal(
    GizmoSettings.defaults,
    debugLabel: 'gizmoSettings',
  );

  /// Whether a small view through the game's live camera is drawn over
  /// the editor while authoring.
  @internal
  final Signal<bool> showGamePreview = Signal(true, debugLabel: 'gamePreview');

  /// The authoring grid size, in world units.
  @internal
  final Signal<double> gridSize = Signal(32.0, debugLabel: 'gridSize');

  /// [engine.time.timeScale] captured when the editor is opened, restored
  /// when it's closed again.
  double? _preEditorTimeScale;

  /// Where the play-test is: stopped (authoring), playing or paused.
  EditorPlayState get playState => playController.state.value;

  /// True whenever the editor should behave as "authoring" (the game's time
  /// held at 0, the editor's view owning the camera, play-only systems off)
  /// rather than "simulating" — i.e. the editor is open and no play-test is
  /// in progress.
  @internal
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
  @internal
  late final PlayController playController = PlayController(
    engine: engine,
    scope: scope,
  );

  /// Opens and saves scenes through the scope's store.
  @internal
  late final SceneIO sceneIO = SceneIO(
    scope: scope,
    world: () => engine.world,
    sceneState: sceneState,
  );

  /// Create, delete, group, re-parent and clipboard operations — the
  /// scope's, shared with the windows that open over the editor.
  @internal
  EntityOps get entities => scope.entities;

  /// Pointer handling for the game canvas: gizmos, pan, zoom, designer tools.
  @internal
  late final ViewportInput viewport = ViewportInput(
    world: () => engine.world,
    sceneState: sceneState,
    camera: () => scope.editorView,
    designer: () => designer.value,
    gridSize: () => gridSize.value,
    isActive: () => _isInitialized && isVisible.value,
    isAuthoring: () => isAuthoring.value,
    // Locked in the tree, or hidden: neither can be picked in the
    // viewport, which is what the padlock is for.
    // Nor can anything the Level Designer has put out of reach.
    isPickable: (entity) =>
        !scope.view.isLockedIn(entity) &&
        !scope.view.isHiddenIn(entity) &&
        !PlaySnapshot.isGenerated(entity) &&
        sceneState.canSelect(entity),
    transformMode: () => shownTransformMode ?? TransformMode.all,
    transformModes: () => transformModesAvailable,
    colliderEdit: () => Collider2DEditSession.of(scope),
    handles: () => selectionHandles,
    handleDrags: HandleDragSession(scope),
    commitTransform: (command) {
      scope.history.pushApplied(command);
      sceneState.markDirty();
    },
    pickTests: () => scope.pickTests,
    // In 3-D the gizmo moves, turns and scales all that is selected,
    // about the pivot the designer chose, and moves land where the snaps
    // say.
    selection: () => selectionEntities,
    pivotOf: (entities) =>
        SelectionPivot.of(entities, scope.designer3D.pivotMode.value),
    snaps3D: Translate3DSnaps(
      view: () => scope.editorView,
      state: () => scope.designer3D,
      surfaceAt: (screen, ignore) =>
          RayEntityPicker(tests: () => scope.pickTests).placementAt(
            scope.editorView,
            screen,
            engine.world.entities.where(
              (e) => _isDrawn(e) && !ignore.contains(e),
            ),
          ),
      candidates: () => engine.world.entities.where(_isDrawn),
      vertexSources: () => scope.pickTests.whereType<EntityVertexSource>(),
      holdingV: () => HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.keyV,
      ),
    ),
  );

  // ── Focus nodes ───────────────────────────────────────────────────────────

  /// The game's keyboard focus: it has the keys while the editor is
  /// closed or a play-test runs.
  @internal
  final FocusScopeNode gameFocusScopeNode = FocusScopeNode(
    debugLabel: 'just-game-editor-game-scope',
  );

  /// The editor's keyboard focus while it is open.
  @internal
  final FocusNode editorFocusNode = FocusNode(
    debugLabel: 'just-game-editor-overlay-focus',
  );

  /// Whether the editor has started: [register] did it, or the engine did
  /// when the plugin was registered with it ([attach]).
  bool get isInitialized => _isInitialized;

  /// The key that opens and closes the editor (F1 unless [register] was
  /// given another). No command of the editor's can be bound to it.
  LogicalKeyboardKey get toggleKey => _toggleKey;

  /// The key that opens and shuts the dock panel above the status bar while
  /// the editor is open (F2 unless [register] was given another).
  LogicalKeyboardKey get statusPanelToggleKey => _statusPanelToggleKey;

  /// Whether the editor can run here: on a desktop — Windows, macOS or
  /// Linux — launched from the project folder, where the project's files
  /// are on disk to read and save.
  ///
  /// A phone, a tablet or the web has only the copies of the assets packed
  /// into the app, read-only, so there is no scene to list and nowhere to
  /// save one. [register] returns null there, and a host that wants to say
  /// why asks this.
  static bool get supportsPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Makes and starts the editor for [engine]; a game's editor entry point
  /// calls this, then shows the plugin with `JustGameEngineEditor`.
  ///
  /// Null in a profile or release build, and where the editor cannot run
  /// ([supportsPlatform]): the host then shows just the game.
  ///
  /// - [modules]: the game's own editor modules (its kits, its
  ///   components' editors); the editor's own come first.
  /// - [scope]: an editor scope made beforehand, which the caller then
  ///   disposes; usually left out, and the plugin makes it.
  /// - [spawners]: what a spawn point can create when Play is pressed
  ///   ([EditorScope.spawners]).
  /// - [bindPhysicsBodies]: whether a body dragged during a play-test
  ///   follows the drag at once (and joints can be authored).
  /// - [toggleKey] opens and closes the editor (F1);
  ///   [statusPanelToggleKey] opens and shuts the dock panel (F2).
  /// - [protectedSceneNames]: scenes the game's own code loads by name,
  ///   which the Scenes list will not delete or rename.
  /// - [startVisible]: whether the editor opens at once (true) or waits
  ///   for [toggleKey].
  ///
  /// [onReassemble] runs after each hot reload, before the editor rebuilds
  /// its registries: the place for the app to do again what its `main` did
  /// once and a reload never repeats — register its interface bindings,
  /// add systems it declared since, hand over its spawners
  /// ([EditorScope.spawners]) and modules ([syncModules]). Keep it a call to
  /// a named function, whose body a reload replaces.
  static Future<JustGameEditorPlugin?> register({
    required Engine engine,
    EditorScope? scope,
    List<EditorModule> modules = const [],
    List<Spawner> spawners = const [],
    bool bindPhysicsBodies = true,
    LogicalKeyboardKey toggleKey = LogicalKeyboardKey.f1,
    LogicalKeyboardKey statusPanelToggleKey = LogicalKeyboardKey.f2,
    Set<String> protectedSceneNames = const {},
    bool startVisible = true,
    void Function(JustGameEditorPlugin plugin)? onReassemble,
  }) async {
    if (!kDebugMode) return null;
    if (!supportsPlatform) {
      debugPrint(
        '[JustGameEditor] not started: the editor edits the project files '
        'on disk and needs a desktop (Windows, macOS or Linux).',
      );
      return null;
    }

    final plugin = JustGameEditorPlugin(
      engine: engine,
      scope: scope,
      modules: modules,
      spawners: spawners,
      bindPhysicsBodies: bindPhysicsBodies,
      toggleKey: toggleKey,
      statusPanelToggleKey: statusPanelToggleKey,
      protectedSceneNames: protectedSceneNames,
      startVisible: startVisible,
      onReassemble: onReassemble,
    );
    await plugin._initialize();
    return plugin;
  }

  EditorPresence? _presence;

  /// The systems of the editor's own [_initialize] added to the game's
  /// world — they read the editor's state — taken out again by [dispose].
  final List<System> _ownSystems = [];

  /// The start under way: a second call while it awaits — the engine
  /// attaching while [register] starts the editor — waits for it rather
  /// than starting the editor twice.
  Future<void>? _starting;

  Future<void> _initialize() {
    if (!kDebugMode || _isInitialized) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  /// Starts the editor; [isInitialized] only once all of it is done.
  ///
  /// A start that fails part-way takes back what it did and throws, and the
  /// next [attach] tries again. Marked started first, as it was, the editor
  /// was left with no keys, listeners or loaders, could not be started
  /// again, and went on telling `just` it was open.
  ///
  /// Before the engine has started there is no world to edit: nothing is
  /// done, and [attach] starts the editor once the engine it is registered
  /// with has.
  Future<void> _start() async {
    if (!engine.isInitialized) {
      debugPrint(
        '[JustGameEditor] waiting for the engine: the editor starts when '
        'it is registered with the engine, once that has started.',
      );
      return;
    }
    // So `just game scene` and `just upgrade` wait while the editor is open.
    _presence = EditorPresence.start();
    try {
      await logService.startSession(controller: debuggerController);
      _install();
    } on Object {
      _uninstall();
      rethrow;
    }
    _isInitialized = true;
    // Launching the editor entry point is asking for the editor: open it and
    // its status panel straight away rather than waiting for F1.
    if (_startVisible) setVisible(true);
  }

  /// What [_start] puts on the engine and the editor's own state once the
  /// engine is there and the log is open.
  void _install() {
    // A project the editor cannot write — a sandboxed macOS debug app, a
    // read-only checkout — said now, not as a failed save later.
    if (scope.scenes.writeAccessProblem() case final problem?) {
      scope.log.log(
        problem,
        source: 'editor',
        category: 'scene',
        level: DebuggerLogLevel.warning,
      );
    }
    // A project pinned to another Flutter than this one: the game may not
    // build, and 3-D may draw wrongly. Problems and a message say it too.
    if (FlutterPinCheck.of(scope).mismatch case final pin?) {
      scope.log.log(
        pin.message,
        source: 'editor',
        category: 'project',
        level: DebuggerLogLevel.warning,
        details: pin.fix,
      );
    }
    // No gameplay systems of the editor's own (a movement system, say):
    // what runs in a play-test is what the game's boot registered, or an
    // entity would move in the editor and stand still in the shipped game.
    if (bindPhysicsBodies) {
      // No bridge system here — Physics2DSystem (core engine) owns
      // syncing Physics2DBody results back to TransformComponent itself, for
      // every entity with a Collider2DComponent, not just editor-authored ones.
      if (!engine.world.systems.any(
        (system) => system is Physics2DBodyBindingSystem,
      )) {
        _ownSystems.add(
          // A drag is what it acts on: during a play-test, where bodies
          // move. (Authoring, nothing steps.)
          Physics2DBodyBindingSystem(
            sceneState: sceneState,
            isDraggingActive: () => viewport.isDragging,
          ),
        );
        engine.world.addSystem(_ownSystems.last);
      }
    }
    if (!engine.world.systems.any(
      (system) => system is EditorLogCaptureSystem,
    )) {
      _ownSystems.add(EditorLogCaptureSystem(logService));
      engine.world.addSystem(_ownSystems.last);
    }
    // Sprites are shown and played by the engine's own systems, as in the
    // game — but read from the project's files, so a sheet saved a moment
    // ago shows without a rebuild.
    // For this engine only: another engine in the process is not affected.
    _loaders = engine.context.overrideLoaders(
      sprites: spriteAssets,
      animatorGraphs: spriteAssets.loadGraph,
      timelines: spriteAssets.loadTimeline,
      tileText: spriteAssets.readText,
      prefabs: spriteAssets.loadPrefab,
      material2DText: spriteAssets.readText,
    );
    // What a module (the Asset Store, say) calls after writing files.
    scope.assetReloader = reloadAssets;
    // Tile maps draw in the editor as in the game; their collision is built
    // only in a play-test (see _syncRuntimeSystems).
    // Each only if the game has not added it already.
    registerDefaultSystems(
      engine.world,
      engine,
      include: const {
        DefaultSystem.sprites,
        DefaultSystem.animation,
        DefaultSystem.timelines,
        DefaultSystem.levelMaps,
        DefaultSystem.mapCollision,
      },
    );
    // While authoring, the output camera is the editor's view: the brain
    // keeps thinking but does not write to it. Play hands it over.
    isAuthoring.addListener(_syncCameraOwnership);
    _syncCameraOwnership();
    keepsToLevelMap.addListener(_syncLevelMapFocus);
    _syncLevelMapFocus();
    playController.state.addListener(_focusGameOnPlay);
    playController.state.addListener(_tellModulesPlayState);
    playController.state.addListener(_releasePointerUnlessPlaying);
    _attachDebuggerIfReady();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    // Register game custom components.
    _runComponentRegistrar();
    logService.log(
      'Runtime editor initialized.',
      source: 'editor',
      category: 'lifecycle',
    );
    // From the start, not only once a designer has been opened: the eye
    // in the scene tree works whether or not one ever is.
    _updateRenderFilter();
    // The settings the viewport's look and the play-test follow, and where
    // this session is left, for the next to start from.
    scope.chrome.reservedKeys = {_toggleKey, _statusPanelToggleKey};
    _stopFollowing
      ..add(scope.prefs.settings.watch(_followSettings))
      ..add(logService.onError((_) => _pauseOnError()))
      ..add(sceneState.activeScene.watch(_rememberScene))
      ..add(designer.watch(_rememberDesigner))
      ..add(designer.watch(_syncDesignerSnap))
      ..add(scope.activeWorkspace.watch(_syncDrawingUnderWorkspace));
    isAuthoring.addListener(_syncBackdrop);
    _followSettings();
    // Closing the window asks about unsaved changes first.
    _exitListener ??= AppLifecycleListener(onExitRequested: confirmExit);
  }

  /// Takes back what [_install] did, as far as it got, after a start that
  /// failed: the editor is then as it was before [_start], ready to start
  /// again.
  void _uninstall() {
    _presence?.stop();
    _presence = null;
    for (final stop in _stopFollowing) {
      stop();
    }
    _stopFollowing.clear();
    _removeListeners();
    try {
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    } catch (_) {
      // The keyboard singleton is unavailable if no binding was initialized.
    }
    if (engine.isInitialized) {
      for (final system in _ownSystems) {
        if (engine.world.systems.contains(system)) {
          engine.world.removeSystem(system);
        }
      }
    }
    _ownSystems.clear();
    if (_loaders case final loaders?) {
      _loaders = null;
      loaders.restore();
    }
    if (scope.assetReloader == reloadAssets) scope.assetReloader = null;
    _exitListener?.dispose();
    _exitListener = null;
    logService.stopSession();
  }

  /// The listeners [_install] adds to the editor's own signals, taken off.
  void _removeListeners() {
    isAuthoring
      ..removeListener(_syncCameraOwnership)
      ..removeListener(_syncBackdrop);
    keepsToLevelMap.removeListener(_syncLevelMapFocus);
    playController.state
      ..removeListener(_focusGameOnPlay)
      ..removeListener(_tellModulesPlayState)
      ..removeListener(_releasePointerUnlessPlaying);
  }

  /// Asks the engine's app-exit question for the editor: closing the window
  /// with unsaved changes to the open scene, or to the map files it edits,
  /// asks first through [askToSaveBeforeExit] — save them, discard them, or
  /// stay. Without anyone to ask, a backup of the scene is written and the
  /// window closes. A save under way is waited for first.
  @internal
  Future<AppExitResponse> confirmExit() async {
    for (var i = 0; i < 300 && (_saving || sceneIO.isBusy); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final scene = sceneState.activeScene.value;
    if (scene == null ||
        !(sceneState.isDirty.value || scope.mapDocs.hasDirty)) {
      return AppExitResponse.exit;
    }
    final ask = askToSaveBeforeExit;
    if (ask == null) {
      try {
        await sceneIO.backup(
          asAuthored: _authoredWhilePlaying,
          editorData: designer.value?.editorData() ?? sceneIO.editorData,
          keep: scope.prefs.settings.value.backupsToKeep,
        );
      } on Object catch (error) {
        debugPrint('[JustGameEditor] no backup written on exit: $error');
      }
      return AppExitResponse.exit;
    }
    final choice = await ask(scene.name);
    if (choice == null) return AppExitResponse.cancel;
    if (choice == UnsavedChoice.save) {
      try {
        if (!await saveScene()) return AppExitResponse.cancel;
      } on Object catch (error) {
        scope.log.log(
          'Did not close: ${scene.name} could not be saved: $error',
          source: 'editor',
          category: 'scene',
          level: DebuggerLogLevel.error,
        );
        return AppExitResponse.cancel;
      }
    }
    return AppExitResponse.exit;
  }

  /// Hears the window being closed ([confirmExit]) while the editor runs.
  AppLifecycleListener? _exitListener;

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

  /// What a hot reload must do for the editor to show the code as it now
  /// is. The overlay calls it from its [State.reassemble]; a hot reload is
  /// debug-only, and so is this.
  ///
  /// A reload swaps the code but runs nothing again: not `main`, not a
  /// constructor, not a static initializer. So, in order — the app's own
  /// wiring ([register]'s `onReassemble`), the component definitions, every
  /// registry the editor and its modules fill, the Level Designer's tools,
  /// the built-in docks; then live components whose definition changed are
  /// brought up to it, and the systems are put back in priority order. Each
  /// step stands alone: one that throws is logged, and the rest still run.
  void reassemble() {
    if (!kDebugMode) return;
    final before = _definitionShapes();
    var failed = 0;
    void step(String what, void Function() run) {
      try {
        run();
      } on Object catch (error, stack) {
        failed++;
        logService.log(
          'Hot reload: $what were not brought up to date — $error',
          source: 'editor',
          category: 'reload',
          level: DebuggerLogLevel.error,
          details: '$stack',
        );
      }
    }

    step("the game's wiring", () => _onReassemble?.call(this));
    step('the component definitions', scope.context.refreshDefinitions);
    step("the editor's registries", scope.reassemble);
    step("the Level Designer's tools", () => designer.value?.reloadModules());
    step('the docks', () {
      BuiltInDocks.invalidate(this);
      ProblemScan.of(scope).refresh();
    });
    var adopted = (types: const <String>[], rebuilt: 0);
    step('the components in the scene', () {
      adopted = _adoptChangedDefinitions(before);
    });
    step('the systems', () {
      if (engine.isInitialized) engine.world.sortSystems();
    });
    _updateRenderFilter();
    sceneState.refresh();
    final changed = adopted.types.isEmpty
        ? ''
        : ' Changed: ${adopted.types.join(', ')}'
              '${adopted.rebuilt == 0 ? '' : ' (${adopted.rebuilt} rebuilt)'}.';
    logService.log(
      failed == 0
          ? 'Hot reload: the editor is up to date.$changed'
          : 'Hot reload: $failed step(s) failed; see above.$changed',
      source: 'editor',
      category: 'reload',
      level: failed == 0 ? DebuggerLogLevel.info : DebuggerLogLevel.warning,
    );
  }

  static bool _readsEveryField(ComponentDefinition d, Component component) {
    try {
      for (final f in d.fields) {
        f.read(component);
      }
      return true;
    } on Object {
      return false;
    }
  }

  /// Makes the editor's modules [fresh]: one whose id is new joins, one
  /// whose id is gone leaves (and is disposed), and one still there keeps
  /// its instance — and with it whatever it holds — unless [fresh] has an
  /// instance of another class under that id. The registries are rebuilt
  /// only when something changed.
  ///
  /// For the app's `onReassemble` ([register]), handing over its module
  /// list as the code now makes it, so a module added to `main` shows after
  /// a hot reload. A changed constructor argument of a module that stays
  /// still needs a hot restart.
  void syncModules(List<EditorModule> fresh) {
    final ids = {for (final m in fresh) m.id};
    var changed = false;
    for (final old in scope.modules.all) {
      if (!ids.contains(old.id)) {
        scope.modules.unregister(old.id);
        changed = true;
      }
    }
    for (final module in fresh) {
      final old = scope.modules.byId(module.id);
      if (old != null && old.runtimeType == module.runtimeType) continue;
      // Registering disposes the one it replaces: disposed here as well,
      // it was disposed twice.
      scope.modules.register(module);
      changed = true;
    }
    if (changed) scope.reload();
  }

  // ── Level Designer ────────────────────────────────────────────────────────

  /// Undo for everything the editor does. The scope owns it; this is the
  /// name the rest of the editor reaches it by.
  EditorHistory get history => scope.history;

  /// The Level Designer session, created lazily the first time the designer is
  /// opened on a scene.
  ///
  /// Null until then, so a session that is never used costs nothing — and,
  /// more importantly, so the base editor's behaviour is completely unchanged
  /// for anyone who does not open the designer.
  @internal
  final Signal<LevelDesignerSession?> designer = Signal(
    null,
    debugLabel: 'designer',
  );

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
  @internal
  late final Computed<bool> isGridVisible = Computed(
    () => showGrid.value && isAuthoring.value,
    debugLabel: 'gridVisible',
  );

  /// Whether only the Level Map can be worked on: the Level Designer is
  /// open on a 2-D scene and building, not play-testing, and no workspace
  /// — the tileset or interface editor, which work on things off the map —
  /// is open over it. A 3-D scene has no Level Map: its designer works on
  /// the whole scene.
  @internal
  late final Computed<bool> keepsToLevelMap = Computed(
    () =>
        designer.value != null &&
        sceneState.sceneMode.value == SceneMode.twoD &&
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

  /// Whether [entity] is drawn in the viewport — its sprite, and the
  /// markers and frames the editor draws for it. Everything is during a
  /// play-test; while authoring, not what the eye hid, nor what the Level
  /// Designer has hidden: its layers, and everything but its Level Map.
  bool _isDrawn(Entity entity) {
    if (!isAuthoring.value) return true;
    if (scope.view.isHiddenIn(entity)) return false;
    final session = designer.value;
    return session == null || session.controller.isShownInViewport(entity);
  }

  static final Set<LogicalKeyboardKey> _flyKeys = {
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.keyE,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };

  // Handed to HardwareKeyboard: one method, so removeHandler finds it.
  bool _onHardwareKey(KeyEvent event) => _dispatchKey(event);

  /// Where sprites are read from while the editor runs: the project's files.
  /// What they are not in comes from the engine's own loaders.
  @internal
  late final FileSpriteAssetLoader spriteAssets = FileSpriteAssetLoader(
    context: engine.context,
  );

  /// What [_initialize] pointed the engine's loaders at, to put back.
  LoaderOverride? _loaders;

  /// The JSON files that are something other than a sprite atlas. Every
  /// other `.json` in a project is taken to be an atlas — the one kind of
  /// JSON that carries no suffix of its own.
  @internal
  static const List<String> dataJsonSuffixes = [
    '.scene.json',
    '.animator.json',
    '.timeline.json',
    '.tileset.json',
    PrefabFile.ending,
    '.input.json',
    LevelMapFiles.suffix,
    LevelMapFiles.legacySuffix,
    '/scenes.json',
    '/palettes.json',
    // The project's own settings files (assets/project/…).
    '/tags.json',
    '/physics.json',
  ];

  /// The data files above that may also be the whole path, with no folder
  /// before them.
  static const List<String> _bareDataFiles = [
    'scenes.json',
    'palettes.json',
    'tags.json',
    'physics.json',
  ];

  /// Whether [path] is a sprite atlas: a `.json` that is none of the
  /// editor's other data files, nor one of [scope]'s modules'
  /// ([EditorScope.dataFileSuffixes]).
  @internal
  static bool isSpriteAtlasPath(String path, {EditorScope? scope}) {
    final p = path.toLowerCase().replaceAll('\\', '/');
    if (!p.endsWith('.json') || _bareDataFiles.contains(p)) return false;
    final modules = scope?.dataFileSuffixes ?? const <String>{};
    return !dataJsonSuffixes.any(p.endsWith) && !modules.any(p.endsWith);
  }

  /// Whether dropping [path] on the viewport of a scene of [mode] makes
  /// something: a kind one of [scope]'s modules knows how to drop, in the
  /// scenes it drops in ([AssetKind.dropsIn]: a model in 3-D, a sound in
  /// either); in 2-D also an image, a sprite project, a sprite atlas, a
  /// tileset or a map.
  @internal
  static bool canDropAsset(
    String path, {
    SceneMode mode = SceneMode.twoD,
    EditorScope? scope,
  }) {
    final kind = scope?.assetKinds.of(path);
    if (kind != null && kind.drop != null) return kind.dropsInto(mode);
    // Sprites and tile maps are 2-D: a 3-D scene does not draw them.
    if (mode != SceneMode.twoD) return false;
    return _dropsFlat(path, scope: scope);
  }

  /// Why dropping [path] on the viewport of a scene of [mode] makes
  /// nothing when it would in a scene of the other mode — a model in a 2-D
  /// scene, a sprite in a 3-D one — or null when it drops, or would
  /// nowhere. What the viewport says as it turns the file away.
  @internal
  static String? dropRefusal(
    String path, {
    SceneMode mode = SceneMode.twoD,
    EditorScope? scope,
  }) {
    if (canDropAsset(path, mode: mode, scope: scope)) return null;
    String name(SceneMode m) => m == SceneMode.threeD ? '3D' : '2D';
    final kind = scope?.assetKinds.of(path);
    if (kind != null && kind.drop != null) {
      for (final other in SceneMode.values) {
        if (other == mode || !kind.dropsInto(other)) continue;
        return '${kind.label} go in ${name(other)} scenes: '
            'this one is ${name(mode)}.';
      }
      return null;
    }
    if (mode == SceneMode.twoD || !_dropsFlat(path, scope: scope)) return null;
    return 'Sprites and tile maps go in 2D scenes: this one is 3D.';
  }

  // Whether [path] is a file a 2-D scene takes from the editor itself: an
  // image, a sprite project, a sprite atlas, a tileset or a map.
  static bool _dropsFlat(String path, {EditorScope? scope}) {
    final p = path.toLowerCase();
    return p.endsWith('.tileset.json') ||
        LevelMapFiles.isMapFile(p) ||
        TiledImporter.isTiledMap(path) ||
        p.endsWith('.png') ||
        p.endsWith('.jpg') ||
        p.endsWith('.jpeg') ||
        p.endsWith('.webp') ||
        p.endsWith('.jsprite') ||
        isSpriteAtlasPath(path, scope: scope);
  }

  /// Many files changed at once — a package installed, updated or removed:
  /// each kind is reloaded once, not once per file.
  @internal
  void reloadAssets(Iterable<String> paths) {
    var sprites = false;
    var allMaps = false;
    final maps = <String>{};
    for (final path in paths) {
      final lower = path.toLowerCase();
      if (lower.endsWith('.animator.json')) {
        reloadAnimators(path);
      } else if (lower.endsWith('.timeline.json')) {
        reloadTimelines(path);
      } else if (lower.endsWith('.tsx') || lower.endsWith('.tsj')) {
        allMaps = true;
      } else if (lower.endsWith('.tileset.json') ||
          LevelMapFiles.isMapFile(lower) ||
          lower.endsWith('.tmx') ||
          lower.endsWith('.tmj')) {
        maps.add(path);
      } else if (PrefabFile.isPrefabPath(lower)) {
        _refreshPrefab(path);
      } else if (isSpriteAtlasPath(path, scope: scope)) {
        sprites = true;
      } else if (!lower.endsWith('.json') &&
          !_isFont(lower) &&
          !_isAudio(lower)) {
        sprites = true;
      }
    }
    if (allMaps) {
      reloadLevelMaps();
    } else {
      maps.forEach(reloadLevelMaps);
    }
    if (sprites) reloadSprites();
    // After the sprites, whose loader the materials read their maps from.
    paths.forEach(_reloadMaterials);
    for (final path in paths) {
      for (final module in scope.modules.withBuiltIns) {
        module.onAssetChanged(path);
      }
    }
  }

  static bool _isFont(String lower) =>
      lower.endsWith('.ttf') ||
      lower.endsWith('.otf') ||
      lower.endsWith('.ttc');

  static bool _isAudio(String lower) =>
      lower.endsWith('.wav') ||
      lower.endsWith('.mp3') ||
      lower.endsWith('.ogg') ||
      lower.endsWith('.flac') ||
      lower.endsWith('.m4a');

  /// Play started or stopped: modules that show something only in a
  /// play-test — the game's screens — follow it.
  bool _modulesThinkPlaying = false;
  void _tellModulesPlayState() {
    final playing = playController.state.value != EditorPlayState.stopped;
    scope.isPlayTesting.value = playing;
    if (playing == _modulesThinkPlaying) return;
    _modulesThinkPlaying = playing;
    for (final module in scope.modules.withBuiltIns) {
      module.onPlayStateChanged(playing);
    }
    if (!playing) _refreshPrefabsChangedMeanwhile();
  }

  /// Prefab files that changed while the world was the game's — a
  /// play-test, or the editor hidden — whose instances are made again once
  /// the level as authored is back ([_refreshPrefabsChangedMeanwhile]).
  final Set<String> _prefabsChangedMeanwhile = {};

  /// The prefab at [path] changed on disk: its instances are made again
  /// from it — now while authoring; while the game runs on the level, once
  /// the level is put back. Made again during a play-test, they were made
  /// from what the game had done to them, and Stop then put back the
  /// instances made from the old file.
  void _refreshPrefab(String path) {
    if (playController.isRunning || _hiddenSnapshot != null) {
      _prefabsChangedMeanwhile.add(path);
      return;
    }
    unawaited(scope.prefabInstances.refresh(path));
  }

  void _refreshPrefabsChangedMeanwhile() {
    if (playController.isRunning || _hiddenSnapshot != null) return;
    final paths = List.of(_prefabsChangedMeanwhile);
    _prefabsChangedMeanwhile.clear();
    paths.forEach(_refreshPrefab);
  }

  void _focusGameOnPlay() {
    if (playController.state.value == EditorPlayState.playing) focusGame();
  }

  /// Paused or stopped, the editor needs the mouse back.
  void _releasePointerUnlessPlaying() {
    if (playController.state.value == EditorPlayState.playing) return;
    if (engine.isInitialized) unawaited(engine.input.releasePointer());
  }

  /// Whether a text field has keyboard focus.
  static bool get _isTypingInTextField {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _update(double dt) {
    scope.modules.notifyUpdate(dt);
    _attachDebuggerIfReady();
    // After the frame's game update: play time, and the end of a stepped frame.
    if (_isInitialized) playController.tick(dt);
    if (_isInitialized) BuiltInDocks.captureFrame(this);
    if (_isInitialized) sceneIO.loading.tick();
    if (_isInitialized) _autosaveTick();
    if (_isInitialized) _syncRuntimeSystems(dt);
    if (_isInitialized) _syncSplit();
    if (_isInitialized) _syncSceneAids();
    if (_isInitialized) _syncColliderOutlines();
    if (!_isInitialized || !isVisible.value) return;
    // Right button held in 3-D: WASD flies the view.
    viewport.flyTick(dt, HardwareKeyboard.instance.logicalKeysPressed);
    _holdTimeWhileAuthoring();
    // The game is frozen while authoring, so the brain is asked directly:
    // every camera snaps to what it would frame, which is what the camera
    // gizmos and the game preview draw.
    if (isAuthoring.value &&
        engine.isInitialized &&
        engine.camera.isInitialized) {
      engine.camera.brain.evaluate(engine.world, 0, snap: true);
    }
  }

  /// What the editor adds to its 3-D views — what it hides, the
  /// selection's outline, the view mode, the slice — handed to the 3-D
  /// renderer while authoring a 3-D scene; taken back otherwise, so a
  /// play-test shows the level as it ships.
  @internal
  late final g3.SceneEditorAids sceneAids = g3.SceneEditorAids()
    ..plainViews.add(_previewFrame)
    ..drawFilter = _isDrawn
    ..highlighted = () => selectionEntities;

  /// In a play-test: the selection's outline, when its gizmos show it,
  /// and nothing else of the editor's.
  late final g3.SceneEditorAids _playAids = g3.SceneEditorAids()
    ..plainViews.add(_previewFrame)
    ..highlighted = () => selectionEntities;

  /// The engine's collider drawer, in the game's world while it shows 2-D
  /// colliders — see [_syncColliderOutlines].
  Collider2DDebuggerSystem? _colliderOutlines;

  /// The editor's view, kept across a play-test so Stop returns to exactly
  /// where the author was looking.
  CameraState? _editorView;

  /// Decides who writes the output camera. Authoring: the editor — its pan,
  /// zoom and bookmarks — while the brain only thinks. Otherwise the brain.
  void _syncCameraOwnership() {
    if (!engine.isInitialized || !engine.camera.isInitialized) return;
    final brain = engine.camera.brain;
    final authoring = isAuthoring.value;
    if (authoring == !brain.driveOutput) return;
    final camera = engine.camera.mainCamera;
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

  /// The viewport split four ways (top, front, side, perspective) — while
  /// [SplitViews.on], authoring a 3-D scene.
  @internal
  late final SplitViews splitViews = SplitViews(
    () => scope.sceneView as OrbitFlyEditorView,
  );

  int _inPaneDepth = 0;

  /// The preview's top-left corner on the canvas. The chrome publishes it on
  /// every layout, so the preview hangs directly below the play controls
  /// wherever they are.
  @internal
  Offset gamePreviewOrigin = const Offset(16, 56);

  /// How much of the canvas's foot the preview must stay clear of — the
  /// settings gear, and while designing the minimap standing on it. The
  /// chrome publishes it with the origin.
  @internal
  double gamePreviewBottomReserve = 0;

  /// How the preview's panel is drawn. The chrome publishes it with the
  /// origin, from the same settings the play toolbar is drawn with, so the
  /// two read as one piece of UI.
  @internal
  GamePreviewStyle gamePreviewStyle = const GamePreviewStyle();

  /// Height of the preview panel's header row: the LIVE chip and camera name.
  @internal
  static const double gamePreviewHeaderHeight = 22;

  /// The whole preview **panel** on a canvas of [canvasSize], with its corner
  /// at [origin]: a fraction of the canvas wide, and as tall as its header
  /// plus a game view of the game's own aspect.
  ///
  /// On a canvas too short for that above [bottomReserve], it is narrower —
  /// the same shape, smaller — rather than run into what is at the foot.
  @internal
  static Rect gamePreviewRect(
    Size canvasSize, {
    Offset origin = const Offset(16, 56),
    GamePreviewStyle style = const GamePreviewStyle(),
    double bottomReserve = 0,
  }) {
    final aspect = canvasSize.height / canvasSize.width;
    final chrome = style.padding * 2 + gamePreviewHeaderHeight;
    double heightFor(double width) =>
        chrome + (width - style.padding * 2) * aspect;
    var width = (canvasSize.width * 0.24).clamp(180.0, 420.0).toDouble();
    final room = canvasSize.height - bottomReserve - origin.dy;
    if (heightFor(width) > room) {
      width = math.max(96.0, (room - chrome) / aspect + style.padding * 2);
    }
    return Rect.fromLTWH(origin.dx, origin.dy, width, heightFor(width));
  }

  /// The game view inside [panel]: below the header, inset by the padding.
  @internal
  static Rect gamePreviewViewRect(
    Rect panel, {
    GamePreviewStyle style = const GamePreviewStyle(),
  }) => Rect.fromLTRB(
    panel.left + style.padding,
    panel.top + style.padding + gamePreviewHeaderHeight,
    panel.right - style.padding,
    panel.bottom - style.padding,
  );

  // The preview's own view, kept so a 3-D backend keeps one surface for it.
  final FrameView _previewFrame = FrameView();

  /// Asks whether to open [sceneName] from a backup of changes that were
  /// never saved, made at [when]: true recovers them, false opens the file
  /// and sets the backup aside, null opens the file and asks again next
  /// time. Set by the overlay, which has somewhere to ask; without it the
  /// file opens.
  @internal
  Future<bool?> Function(String sceneName, DateTime when)? askToRecover;

  /// Asks what to do with the unsaved changes to the scene [leaving] before
  /// [opening] replaces it: save them, discard them, or — null — stay on
  /// it. Set by the overlay, which has somewhere to ask; without it a scene
  /// with unsaved changes is never left for another.
  @internal
  Future<UnsavedChoice?> Function(String leaving, String opening)?
  askToLeaveScene;

  /// Asks what to do with the unsaved changes to the scene [open] before
  /// the window closes: save them, discard them, or — null — stay. Set by
  /// the overlay; without it a backup is written and the window closes
  /// ([confirmExit]).
  @internal
  Future<UnsavedChoice?> Function(String open)? askToSaveBeforeExit;

  /// The level as authored while the editor is hidden over a scene: the
  /// game runs on the editor's world then, as in a play-test, and showing
  /// the editor again puts this back. What a save writes meanwhile.
  PlaySnapshot? _hiddenSnapshot;

  /// Whether [openScene] is under way — its questions asked, or the scene
  /// read — during which autosave waits: the scene being left may have
  /// had its changes discarded already.
  bool _openingScene = false;

  /// Whether [saveScene] is under way, the map files included.
  bool _saving = false;

  /// Opens [sceneName] through [sceneIO], closing the Level Designer first:
  /// its undo commands hold entities of the scene being left, and it reopens
  /// cleanly on the new one. A backup with changes never saved is offered
  /// first.
  ///
  /// The scene open now is left first, as [leaveScene] does it: unsaved
  /// changes are asked about, and a play-test of it ends. Nothing opens
  /// while another open or a save is under way, or when the question is
  /// cancelled.
  ///
  /// Autosave waits from the first question to the end of the open: once
  /// the changes are discarded, it must not save them while the next
  /// question — recover a backup? — waits for its answer.
  Future<void> openScene(String sceneName) async {
    if (sceneIO.isBusy || _saving || _openingScene) return;
    _openingScene = true;
    try {
      await _openScene(sceneName);
    } finally {
      _openingScene = false;
    }
  }

  Future<void> _openScene(String sceneName) async {
    if (!await leaveScene(opening: sceneName)) return;
    if (sceneIO.isBusy || _saving) return;
    final wasDesignerOpen = isLevelDesignerOpen;
    Map<String, dynamic>? recovered;
    final ask = askToRecover;
    final backup = ask == null ? null : scope.scenes.unsavedBackupOf(sceneName);
    if (ask != null && backup != null) {
      final recover = await ask(sceneName, backup.lastModifiedSync());
      if (recover == true) {
        recovered = await scope.scenes.readBackup(backup);
      } else if (recover == false) {
        await _declineBackups(sceneName);
      }
    }
    closeLevelDesigner();
    final assets = _countSceneAssets();
    final opened = recovered != null
        ? await sceneIO.openFrom(sceneName, recovered, assets: assets)
        : await sceneIO.open(sceneName, assets: assets);
    // Not opened (the file could not be read): the scene that was open
    // still is, and the designer goes back to it.
    if (!opened && !sceneState.hasScene) return;
    if (wasDesignerOpen) openLevelDesigner();
  }

  /// Sets aside every backup of [sceneName] holding changes never saved,
  /// not only the newest: Backup-mode autosave keeps several, and each
  /// older one was offered again on the next open once the newer had gone.
  Future<void> _declineBackups(String sceneName) async {
    final seen = <String>{};
    for (
      var backup = scope.scenes.unsavedBackupOf(sceneName);
      // One that could not be set aside is not offered again here.
      backup != null && seen.add(backup.path);
      backup = scope.scenes.unsavedBackupOf(sceneName)
    ) {
      await scope.scenes.setAside(backup);
    }
  }

  // ── Autosave ───────────────────────────────────────────────────────────

  DateTime? _nextAutosave;
  bool _autosaving = false;

  // ── Where the session is left ──────────────────────────────────────────

  static final SettingPref<bool> _designerOpenPref = SettingPref.boolean(
    OverlaySettingsPrefKeys.sessionDesignerOpen,
    false,
  );

  bool _reopened = false;

  // ── Settings the plugin follows ────────────────────────────────────────

  final List<void Function()> _stopFollowing = [];

  Color? _gameBackdrop;

  /// While authoring, the viewport clears to the settings' backdrop; the
  /// game gets its own back to play in.
  void _syncBackdrop() {
    if (!engine.isInitialized) return;
    final rendering = engine.rendering;
    final wanted = isAuthoring.value
        ? scope.prefs.settings.value.backdrop
        : null;
    if (wanted != null) {
      _gameBackdrop ??= rendering.backgroundColor;
      rendering.backgroundColor = wanted;
    } else if (_gameBackdrop != null) {
      rendering.backgroundColor = _gameBackdrop!;
      _gameBackdrop = null;
    }
  }

  /// How often the level is drawn while a workspace is open over it. It is
  /// dimmed and nearly covered there, and drawing it every frame only took
  /// time from the workspace — a lit level drawn with a 2-D material
  /// window's own lit preview filled the GPU's memory: 3 fps. Often enough
  /// that what is edited live in the scene still shows at its edges.
  @internal
  static const Duration drawIntervalUnderWorkspace = Duration(
    milliseconds: 250,
  );

  // The game's own drawInterval, while a workspace has the level's.
  Duration? _gameDrawInterval;
  bool _drawingHeld = false;

  /// Saves the active scene. During a play-test the level is saved as it was
  /// authored, not as the simulation has left it.
  ///
  /// Map files edited alongside it are saved too: one save, one unsaved
  /// mark, for the scene and the maps it uses.
  ///
  /// A map file that could not be written does not stop the scene being
  /// saved; it stays unsaved (and the scene with it), and the save then
  /// throws a [FileSystemException] naming it, for whoever asked to save to
  /// say so — closing the scene does not go on as though all were saved.
  ///
  /// False when it was not saved because an open or another save was under
  /// way; an error writing it is thrown.
  ///
  /// One save at a time, from its first map file to the scene: a second —
  /// Ctrl+S during an autosave — gets false, rather than writing the same
  /// map files at once through the same temporary files.
  Future<bool> saveScene() async {
    if (sceneIO.isBusy || _saving) return false;
    _saving = true;
    try {
      final mapsFailed = await scope.mapDocs.saveDirty();
      final saved = await sceneIO.save(
        // The level as authored while the game runs on it: a play-test's
        // snapshot, or the one taken when the editor was hidden.
        asAuthored: _authoredWhilePlaying,
        editorData: designer.value?.editorData() ?? sceneIO.editorData,
      );
      if (mapsFailed.isNotEmpty) {
        // Still not on disk: the unsaved mark stays.
        sceneState.markDirty();
        throw FileSystemException(
          'Could not save ${mapsFailed.keys.join(', ')}: '
          '${mapsFailed.values.join('; ')}',
        );
      }
      return saved;
    } finally {
      _saving = false;
    }
  }

  // ── Play / Pause / Stop ────────────────────────────────────────────────────

  /// Starts or resumes the play-test; see [PlayController.play].
  void play() {
    if (_isInitialized) playController.play();
  }

  /// Starts the play-test with the player at [at] instead of its spawn
  /// point — placed by the game kit that knows its player
  /// (`LevelAids.playFrom`), else whatever carries the `player` tag.
  /// Whether it was placed; nothing when a play-test is on already, nor
  /// when Play did not start (a spawner threw): the player then is the one
  /// authored in the level, and moving it would move it for good.
  @internal
  bool playFrom(Vector3 at) {
    if (!_isInitialized ||
        playController.state.value != EditorPlayState.stopped) {
      return false;
    }
    playController.play();
    if (!playController.isRunning) return false;
    final world = engine.world;
    for (final aids in scope.levelAids) {
      if (aids.playFrom(world, at)) return true;
    }
    for (final e in world.entities) {
      if (!e.isAlive ||
          !(e.getComponent<TagComponent>()?.tags.contains('player') ?? false)) {
        continue;
      }
      final t = e.getComponent<TransformComponent>();
      if (t == null) continue;
      t.position.setValues(at.x, at.y, view3D ? at.z : t.position.z);
      world.transformHierarchy.propagateFrom(e);
      return true;
    }
    scope.log.log(
      'Play from here: no game kit placed its player, and nothing is tagged '
      '"player"; it started from the spawn point.',
      source: 'editor',
      category: 'play',
    );
    return false;
  }

  /// Whether the editor's view is 3-D: the open scene is a 3-D one.
  @internal
  bool get view3D => !scope.editorView.isPlanar;

  /// Freezes the play-test; see [PlayController.pause].
  void pause() => playController.pause();

  /// Ends the play-test and restores the authored scene; see
  /// [PlayController.stop].
  void stop() => playController.stop();

  // ── Visibility ────────────────────────────────────────────────────────────

  /// Opens the editor when it is closed and closes it when it is open, as
  /// [toggleKey] does.
  void toggleVisibility() => setVisible(!isVisible.value);

  /// Opens or closes the editor, with its status bar. Opening holds the
  /// game's time at 0 for authoring and takes the keyboard from the game;
  /// closing stops a play-test, gives the game back the time scale it had
  /// and gives it the keyboard back.
  void setVisible(bool visible) => _setVisible(visible);

  bool _suspended = false;

  /// Closes the editor for good: takes off the game's world what the editor
  /// added to it, gives the engine back its own settings, and disposes the
  /// editor's state — and [scope], when the plugin made it. For whoever
  /// made the plugin, after it is off the engine; the plugin is not used
  /// again.
  void dispose() {
    // Closed and let go of first, as a detach would: no play-test left
    // running, the game's time scale back, no key handler, no heartbeat.
    _suspend();
    _presence?.stop();
    _presence = null;
    for (final stop in _stopFollowing) {
      stop();
    }
    _stopFollowing.clear();
    // What _initialize put on the engine that reads the editor's state:
    // read after this, it would be read from disposed signals.
    if (engine.isInitialized) {
      final render = engine.world.getSystem<RenderSystem>();
      if (render != null && render.shouldRender == _isDrawn) {
        render.shouldRender = null;
      }
      for (final system in _ownSystems) {
        if (engine.world.systems.contains(system)) {
          engine.world.removeSystem(system);
        }
      }
    }
    _ownSystems.clear();
    _detachDebugger();
    _exitListener?.dispose();
    _exitListener = null;
    _hiddenSnapshot = null;
    isAuthoring.removeListener(_syncBackdrop);
    if (_gameBackdrop != null && engine.isInitialized) {
      engine.rendering.backgroundColor = _gameBackdrop!;
      _gameBackdrop = null;
    }
    if (_drawingHeld && engine.isInitialized) {
      engine.rendering.drawInterval = _gameDrawInterval;
      _drawingHeld = false;
    }
    closeLevelDesigner();
    _removeListeners();
    // Tear-offs of one method on one object are equal, not identical.
    if (scope.assetReloader == reloadAssets) {
      scope.assetReloader = null;
    }
    if (_loaders case final loaders?) {
      _loaders = null;
      loaders.restore();
      // What was read from the project's files is not the bundle's.
      engine.context.tiles.clear();
    }
    if (engine.isInitialized && engine.camera.isInitialized) {
      engine.camera.brain.driveOutput = true;
    }
    try {
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    } catch (_) {
      // The keyboard singleton is unavailable if no binding was initialized.
    }
    logService.stopSession();
    playController.dispose();
    debuggerController.dispose();
    // Before the scope: made late, either may be made now from its state.
    splitViews.dispose();
    sceneIO.loading.dispose();
    if (_ownsScope) scope.dispose();
    editorFocusNode.dispose();
    gameFocusScopeNode.dispose();
    isGridVisible.dispose();
    keepsToLevelMap.dispose();
    isAuthoring.dispose();
    for (final signal in [
      isVisible,
      isStatusPanelVisible,
      showGrid,
      showGamePreview,
      gridSize,
    ]) {
      signal.dispose();
    }
    gizmoSettings.dispose();
    designer.dispose();
  }
}
