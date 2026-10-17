import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerSignalEvent, kPrimaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../debugger/engine_debugger.dart';
import '../../ui/inspector/physics/collider_edit_session.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine/graphics_3d.dart' as g3;
import '../physics/collider_overlay_3d.dart';
import '../input/selection_pivot.dart';
import '../input/translate_snaps_3d.dart';
import '../../ui/level_designer_3d/split/split_views.dart';
import '../assets/file_sprite_asset_loader.dart';
import '../../ui/level_designer/state/map_placement.dart';
import '../ecs/systems/editor_log_capture_system.dart';
import '../ecs/systems/physics_body_binding_system.dart';
import '../entity/entity_ops.dart';
import '../physics/physics_bodies.dart';
import '../input/viewport_input.dart';
import '../play/play_controller.dart';
import '../project/editor_presence.dart';
import '../scene/scene_io.dart';
import '../scene/scene_loading.dart' show AssetTally;
import '../serialization/scene_manager.dart';
import '../state/play_snapshot.dart';
import '../../ui/overlay/docks/extra/extra_docks.dart' show ProblemScan;
import '../../ui/overlay/docks/shell/built_in_docks.dart' show BuiltInDocks;
import '../../ui/overlay/gizmo_3d.dart';
import '../../ui/overlay/gizmo_painter.dart';
import '../view/orbit_fly_editor_view.dart';
import '../../ui/overlay/settings/settings_dialog.dart';
import '../../ui/level_designer/level_designer_session.dart';
import '../level_map/tiled_import.dart';
import '../../extension/built_in_tile_contributions.dart';
import '../level_map/level_map_documents.dart';
import '../level_map/level_map_focus.dart';
import '../level_map/level_map_provision.dart';
import '../level_map/tile_commands.dart';
import '../../ui/level_designer/tools/tiles/tile_tool_base.dart';
import '../../extension/built_in_editor_module.dart';
import '../../ui/overlay/camera_rig_painter.dart';
import '../prefs/recent_scenes.dart';
import '../scope/editor_scope_services.dart';

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

  /// The engine calls this over the world every frame (its plugin overlay
  /// hook, order 100); the editor draws only while it is shown.
  @override
  void renderOverlay(Canvas canvas, Size size) {
    if (isVisible.value) onRender(canvas, size);
  }

  @override
  void detach() {}

  JustGameEditorPlugin({
    required Engine engine,
    EditorScope? scope,
    List<EditorModule> modules = const [],
    List<Spawner> spawners = const [],
    @Deprecated('Use spawners, which also say what each one is.')
    Map<String, Entity Function(World world, Entity spawnPoint)> spawnRegistry =
        const {},
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
               builtIns: const [BuiltInEditorModule.new],
               modules: [..._staticModules, ...modules],
             ),
         ownsScope: scope == null,
         lateModules: scope == null ? const [] : modules,
         spawners: [
           ...spawners,
           for (final s in Spawner.fromMap(spawnRegistry))
             if (!spawners.any((x) => x.id == s.id)) s,
         ],
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
       _gizmoPainter = GizmoPainter() {
    scope.spawners.value = spawners;
    // A scope someone else built gets the editor's own tools, ahead of its
    // modules; one the plugin built already has them.
    scope.addBuiltIn(BuiltInEditorModule.new);
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

  /// [spawners] by id, as the old constructor took them.
  @Deprecated('Use spawners.')
  Map<String, Entity Function(World world, Entity spawnPoint)>
  get spawnRegistry => {for (final s in spawners) s.id: s.spawn};

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
    colliderEdit: () => ColliderEditSession.of(scope),
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
    snaps3D: TranslateSnaps3D(
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

  final FocusScopeNode gameFocusScopeNode = FocusScopeNode(
    debugLabel: 'just-game-editor-game-scope',
  );
  final FocusNode editorFocusNode = FocusNode(
    debugLabel: 'just-game-editor-overlay-focus',
  );

  bool get isInitialized => _isInitialized;
  LogicalKeyboardKey get toggleKey => _toggleKey;
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

  /// Factory for debug-only plugin registration.
  ///
  /// Null in a profile or release build, and where the editor cannot run
  /// ([supportsPlatform]): the host then shows just the game.
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
    @Deprecated('Use spawners, which also say what each one is.')
    Map<String, Entity Function(World world, Entity spawnPoint)> spawnRegistry =
        const {},
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
      spawnRegistry: spawnRegistry,
      bindPhysicsBodies: bindPhysicsBodies,
      toggleKey: toggleKey,
      statusPanelToggleKey: statusPanelToggleKey,
      protectedSceneNames: protectedSceneNames,
      startVisible: startVisible,
      onReassemble: onReassemble,
    );
    await plugin.onInitialize();
    return plugin;
  }

  EditorPresence? _presence;

  Future<void> onInitialize() async {
    if (!kDebugMode || _isInitialized) return;
    _isInitialized = true;
    // So `just game scene` and `just upgrade` wait while the editor is open.
    _presence = EditorPresence.start();
    await logService.startSession(controller: debuggerController);
    if (!engine.world.systems.any((system) => system is SimpleMovementSystem)) {
      engine.world.addSystem(SimpleMovementSystem(engine.input));
    }
    if (bindPhysicsBodies) {
      // No bridge system here — PhysicsSystem (core engine) owns
      // syncing PhysicsBody results back to TransformComponent itself, for
      // every entity with a Collider2D, not just editor-authored ones.
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
    // For this engine only: another engine in the process is not affected.
    _loaders = engine.context.overrideLoaders(
      sprites: spriteAssets,
      animatorGraphs: spriteAssets.loadGraph,
      timelines: spriteAssets.loadTimeline,
      tileText: spriteAssets.readText,
      prefabs: spriteAssets.loadPrefab,
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
    // Register game custom components; a component refresh asked for by
    // hand goes the way a hot reload does.
    _runComponentRegistrar();
    sceneState.onComponentsRefreshed = reassemble;
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
      ..add(designer.watch(_syncDesignerSnap));
    isAuthoring.addListener(_syncBackdrop);
    _followSettings();
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

  /// Each definition's fields — name and kind — by type: enough to tell
  /// which ones a reload changed.
  Map<String, List<(String, String)>> _definitionShapes() => {
    for (final d in scope.definitions.definitions)
      d.type: [for (final f in d.fields) (f.name, f.kind.id)],
  };

  /// Brings the scene's components up to definitions a reload changed.
  ///
  /// A component made before its class gained a field may not be able to
  /// read it — its value was never set. Such a one is made again from what
  /// it holds, through the new definition, as Stop puts a component back; the
  /// new field takes its default. One that reads every field is kept as it
  /// is, since undo steps hold it. Left alone during a play-test: Stop
  /// restores through the new definitions anyway.
  ({List<String> types, int rebuilt}) _adoptChangedDefinitions(
    Map<String, List<(String, String)>> before,
  ) {
    final changed = <String>{};
    for (final d in scope.definitions.definitions) {
      final was = before[d.type];
      if (was == null) continue;
      final now = [for (final f in d.fields) (f.name, f.kind.id)];
      if (!listEquals(was, now)) changed.add(d.type);
    }
    var rebuilt = 0;
    if (changed.isEmpty || !engine.isInitialized || playController.isRunning) {
      return (types: changed.toList(), rebuilt: rebuilt);
    }
    for (final entity in engine.world.entities.toList()) {
      for (final component in entity.components.toList()) {
        final d = scope.definitions.definitionFor(component);
        if (d == null || !changed.contains(d.type)) continue;
        if (_readsEveryField(d, component)) continue;
        final fields = <String, Object?>{};
        for (final f in d.fields) {
          try {
            fields[f.name] = f.encodeFrom(component);
          } on Object {
            // The field it never had: the new instance's default.
          }
        }
        entity.addComponent(d.decode({'type': d.type, 'fields': fields}));
        rebuilt++;
      }
    }
    return (types: changed.toList(), rebuilt: rebuilt);
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
      old?.dispose();
      scope.modules.register(module);
      changed = true;
    }
    if (changed) scope.reload();
  }

  void _attachDebuggerIfReady() {
    if (_isDebuggerAttached || !engine.isInitialized) return;
    engine.attachDebugger(debuggerController);
    _isDebuggerAttached = true;
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
  final Signal<LevelDesignerSession?> designer = Signal(
    null,
    debugLabel: 'designer',
  );

  /// Changes the grid size from the Level Designer.
  ///
  /// Writes through to [sceneState], the plugin's own copy and the saved
  /// settings, so the designer's control and the settings dialog never
  /// disagree about what the grid is — and the next settings change does not
  /// put the old size back.
  void setGridSize(double size) {
    if (size <= 0 || size == gridSize.value) return;
    gridSize.value = size;
    sceneState.setGridSnapping(enabled: _gridSnappingEnabled, gridSize: size);
    final prefs = scope.prefs;
    if (prefs.settings.value.gridSize != size) {
      prefs.update(prefs.settings.value.copyWith(gridSize: size));
    }
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

  // ── Move, Scale, Rotate ───────────────────────────────────────────────────

  /// What the Move, Scale and Rotate toolbar can act on now. Nothing
  /// during a play-test. With Select tiles in hand, the tiles it has
  /// selected; otherwise what is selected — in the designer all of it, in
  /// the editor the one entity its gizmo is on.
  Set<TransformMode> get transformModesAvailable {
    if (!isAuthoring.value) return TransformModes.none;
    final session = designer.value;
    if (session != null) {
      if (session.controller.toolId.value == TileTools.select) {
        return scope.tiles.selection.value.isEmpty
            ? TransformModes.none
            : TransformModes.tiles;
      }
      return TransformModes.forEntities(
        engine.world,
        session.selectionEntities(),
      );
    }
    // A piece of a map turns its tiles, which only the designer does.
    final selected = sceneState.selectedEntity.value;
    return selected == null
        ? TransformModes.none
        : TransformModes.forEntities(engine.world, [
            selected,
          ], turnsPieces: false);
  }

  /// Whether the gizmos are in hand: always in the editor; in the designer
  /// with the select tool — which All, Move, Scale and Rotate are — or with
  /// Select tiles and tiles selected.
  bool get isTransformToolInHand {
    final session = designer.value;
    if (session == null) return true;
    final tool = session.controller.toolId.value;
    return tool == BuiltInTools.select ||
        (tool == TileTools.select && scope.tiles.selection.value.isNotEmpty);
  }

  /// The gizmo the selection shows: the mode chosen when it can take it,
  /// else Move; null when nothing selected can take any.
  TransformMode? get shownTransformMode => TransformModes.shown(
    scope.view.transformMode.value,
    transformModesAvailable,
  );

  /// Picks Move, Scale or Rotate — the toolbar's buttons, W, E and R. In
  /// the designer the select tool comes with it, whose gizmos they are.
  void chooseTransformMode(TransformMode mode) {
    scope.view.transformMode.value = mode;
    if (isAuthoring.value) designer.value?.adoptTransformMode();
  }

  /// Whether only the Level Map can be worked on: the Level Designer is
  /// open on a 2-D scene and building, not play-testing, and no workspace
  /// — the tileset or interface editor, which work on things off the map —
  /// is open over it. A 3-D scene has no Level Map: its designer works on
  /// the whole scene.
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

  /// Opens the Level Designer, creating its session if needed.
  void openLevelDesigner() {
    if (designer.value != null || !sceneState.hasScene) return;
    designer.value = LevelDesignerSession(
      scope: scope,
      uniqueName: entities.uniqueName.call,
      camera: () => scope.editorView,
      splitViews: () => splitViews,
      onDuplicate: duplicateSelection,
      onDelete: deleteSelection,
      onArray: (count, step) => arraySelection(count: count, step: step),
      onArray3D: arraySelection3D,
    )..restoreEditorData(sceneIO.editorData);
    // Its panel is a tab of the right panel: the one to see on opening.
    scope.chrome.rightPanelTab.value = EditorChromeState.levelTab;
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
    // The engine may already be gone: an app closing disposes it first.
    if (!engine.isInitialized) return;
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
    if (scope.view.isHiddenIn(entity)) return false;
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
    scope.chrome.rightPanelTab.value = EditorChromeState.inspectorTab;
    _updateRenderFilter();
    session.dispose();
  }

  /// Toggles the Level Designer workspace.
  void toggleLevelDesigner() =>
      isLevelDesignerOpen ? closeLevelDesigner() : openLevelDesigner();

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

  bool _onHardwareKey(KeyEvent event) {
    if (!_isInitialized) return false;
    // A chord being bound in the settings: every key is for that.
    if (scope.chrome.capturingKeys) return false;
    // Flying (right button held in 3-D): the movement keys steer, and are
    // no shortcuts meanwhile.
    if (viewport.isLooking && _flyKeys.contains(event.logicalKey)) {
      return true;
    }
    // A scene opening: the editor waits for it, and Esc stops waiting on
    // its assets. The toggle key still hides the editor; a key let go
    // still reaches whatever saw it pressed.
    if (isVisible.value &&
        sceneIO.loading.isLoading &&
        event is! KeyUpEvent &&
        event.logicalKey != _toggleKey) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        sceneIO.loading.skip();
      }
      return true;
    }
    // Holding a key keeps nudging; nothing else acts on a repeat.
    if (event is KeyRepeatEvent) {
      if (EditorKeyClaim.focusedClaims(event)) return false;
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
    // A 3-D gizmo being dragged takes a typed value: digits, Enter, Esc.
    if (viewport.isDragging && viewport.typeKey(key)) return true;

    if (key == _toggleKey) {
      toggleVisibility();
      return true;
    }
    // The settings dialog is modal: Esc or its own chord shuts it, and every
    // other key is the dialog's — typing in its search must not pick a tool
    // or delete the selection behind it.
    final settingsOpen = scope.chrome.settingsOpen;
    if (settingsOpen.value) {
      final modifiers = ModifierKeys.fromHardwareKeyboard();
      if (key == LogicalKeyboardKey.escape ||
          scope.commands
              .bindingsFor(EditorSettingsDialog.commandId)
              .any((b) => b.matches(key, modifiers))) {
        settingsOpen.value = false;
        return true;
      }
      return false;
    }
    // A focused panel that keeps a key for itself — the Scenes list's F2
    // renames, its Delete deletes a scene — has it.
    if (EditorKeyClaim.focusedClaims(event)) return false;
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
      host: this,
      modifiers: ModifierKeys.fromHardwareKeyboard(),
      gridSize: gridSize.value,
    );
    final commands = scope.commands;
    // Save works even from inside a text field — with what was typed there,
    // kept first as leaving the field would keep it, not the value before.
    if (commands.resolve(key, context.modifiers)?.scope ==
        CommandScope.always) {
      PendingFieldEdits.flush();
    }
    if (commands.dispatch(key, context, scopes: const {CommandScope.always})) {
      return true;
    }
    // Everything below means something else in a text field: Delete,
    // Ctrl+C, Ctrl+Z, every single-letter tool key. A HardwareKeyboard
    // handler sees keys before the focused widget does.
    if (_isTypingInTextField) return false;
    // A collider being edited: Esc finishes, Delete takes a point away.
    if (isAuthoring.value && ColliderEditSession.of(scope).handleKey(key)) {
      return true;
    }
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
  /// What they are not in comes from the engine's own loaders.
  late final FileSpriteAssetLoader spriteAssets = FileSpriteAssetLoader(
    context: engine.context,
  );

  /// What [onInitialize] pointed the engine's loaders at, to put back.
  LoaderOverride? _loaders;

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
    '.tileset.json',
    LevelMapFiles.suffix,
    LevelMapFiles.legacySuffix,
    '/scenes.json',
    '/palettes.json',
  ];

  /// Whether [path] is a sprite atlas: a `.json` that is none of the
  /// editor's other data files.
  static bool isSpriteAtlasPath(String path) {
    final p = path.toLowerCase().replaceAll('\\', '/');
    if (!p.endsWith('.json') || p == 'scenes.json') return false;
    return !dataJsonSuffixes.any(p.endsWith) &&
        !ModuleDataFiles.suffixes.any(p.endsWith);
  }

  /// Whether dropping [path] on the viewport of a scene of [mode] makes
  /// something: a kind a module knows how to drop (a model); in 2-D also
  /// an image, a sprite project, a sprite atlas, a tileset or a map.
  static bool canDropAsset(String path, {SceneMode mode = SceneMode.twoD}) {
    if (AssetKind.of(path).drop != null) return true;
    // Sprites and tile maps are 2-D: a 3-D scene does not draw them.
    if (mode != SceneMode.twoD) return false;
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
    if (!sceneState.hasScene ||
        !canDropAsset(path, mode: sceneState.editingMode)) {
      return null;
    }
    final at = engine.cameraSystem.mainCamera.screenToWorld(canvasPosition);
    final view = scope.editorView;
    // In space a sprite stands where the pointer meets the ground; a model
    // on the surface under it.
    final ground = view.isPlanar ? null : view.screenToGround(canvasPosition);
    final surface = view.isPlanar ? null : surfaceAt(canvasPosition);
    // A kind a module knows makes what it makes.
    if (AssetKind.of(path).drop case final drop?) {
      return drop(
        AssetDrop(
          scope: scope,
          path: path,
          at: surface?.position ?? Vector3(at.dx, at.dy, 0),
          surface: surface,
          place: (components, name) => _place(path, components, name: name),
        ),
      );
    }
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
      TransformComponent(
        position: ground ?? Vector3(at.dx, at.dy, 0),
      ),
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
    final tileSize = engine.context.tiles.loadedTileset(path)?.tileWidth;
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
    } else if (lower.endsWith('.tileset.json') ||
        LevelMapFiles.isMapFile(lower) ||
        lower.endsWith('.tmx') ||
        lower.endsWith('.tmj') ||
        lower.endsWith('.tsx') ||
        lower.endsWith('.tsj')) {
      reloadLevelMaps(path);
    } else if (isSpriteAtlasPath(path)) {
      reloadSprites(path);
    } else if (PrefabFile.isPrefabPath(lower)) {
      unawaited(scope.prefabInstances.refresh(path));
    } else if (lower.endsWith('.json')) {
      // Some other data file: nothing a sprite shows.
    } else if (!_isFont(lower) && !_isAudio(lower)) {
      reloadSprites();
    }
    // And whatever a module shows from it — a theme, a font, a screen.
    for (final module in scope.modules.all) {
      module.onAssetChanged(path);
    }
  }

  /// Many files changed at once — a package installed, updated or removed:
  /// each kind is reloaded once, not once per file.
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
      } else if (isSpriteAtlasPath(path)) {
        sprites = true;
      } else if (PrefabFile.isPrefabPath(lower)) {
        unawaited(scope.prefabInstances.refresh(path));
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
    for (final path in paths) {
      for (final module in scope.modules.all) {
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

  // Systems that must not run on the scene being edited:
  //
  // * A timeline writes to the fields it animates. While authoring those
  //   fields are the scene being edited, so timelines only run in a
  //   play-test (whose changes are thrown away) — the Timeline dock
  //   previews by itself.
  // * Tile collision builds bodies from the maps. While authoring they
  //   would be rebuilt on every stroke for nothing; they are built when
  //   play starts, and destroyed with the play-test.
  // * Sound plays only in a play-test. Authoring, the game's AudioSystem
  //   would start every source on load, and mark it played in the scene
  //   being edited; when a play-test stops, what it played stops with it.
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
      if (system is AudioSystem && system.isActive != run) {
        system.isActive = run;
        if (!run) system.stopAll();
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

  /// Play started or stopped: modules that show something only in a
  /// play-test — the game's screens — follow it.
  bool _modulesThinkPlaying = false;
  void _tellModulesPlayState() {
    final playing = playController.state.value != EditorPlayState.stopped;
    scope.isPlayTesting.value = playing;
    if (playing == _modulesThinkPlaying) return;
    _modulesThinkPlaying = playing;
    for (final module in scope.modules.all) {
      module.onPlayStateChanged(playing);
    }
  }

  void _focusGameOnPlay() {
    if (playController.state.value == EditorPlayState.playing) focusGame();
  }

  /// A press on the play-test's view, which takes the game's presses while
  /// it plays: a game that looks with the mouse
  /// (`input.lockPointerOnClick`) holds it, as it would outside the editor.
  /// Escape, Pause and Stop let go.
  void pressedPlayingGame(PointerDownEvent event) {
    if (playController.state.value != EditorPlayState.playing) return;
    if (event.kind != PointerDeviceKind.mouse ||
        (event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }
    if (engine.isInitialized) engine.input.lockPointerForClick();
  }

  /// Paused or stopped, the editor needs the mouse back.
  void _releasePointerUnlessPlaying() {
    if (playController.state.value == EditorPlayState.playing) return;
    if (engine.isInitialized) unawaited(engine.input.releasePointer());
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
    if (_isInitialized) sceneIO.loading.tick();
    if (_isInitialized) _autosaveTick();
    if (_isInitialized) _syncRuntimeSystems(dt);
    if (_isInitialized) _syncSplit();
    if (_isInitialized) _syncSceneAids();
    if (!_isInitialized || !isVisible.value) return;
    // Right button held in 3-D: WASD flies the view.
    viewport.flyTick(dt, HardwareKeyboard.instance.logicalKeysPressed);
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

  /// What the editor adds to its 3-D views — what it hides, the
  /// selection's outline, the view mode, the slice — handed to the 3-D
  /// renderer while authoring a 3-D scene; taken back otherwise, so a
  /// play-test shows the level as it ships.
  late final g3.SceneEditorAids sceneAids = g3.SceneEditorAids()
    ..plainViews.add(_previewFrame)
    ..drawFilter = _isDrawn
    ..highlighted = () => selectionEntities;

  void _syncSceneAids() {
    if (!engine.isInitialized) return;
    final graphics = engine.services.maybe<g3.Graphics3D>();
    if (graphics == null || !graphics.isStarted) return;
    final renderer = graphics.sceneRenderer;
    if (!isVisible.value ||
        !isAuthoring.value ||
        sceneState.editingMode != SceneMode.threeD) {
      renderer.aids = null;
      return;
    }
    final state = scope.designer3D;
    renderer.aids = sceneAids
      ..viewMode = switch (state.viewMode.value) {
        ViewMode3D.lit => g3.RenderViewMode.lit,
        ViewMode3D.unlit || ViewMode3D.collision => g3.RenderViewMode.unlit,
        ViewMode3D.wireframe => g3.RenderViewMode.wireframe,
      }
      ..highlighted = state.outline.value ? () => selectionEntities : null
      ..sliceY = state.sliceOn.value ? state.sliceY.value : null;
    sceneAids.skippedViews.clear();
    if (activeSplit != null) sceneAids.skippedViews.add(engine.rendering.view);
  }

  /// Switches the 3-D view between perspective and orthographic (pad 5).
  void toggleOrthographic() {
    if (scope.editorView case final OrbitFlyEditorView view) {
      view.orthographic = !view.orthographic;
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
    final split = activeSplit;
    if (split != null) {
      _renderPanes(canvas, size, split);
      return;
    }
    _renderView(canvas, size, preview: true);
  }

  /// The viewport split four ways (top, front, side, perspective) — while
  /// [SplitViews.on], authoring a 3-D scene.
  late final SplitViews splitViews = SplitViews(
    () => scope.sceneView as OrbitFlyEditorView,
  );

  /// [splitViews] while they are what the viewport shows; null otherwise.
  SplitViews? get activeSplit =>
      splitViews.on.value &&
          isAuthoring.value &&
          sceneState.editingMode == SceneMode.threeD &&
          scope.sceneView is OrbitFlyEditorView
      ? splitViews
      : null;

  /// Splits the 3-D viewport four ways, or joins it again.
  void toggleSplitViews() {
    if (sceneState.editingMode != SceneMode.threeD) return;
    splitViews.toggle();
  }

  /// Each pane of [split] in its quarter of the canvas: its own picture of
  /// the scene, and over it the editor's aids seen through it. The game's
  /// camera preview over them all.
  void _renderPanes(Canvas canvas, Size size, SplitViews split) {
    split.layout(size);
    final background = Paint()..color = engine.rendering.backgroundColor;
    canvas.drawRect(Offset.zero & size, Paint()..color = EditorTheme.border);
    for (final pane in split.panes) {
      canvas
        ..save()
        ..clipRect(pane.rect)
        ..translate(pane.rect.left, pane.rect.top);
      scope.throughPane(pane, () {
        final paneSize = pane.rect.size;
        canvas.drawRect(Offset.zero & paneSize, background);
        pane.frame.update(
          pane.view.camera,
          paneSize,
          interpolation: engine.rendering.interpolation,
        );
        for (final renderer in engine.rendering.sceneRenderers) {
          if (renderer.enabled) renderer.render(canvas, pane.frame);
        }
        _renderView(canvas, paneSize, preview: false);
      });
      _paintPaneLabel(canvas, pane, active: identical(pane, split.active));
      canvas.restore();
    }
    _paintGamePreview(canvas, size, engine.cameraSystem.mainCamera);
  }

  /// What has been typed during a gizmo drag, beside the gizmo.
  void _paintTyped(Canvas canvas, Offset at, String text) {
    final label = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: EditorTheme.textBright,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromLTWH(at.dx + 16, at.dy + 16, label.width + 12, label.height + 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()..color = EditorTheme.panelBg.withValues(alpha: 0.9),
    );
    label.paint(canvas, box.topLeft + const Offset(6, 3));
  }

  void _paintPaneLabel(Canvas canvas, ViewPane pane, {required bool active}) {
    final label = TextPainter(
      text: TextSpan(
        text: pane.kind.label,
        style: TextStyle(
          color: active ? EditorTheme.primary : EditorTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(8, 6));
    if (active) {
      canvas.drawRect(
        (Offset.zero & pane.rect.size).deflate(0.5),
        Paint()
          ..color = EditorTheme.primary.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke,
      );
    }
  }

  // ── The pointer, through the pane it is over ─────────────────────────

  /// Runs [handle] with [event] as [pane] sees it: its position in the
  /// pane, the pane's view as the editor's, the canvas the pane's size.
  T _inPane<T>(ViewPane pane, PointerEvent event, T Function(PointerEvent) handle) {
    final shift = Matrix4.translationValues(-pane.rect.left, -pane.rect.top, 0);
    final local = event.transformed(
      event.transform == null ? shift : (shift..multiply(event.transform!)),
    );
    final canvas = viewport.canvasSize;
    viewport.updateCanvasSize(pane.rect.size);
    _inPaneDepth++;
    try {
      return scope.throughPane(pane, () => handle(local));
    } finally {
      _inPaneDepth--;
      viewport.updateCanvasSize(canvas);
    }
  }

  int _inPaneDepth = 0;

  /// Between gestures the editor's view is the pane last used, so a key —
  /// F, the pad's views, flying — works in it; with no split, its own.
  void _syncSplit() {
    final split = activeSplit;
    final pane = split?.active ?? split?.panes.last;
    scope.viewOverride = pane?.view;
  }

  /// Runs [handle] with [event] in the pane it belongs to: the one it went
  /// down in, while a gesture lasts, else the one under it. Without a
  /// split, as it is.
  T _routed<T>(
    PointerEvent event,
    T Function(PointerEvent) handle,
    T outside, {
    bool begins = false,
  }) {
    final split = activeSplit;
    if (split == null) return handle(event);
    final pane = begins || split.active == null
        ? split.paneAt(event.localPosition)
        : split.active;
    if (pane == null) return outside;
    split.active = pane;
    return _inPane(pane, event, handle);
  }

  /// A press on the canvas, sent on to the viewport through its pane.
  bool pointerDown(PointerDownEvent event) => _routed(
    event,
    (e) => viewport.onPointerDown(e as PointerDownEvent),
    false,
    begins: true,
  );

  /// The pointer moving with no button down.
  void pointerHover(PointerHoverEvent event) => _routed(
    event,
    (e) => viewport.onPointerHover(e as PointerHoverEvent),
    null,
    begins: true,
  );

  /// The pointer moving with a button down.
  void pointerMove(PointerMoveEvent event) =>
      _routed(event, (e) => viewport.onPointerMove(e as PointerMoveEvent), null);

  /// A press let go.
  void pointerUp(PointerUpEvent event) =>
      _routed(event, (e) => viewport.onPointerUp(e as PointerUpEvent), null);

  /// A gesture cut short.
  void pointerCancel(PointerCancelEvent event) => _routed(
    event,
    (e) => viewport.onPointerCancel(e as PointerCancelEvent),
    null,
  );

  /// The wheel.
  void pointerScroll(PointerSignalEvent event) => _routed(
    event,
    (e) => viewport.onPointerScroll(e as PointerSignalEvent),
    null,
    begins: true,
  );

  /// Runs [body] with [local] (canvas pixels) as the pane under it sees
  /// it, that pane's view the editor's: what the right-click menu asks.
  T atPoint<T>(Offset local, T Function(Offset local) body) {
    final split = activeSplit;
    // Already in a pane: a menu opened from a gesture there.
    if (split == null || _inPaneDepth > 0) return body(local);
    final pane = split.paneAt(local) ?? split.panes.last;
    final canvas = viewport.canvasSize;
    viewport.updateCanvasSize(pane.rect.size);
    try {
      return scope.throughPane(
        pane,
        () => body(local - pane.rect.topLeft),
      );
    } finally {
      viewport.updateCanvasSize(canvas);
    }
  }

  void _renderView(Canvas canvas, Size size, {required bool preview}) {
    final camera = scope.editorView..viewportSize = size;
    // In space (a 3-D scene) the 2-D aids — the pixel grid, camera rigs,
    // collider outlines — have nothing to say; the ground grid and the
    // 3-D gizmo take their place.
    final flat = camera.isPlanar;

    if (isGridVisible.value) {
      if (flat) {
        scope.grid.paintGrid(canvas, camera, size, cellSize: gridSize.value);
      } else {
        // On the plane the 3-D designer builds on — the ground, unless it
        // was moved or turned — in the move step.
        paintPlaneGrid(
          canvas,
          camera,
          plane: designer.value?.workingPlane ?? scope.designer3D.plane,
          step: sceneState.moveStep3D,
        );
      }
    }

    // Between the grid and the gizmos: level overlays sit above the grid so
    // they read as part of the level, and below the gizmo handles so those
    // stay visible and grabbable on top of everything.
    designer.value?.paint(canvas, size, camera);

    // The designer draws the camera rigs as one of its overlays; with it
    // closed the base editor draws them itself.
    if (flat && designer.value == null && isAuthoring.value) {
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

    // Cameras, spawn points and whatever else a module marks.
    for (final marker in scope.markers) {
      final where = marker.where;
      _gizmoPainter.paintMarkers(
        canvas,
        marker,
        [
          for (final e in engine.world.query([
            TransformComponent,
            ...marker.components,
          ]))
            if (_isDrawn(e) && (where == null || where(e))) e,
        ],
        camera,
        size,
      );
    }

    // What the modules draw over the level: a light's reach, a frustum.
    if (isAuthoring.value && scope.viewportOverlays.isNotEmpty) {
      final hidden = scope.hiddenOverlays.value;
      final overlayContext = ViewportOverlayContext(
        canvas: canvas,
        size: size,
        view: camera,
        scope: scope,
        isShown: _isDrawn,
      );
      final collisionView =
          !flat && scope.designer3D.viewMode.value == ViewMode3D.collision;
      for (final overlay in scope.viewportOverlays) {
        if (hidden.contains(overlay.id) &&
            !(collisionView && overlay is ColliderOverlay3D)) {
          continue;
        }
        if (!overlay.dimensions.allows(sceneState.editingMode)) continue;
        overlay.paint(overlayContext);
      }
    }

    // The points of the selection that can be dragged.
    final handles = selectionHandles;
    if (handles.isNotEmpty) {
      paintViewportHandles(
        canvas,
        handles,
        camera.isPlanar
            ? (p) => camera.worldToScreen(Offset(p.x, p.y))
            : camera.projectToScreen,
        activeIndex: viewport.handleDrags?.activeIndex ?? -1,
      );
    }

    final highlighted = scope.highlightedTag.value;
    if (highlighted != null) {
      final world = engine.world;
      _gizmoPainter.paintTagHighlight(
        canvas,
        [
          ...world.allTagged(highlighted).where(_isDrawn),
          // Where something with the tag will be once the game spawns it.
          for (final spawner in scope.tags.spawnersGiving(highlighted))
            ...SpawnPoints.of(world, spawner.id).where(_isDrawn),
        ],
        highlighted,
        scope.tags.colorOf(highlighted),
        camera,
        size,
      );
    }

    final layer = scope.highlightedLayer.value;
    if (layer != null) {
      final layers = scope.physicsLayers.value;
      _gizmoPainter.paintHighlight(
        canvas,
        [
          for (final e in PhysicsBodies.byLayer(engine.world, scope.definitions)[layer])
            if (_isDrawn(e)) e,
        ],
        layers.labelOf(layer),
        layers.colorOf(layer),
        camera,
        size,
      );
    }

    // A collider being edited, over everything in the level.
    final collider = ColliderEditSession.of(scope);
    if (flat && isAuthoring.value) collider.paint(canvas, camera);

    if (preview) _paintGamePreview(canvas, size, engine.cameraSystem.mainCamera);

    final selected = sceneState.selectedEntity.value;
    if (selected == null || !selected.isActive) return;
    // Its handles are the ones to take hold of: no gizmo over them.
    if (collider.isEditing(selected)) return;
    // The 2-D designer's select tool draws its own resize and rotate
    // handles, and claims every press — the base gizmo would be a second set
    // of handles that cannot be grabbed. The 3-D one leaves the gizmo be.
    if (flat &&
        designer.value?.controller.toolId.value == BuiltInTools.select &&
        isAuthoring.value) {
      return;
    }
    final mode = shownTransformMode;
    if (mode == null) return;
    if (!flat) {
      final gizmo = Gizmo3D.of(
        selected,
        camera,
        local: sceneState.localGizmo,
        pivot: viewport.gizmoPivot(),
      );
      if (gizmo != null) {
        paintGizmo3D(canvas, gizmo, mode: mode, active: viewport.activeHandle);
        final typed = viewport.typedLabel;
        if (typed != null) _paintTyped(canvas, gizmo.origin, typed);
      }
      return;
    }
    _gizmoPainter.paintGizmos(
      canvas,
      selected,
      camera,
      size,
      mode: mode,
      allows: transformModesAvailable,
    );
  }

  /// The preview's top-left corner on the canvas. The chrome publishes it on
  /// every layout, so the preview hangs directly below the play controls
  /// wherever they are.
  Offset gamePreviewOrigin = const Offset(16, 56);

  /// How much of the canvas's foot the preview must stay clear of — the
  /// settings gear, and while designing the minimap standing on it. The
  /// chrome publishes it with the origin.
  double gamePreviewBottomReserve = 0;

  /// How the preview's panel is drawn. The chrome publishes it with the
  /// origin, from the same settings the play toolbar is drawn with, so the
  /// two read as one piece of UI.
  GamePreviewStyle gamePreviewStyle = const GamePreviewStyle();

  /// Height of the preview panel's header row: the LIVE chip and camera name.
  static const double gamePreviewHeaderHeight = 22;

  /// The whole preview **panel** on a canvas of [canvasSize], with its corner
  /// at [origin]: a fraction of the canvas wide, and as tall as its header
  /// plus a game view of the game's own aspect.
  ///
  /// On a canvas too short for that above [bottomReserve], it is narrower —
  /// the same shape, smaller — rather than run into what is at the foot.
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
  // The preview's own view, kept so a 3-D backend keeps one surface for it.
  final FrameView _previewFrame = FrameView();

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
      bottomReserve: gamePreviewBottomReserve,
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
          ..color = style.borderColor ?? EditorTheme.accent,
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
      // A 3-D backend's image first, as the game draws it.
      final renderers = engine.rendering.sceneRenderers;
      if (renderers.isNotEmpty) {
        final frame = _previewFrame
          ..update(
            camera,
            size,
            interpolation: engine.rendering.interpolation,
          );
        for (final renderer in renderers) {
          if (renderer.enabled) renderer.render(canvas, frame);
        }
      }
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
            TextStyle(
              color: EditorTheme.textMuted,
              fontSize: 9,
              fontStyle: FontStyle.italic,
            ),
            row.width,
          )
        : null;
    final label = text(
      name,
      TextStyle(
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
  void focusOn(Entity entity) {
    if (entity.hasComponent<LevelMapComponent>()) {
      designLevelMap(entity);
      return;
    }
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) {
      sceneState.selectEntity(entity);
      return;
    }
    if (scope.editorView case final OrbitFlyEditorView view) {
      // In space: around it, far enough back to see all of it.
      final box = Aabb3();
      if (RayEntityPicker.boundsOf(entity, box)) view.focusOn(box);
      sceneState.selectEntity(entity);
      return;
    }
    engine.cameraSystem.mainCamera.position = Offset(
      transform.position.x,
      transform.position.y,
    );
    sceneState.selectEntity(entity);
  }

  /// In 3-D: the surface under [canvasPosition] — the nearest drawn
  /// entity's, by its real shape where a pick test knows it, else the
  /// working plane, else the ground — where something placed there goes.
  SurfacePoint surfaceAt(Offset canvasPosition) {
    final view = scope.editorView;
    final found = RayEntityPicker(tests: () => scope.pickTests).placementAt(
      view,
      canvasPosition,
      engine.world.entities.where(_isDrawn),
    );
    if (found.onto != null) return found;
    final plane = workingPlane3D;
    final hit = plane.intersect(view.screenToRay(canvasPosition));
    return hit == null ? found : SurfacePoint(hit, plane.normal);
  }

  /// The 3-D designer's working plane: as set, or through the base of the
  /// selection while it follows it.
  WorkingPlane get workingPlane3D {
    final state = scope.designer3D;
    return state.followSelection.value
        ? state.planeAt(selectionEntities)
        : state.plane;
  }

  /// Drops everything selected straight down onto what is under it (or
  /// the working plane), as one undo step. How many moved.
  int dropSelectionToGround() {
    final picker = RayEntityPicker(tests: () => scope.pickTests);
    return entities.dropSelectionToGround(
      below: (ray, ignore) => picker.placementAlong(
        ray,
        engine.world.entities.where((e) => _isDrawn(e) && !ignore.contains(e)),
      ),
      plane: workingPlane3D,
    );
  }

  /// Copies the selection as [spec] lays them out, about the gizmo's
  /// pivot, as one undo step.
  void arraySelection3D(Array3DSpec spec) => entities.arraySelection3D(
    history,
    spec,
    SelectionPivot.of(selectionEntities, scope.designer3D.pivotMode.value),
  );

  /// The prefabs a 3-D scene can be given from the viewport menu: the
  /// built-in ones and every module's that place in 3-D, whichever kit the
  /// Level Designer has chosen, then each variant of those it applies to
  /// (a Solid of every shape).
  List<PrefabDefinition> get prefabsInSpace {
    final base = [
      for (final module in scope.modules.withBuiltIns)
        for (final prefab in [...module.prefabs, ...module.sharedPrefabs])
          if (prefab.dimensions.allows(SceneMode.threeD)) prefab,
    ];
    return [
      ...base,
      for (final variant in scope.prefabVariants)
        for (final prefab in base)
          if (variant.offersFor(prefab)) variant.of(prefab),
    ];
  }

  /// The points the selected entity lets the author drag, while authoring
  /// with one entity selected: what the modules' [ViewportHandles] offer.
  List<ViewportHandle> get selectionHandles {
    if (!isAuthoring.value || sceneState.hasMultiSelection) return const [];
    final entity = sceneState.selectedEntity.value;
    if (entity == null || !entity.isAlive) return const [];
    final mode = sceneState.editingMode;
    return [
      for (final provider in scope.viewportHandles)
        if (provider.dimensions.allows(mode)) ...provider.handlesOf(entity, scope),
    ];
  }

  /// Places [prefab] at [at], selected, as one undo step.
  Entity placePrefab(PrefabDefinition prefab, SurfacePoint at) =>
      entities.placePrefab(prefab, at);

  /// In 3-D: frames the selection — or, with [all] or nothing selected,
  /// everything drawn.
  void frameInSpace({bool all = false}) {
    final view = scope.editorView;
    if (view is! OrbitFlyEditorView) return;
    final box = Aabb3(), one = Aabb3();
    final picked = all ? const <Entity>[] : selectionEntities;
    for (final e in picked.isEmpty
        ? engine.world.entities.where(_isDrawn)
        : picked) {
      if (RayEntityPicker.boundsOf(e, one)) box.addBox(one);
    }
    view.focusOn(box);
  }

  /// In 3-D: looks along an axis ([yaw], [pitch] in radians), turning about
  /// the point the view pivots on.
  void viewAlong({required double yaw, required double pitch}) {
    if (scope.editorView case final OrbitFlyEditorView view) {
      view.viewFrom(yaw: yaw, pitch: pitch);
    }
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

  /// Asks whether to open [sceneName] from a backup of changes that were
  /// never saved, made at [when]: true recovers them, false opens the file
  /// and sets the backup aside, null opens the file and asks again next
  /// time. Set by the overlay, which has somewhere to ask; without it the
  /// file opens.
  Future<bool?> Function(String sceneName, DateTime when)? askToRecover;

  /// Opens [sceneName] through [sceneIO], closing the Level Designer first:
  /// its undo commands hold entities of the scene being left, and it reopens
  /// cleanly on the new one. A backup with changes never saved is offered
  /// first.
  Future<void> openScene(String sceneName) async {
    if (sceneIO.isBusy) return;
    final wasDesignerOpen = isLevelDesignerOpen;
    Map<String, dynamic>? recovered;
    final ask = askToRecover;
    final backup = ask == null ? null : scope.scenes.unsavedBackupOf(sceneName);
    if (ask != null && backup != null) {
      final recover = await ask(sceneName, backup.lastModifiedSync());
      if (recover == true) {
        recovered = await scope.scenes.readBackup(backup);
      } else if (recover == false) {
        await scope.scenes.setAside(backup);
      }
    }
    closeLevelDesigner();
    final assets = _countSceneAssets();
    final opened = recovered != null
        ? await sceneIO.openFrom(sceneName, recovered, assets: assets)
        : await sceneIO.open(sceneName, assets: assets);
    if (!opened) return;
    if (wasDesignerOpen) openLevelDesigner();
  }

  /// Counts what the scene about to open asks to load, for the loader:
  /// sprites, atlases, tile maps and the rest read through [spriteAssets],
  /// and 3-D models. What was loading before it is left out.
  AssetTally Function() _countSceneAssets() {
    final files = spriteAssets.loads..restart();
    final models = <String>{};
    return () {
      var done = files.finished;
      var total = files.started;
      final graphics = engine.graphics3D;
      if (graphics != null && graphics.isStarted) {
        final cache = graphics.models;
        bool arrived(String path) =>
            cache.errorOf(path) != null || cache.get(path) != null;
        // The cache keeps the last scene's models too: a model is this
        // scene's once it is seen loading. The renderer asks for them as
        // it draws, so after the open.
        for (final path in List.of(cache.paths)) {
          if (!arrived(path)) models.add(path);
        }
        total += models.length;
        done += models.where(arrived).length;
      }
      return (done: done, total: total);
    };
  }

  // ── Autosave ───────────────────────────────────────────────────────────

  DateTime? _nextAutosave;
  bool _autosaving = false;

  /// Autosaves when the settings' interval has gone by. Timed by the clock
  /// on each update rather than a timer: nothing to cancel, and nothing
  /// runs while the editor is not.
  void _autosaveTick() {
    final interval = scope.prefs.settings.value.autosaveInterval;
    if (interval == null) {
      _nextAutosave = null;
      return;
    }
    final now = DateTime.now();
    final due = _nextAutosave ??= now.add(interval);
    if (now.isBefore(due)) return;
    _nextAutosave = now.add(interval);
    unawaited(autosave());
  }

  /// Autosaves the open scene as the settings say — a backup, or the scene
  /// saved — if it has unsaved changes. Waits, returning false, while a
  /// timeline preview shows or an open or save is under way. True when
  /// something was written.
  Future<bool> autosave() async {
    if (_autosaving ||
        !sceneState.hasScene ||
        !sceneState.isDirty.value ||
        sceneIO.isBusy ||
        scope.isAuthoredStateHeld) {
      return false;
    }
    _autosaving = true;
    try {
      final settings = scope.prefs.settings.value;
      if (settings.autosaveMode == AutosaveMode.save) {
        await saveScene();
        return true;
      }
      return await sceneIO.backup(
        asAuthored: playController.snapshot?.entities,
        editorData: designer.value?.editorData() ?? sceneIO.editorData,
        keep: settings.backupsToKeep,
      );
    } catch (error) {
      scope.log.log(
        'Autosave failed: $error',
        source: 'editor',
        category: 'scene',
        level: DebuggerLogLevel.warning,
      );
      return false;
    } finally {
      _autosaving = false;
    }
  }

  // ── Where the session is left ──────────────────────────────────────────

  static final SettingPref<String> _lastScenePref = SettingPref.text(
    OverlaySettingsPrefKeys.sessionLastScene,
    '',
  );
  static final SettingPref<bool> _designerOpenPref = SettingPref.boolean(
    OverlaySettingsPrefKeys.sessionDesignerOpen,
    false,
  );

  void _rememberScene() {
    final name = sceneState.activeScene.value?.name ?? '';
    unawaited(scope.prefs.set(_lastScenePref, name));
    // The Scenes list's Recent, and the start card's Reopen.
    if (name.isNotEmpty) unawaited(RecentScenes.touch(scope.prefs, name));
  }

  // Opening another scene shuts the designer and opens it again: it ends
  // as it was, and so does what is remembered.
  void _rememberDesigner() =>
      unawaited(scope.prefs.set(_designerOpenPref, isLevelDesignerOpen));

  bool _reopened = false;

  /// Opens the scene that was open when the editor was last closed — and
  /// the Level Designer, if it was open on it — as the settings ask. Once,
  /// after the settings are loaded, and only with no scene open yet.
  Future<void> reopenLastSession() async {
    if (_reopened) return;
    _reopened = true;
    final settings = scope.prefs.settings.value;
    if (!settings.reopenLastScene || sceneState.hasScene) return;
    final name = scope.prefs.get(_lastScenePref);
    final designerWasOpen = scope.prefs.get(_designerOpenPref);
    if (name.isEmpty || !scope.scenes.listSceneNames().contains(name)) return;
    await openScene(name);
    if (settings.reopenDesigner &&
        designerWasOpen &&
        sceneState.activeScene.value?.name == name &&
        !isLevelDesignerOpen) {
      openLevelDesigner();
    }
  }

  // ── Settings the plugin follows ────────────────────────────────────────

  final List<void Function()> _stopFollowing = [];

  void _followSettings() {
    ViewportLook.apply(scope.prefs.settings.value);
    _syncBackdrop();
    _syncDesignerSnap();
  }

  /// The designer's Snap and Smart are the settings': one switch, wherever
  /// it is flipped — the magnet over the viewport, the Settings, or the
  /// designer's own status bar.
  void _syncDesignerSnap() {
    final controller = designer.value?.controller;
    if (controller == null) return;
    final settings = scope.prefs.settings.value;
    controller.snapEnabled.value = settings.gridSnappingEnabled;
    controller.smartSnap.value = settings.smartSnap;
  }

  /// A logged error pauses a running play-test, when the settings ask.
  void _pauseOnError() {
    if (!scope.prefs.settings.value.pauseOnError) return;
    if (playController.state.value != EditorPlayState.playing) return;
    // Not from inside the log call that brought it.
    scheduleMicrotask(() {
      if (playController.state.value != EditorPlayState.playing) return;
      playController.pause();
      logService.log(
        'Paused the play-test: an error was logged.',
        source: 'editor',
        category: 'play',
        level: DebuggerLogLevel.warning,
      );
    });
  }

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

  /// Starts the play-test with the player at [at] instead of its spawn
  /// point — placed by the game kit that knows its player
  /// (`LevelAids.playFrom`), else whatever carries the `player` tag.
  /// Whether it was placed; nothing when a play-test is on already.
  bool playFrom(Vector3 at) {
    if (!_isInitialized ||
        playController.state.value != EditorPlayState.stopped) {
      return false;
    }
    playController.play();
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

  bool get view3D => !scope.editorView.isPlanar;

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
    _presence?.stop();
    _presence = null;
    for (final stop in _stopFollowing) {
      stop();
    }
    isAuthoring.removeListener(_syncBackdrop);
    if (_gameBackdrop != null && engine.isInitialized) {
      engine.rendering.backgroundColor = _gameBackdrop!;
      _gameBackdrop = null;
    }
    closeLevelDesigner();
    isAuthoring.removeListener(_syncCameraOwnership);
    keepsToLevelMap.removeListener(_syncLevelMapFocus);
    playController.state.removeListener(_focusGameOnPlay);
    playController.state.removeListener(_tellModulesPlayState);
    playController.state.removeListener(_releasePointerUnlessPlaying);
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
    this.borderColor,
    this.padding = 5,
  });

  /// Corner radius of the panel — the toolbar's.
  final double cornerRadius;

  /// Border colour — the overlay's theme colour, as on the toolbar.
  final Color? borderColor;

  /// Space between the panel's edge and what is in it.
  final double padding;
}
