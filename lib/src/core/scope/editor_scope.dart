import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:just_di/just_di.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_signals/just_signals.dart';

import '../validation/scene_validator.dart';
import '../colours/project_colours.dart';
import '../../extension/editor_module.dart';
import '../../ui/level_designer/state/built_in_prefabs.dart';
import '../../ui/level_designer/state/layer_preset.dart';
import '../../ui/level_designer/state/prefab_registry.dart';
import '../../ui/inspector/built_in_extras.dart';
import '../../ui/inspector/physics/physics_body_extras.dart';
import '../../ui/inspector/built_in_field_editors.dart';
import '../../ui/inspector/component_extras.dart';
import '../../ui/inspector/field_editor.dart';
import '../../ui/level_designer/commands/built_in_bindings.dart';
import '../../ui/level_designer/commands/built_in_commands.dart';
import '../../ui/level_designer/commands/designer_command.dart';
import '../../ui/level_designer/state/editor_history.dart';
import '../../extension/designer_contributions.dart';
import '../../extension/editor_contributions.dart';
import '../../ui/overlay/chrome_state.dart';
import '../../ui/overlay/docks/dock_controller.dart';
import '../../ui/overlay/settings/overlay_settings_store.dart';
import '../prefs/editor_prefs.dart';
import '../theme/theme_controller.dart';
import '../../ui/level_designer/grid/grid_topology.dart';
import '../../ui/level_designer/grid/square_grid.dart';
import '../../ui/level_designer/state/designer_config.dart';
import '../../ui/level_designer/state/selection_handle_layout.dart';
import '../serialization/scene_codec.dart';
import '../serialization/scene_store.dart';
import '../services/editor_log_service.dart';
import '../physics/project_physics_layers.dart';
import '../tags/project_tags.dart';
import '../tags/tag_references.dart';
import '../state/editor_scene_state.dart';
import '../../extension/built_in_row_decorations.dart';
import '../../extension/built_in_tag_contributions.dart';
import '../entity/entity_ops.dart';
import '../state/editor_view_state.dart';
import '../level_map/tile_edit_state.dart';
import '../level_map/level_map_documents.dart';
import '../level_map/level_map_provision.dart';
import '../../ui/tileset/built_in_workspaces.dart';
import '../../extension/built_in_camera_contributions.dart';
import '../../extension/built_in_physics_3d_contributions.dart';
import '../../extension/tiled_object_mapper.dart';
import '../../extension/built_in_tile_contributions.dart';
import '../view/editor_view.dart';
import '../view/orbit_fly_editor_view.dart';
import '../view/ray_entity_picker.dart';
import '../../extension/asset_kind.dart';
import '../../extension/editor_marker.dart';
import '../../extension/prefab_variant.dart';
import '../../extension/viewport_handles.dart';
import '../../extension/viewport_overlay.dart';

/// Everything one editor owns: its registries, services and state, in a
/// `just_di` container that is disposed with it.
///
/// There are no process-wide registries. Two scopes in one process — two
/// tests, or two editors side by side — share nothing. Component definitions
/// come from the edited engine's [context] (a bare world's own context in a
/// test), which the *game* fills at boot through its extensions; the scope
/// reads them from there, so the editor and the game cannot disagree.
///
/// ```dart
/// final scope = EditorScope(engine: engine, modules: [PlatformerModule()]);
/// ```
///
/// A test that needs no engine passes a bare [world] instead.
class EditorScope {
  EditorScope({
    Engine? engine,
    World? world,
    List<EditorModule> modules = const [],
    DiContainer? parent,
    EditorLogService? log,
    String? scenesRoot,
    DesignerConfig config = const DesignerConfig(),
    OverlaySettingsStore? settingsStore,
    SelectionHandleLayout handles = const SelectionHandleLayout(),
    bool? isDebug,
  }) : assert(engine != null || world != null, 'Pass an engine or a world'),
       engine = engine,
       _world = world,
       container = DiContainer(parent: parent),
       _isDebug = isDebug ?? kDebugMode {
    final defs = (engine?.context ?? world!.context).definitions;
    if (engine != null) container.registerSingleton<Engine>(engine);
    container
      ..registerSingleton<ComponentDefinitionRegistry>(defs)
      ..registerSingleton<DesignerConfig>(config)
      ..registerSingleton<SelectionHandleLayout>(handles)
      ..registerLazySingleton<CommandRegistry>(CommandRegistry.new)
      ..registerLazySingleton<EditorPrefs>(
        () => EditorPrefs(
          // A store that cannot be reached — no platform to ask where, in a
          // test — is reported where it is read, not as an error no one
          // handled the moment the scope is made.
          store:
              settingsStore ??
              OverlaySettingsStore(JustStorage.standard()..ignore()),
        ),
        dispose: (p) => p.dispose(),
      )
      ..registerLazySingleton<ThemeController>(
        ThemeController.new,
        dispose: (t) => t.dispose(),
      )
      ..registerLazySingleton<DockController>(
        DockController.new,
        dispose: (d) => d.dispose(),
      )
      ..registerLazySingleton<EditorChromeState>(
        EditorChromeState.new,
        dispose: (c) => c.dispose(),
      )
      ..registerLazySingleton<SceneCodec>(() => SceneCodec(defs))
      ..registerLazySingleton<FieldEditorRegistry>(FieldEditorRegistry.new)
      ..registerLazySingleton<ComponentExtrasRegistry>(
        ComponentExtrasRegistry.new,
      )
      ..registerLazySingleton<PrefabRegistry>(PrefabRegistry.new)
      ..registerLazySingleton<LayerPresetRegistry>(LayerPresetRegistry.new)
      ..registerLazySingleton<ModuleRegistry>(
        ModuleRegistry.new,
        dispose: (m) => m.disposeAll(),
      )
      ..registerLazySingleton<EditorLogService>(
        () => log ?? EditorLogService(),
        dispose: (l) => l.dispose(),
      )
      ..registerLazySingleton<SceneStore>(
        () => SceneStore(root: scenesRoot, codec: codec),
      )
      ..registerLazySingleton<EditorSceneState>(
        () => EditorSceneState()..setGridSnapping(enabled: true, gridSize: 32),
        dispose: (s) => s.dispose(),
      )
      ..registerLazySingleton<EditorHistory>(
        EditorHistory.new,
        dispose: (h) => h.dispose(),
      )
      ..registerLazySingleton<EditorViewState>(
        EditorViewState.new,
        dispose: (v) => v.dispose(),
      )
      ..registerLazySingleton<EntityOps>(
        () => EntityOps(
          scope: this,
          world: () => this.world,
          sceneState: sceneState,
          camera: () => editorView,
          onChanged: sceneState.refresh,
        ),
      )
      ..registerLazySingleton<LevelMapDocuments>(
        () =>
            LevelMapDocuments(world: () => this.world, sceneState: sceneState),
        dispose: (d) => d.dispose(),
      )
      ..registerLazySingleton<TileEditState>(
        () => TileEditState(sceneState: sceneState, docs: mapDocs),
        dispose: (t) => t.dispose(),
      )
      ..registerLazySingleton<LevelMapProvision>(() => LevelMapProvision(this))
      ..registerLazySingleton<ProjectTags>(() {
        _tagsMade = true;
        return ProjectTags(
            path: ProjectTags.pathFor(scenesRoot: scenesRoot),
            spawners: () => spawners.value,
          )
          ..setDeclared(_declaredTags())
          ..load(seed: _tagsTheScenesCarry);
      }, dispose: (t) => t.dispose())
      ..registerLazySingleton<ProjectPhysicsLayers>(
        () => ProjectPhysicsLayers(
          path: ProjectPhysicsLayers.pathFor(scenesRoot: scenesRoot),
          context: () => engine?.context ?? _world?.context,
        )..load(),
        dispose: (l) => l.dispose(),
      )
      ..registerLazySingleton<ProjectColours>(
        () => ProjectColours(
          path: ProjectColours.pathFor(scenesRoot: scenesRoot),
          // A scope given its own settings store is a test's: it keeps its
          // hands off this machine's storage.
          storage: settingsStore == null ? JustStorage.standard : null,
        )..load(),
        dispose: (c) => c.dispose(),
      );
    this.modules.registerAll(modules);
    reload();
    // Made now rather than when first asked for: it follows the selection
    // and the scene from the start, so a map selected before any tile panel
    // is opened is already the one to paint.
    container.get<TileEditState>();
  }

  VoidCallback? _stopFollowingSettings;
  bool _following = false;
  Map<String, List<String>>? _appliedShortcuts;

  /// What the editor's services take from the settings: how much undo and
  /// how many log lines are kept, the steps snapping moves in, and the keys
  /// that were changed.
  void _followSettings() {
    final s = prefs.settings.value;
    history.capacity = s.undoLimit;
    log.maxEntries = s.consoleMaxEntries;
    sceneState
      ..moveStep = s.moveStep
      ..scaleStep = s.scaleStep
      ..rotationStep = s.rotationStepRadians;
    if (!identical(s.shortcuts, _appliedShortcuts)) {
      _appliedShortcuts = s.shortcuts;
      commands.applyShortcuts(s.shortcuts);
    }
  }

  /// The container behind the typed accessors, for anything a module wants
  /// to register alongside.
  final DiContainer container;

  final bool _isDebug;

  /// The modules whose [EditorModule.onRegister] has run: once each, however
  /// many times the registries are rebuilt.
  final Set<EditorModule> _registered = Set.identity();

  /// The engine being edited, or null for a scope over a bare [world].
  final Engine? engine;

  final World? _world;

  /// The world being edited.
  ///
  /// Read lazily: an engine's world does not exist until it initialises, and
  /// the plugin is built before that.
  World get world => _world ?? engine!.world;

  /// What the edited engine knows — its component definitions, loaders and
  /// hooks — or, for a scope over a bare [world], that world's context.
  ///
  /// Available before the engine initialises: an engine makes its context
  /// when it is constructed.
  EngineContext get context => engine?.context ?? _world!.context;

  /// Ways of putting the world back to the scene as authored, for whatever
  /// shows something else in it for a while — a timeline being previewed.
  final List<void Function()> authoredStateGuards = [];

  /// Whether the world is, right now, something other than the scene as
  /// authored — a timeline preview showing a moment of it. An autosave
  /// waits rather than end it. Whoever adds a guard can add a test here.
  final List<bool Function()> authoredStateHeld = [];

  /// True while anything in [authoredStateHeld] says so.
  bool get isAuthoredStateHeld => authoredStateHeld.any((held) => held());

  /// Called by whoever is about to read the scene as authored: a save, the
  /// snapshot a play-test starts from.
  void restoreAuthoredState() {
    for (final restore in List.of(authoredStateGuards)) {
      restore();
    }
  }

  /// Resolves a service by type. Prefer the typed accessors on hot paths.
  T get<T extends Object>() => container.get<T>();

  /// Component definitions: what can be saved, sized and drawn —
  /// [context]'s.
  ComponentDefinitionRegistry get definitions =>
      container.get<ComponentDefinitionRegistry>();

  /// Encodes and decodes components through [definitions].
  SceneCodec get codec => container.get<SceneCodec>();

  /// Fixed designer choices: grid sizes, brush sizes, bookmark slots.
  DesignerConfig get config => container.get<DesignerConfig>();

  /// Designer commands and the keys bound to them.
  CommandRegistry get commands => container.get<CommandRegistry>();

  /// Where the selection handles sit; what a replacement select tool must
  /// also describe.
  SelectionHandleLayout get handleLayout =>
      container.get<SelectionHandleLayout>();

  GridTopology _grid = const SquareGrid();

  /// The shape of the designer's cells. Square unless a module says otherwise;
  /// the last module to contribute one wins.
  GridTopology get grid => _grid;

  /// Persisted overlay settings, built-in and module-declared.
  ///
  /// Made when first asked for — reading the store is the platform's
  /// business — and from then on the services follow them.
  EditorPrefs get prefs {
    final prefs = container.get<EditorPrefs>();
    if (!_following) {
      _following = true;
      _stopFollowingSettings = prefs.settings.watch(_followSettings);
      _followSettings();
    }
    return prefs;
  }

  /// Transient overlay chrome state: panel widths, open dialogs.
  EditorChromeState get chrome => container.get<EditorChromeState>();

  /// The current theme and the presets to pick from.
  ThemeController get theme => container.get<ThemeController>();

  /// Which dock is open and how tall each one is.
  DockController get dockController => container.get<DockController>();

  final List<PrefabCategory> _prefabCategories = [];
  final List<StatusBarControl> _statusControls = [];
  final List<SidePanelSection> _designerPanels = [];
  final List<SettingsSection> _settingsSections = [];
  final List<DockDefinition> _docks = [];
  final List<ToolbarButton> _toolbarButtons = [];
  final List<GettingStartedTip> _gettingStartedTips = [];
  final List<WorkspaceDefinition> _workspaces = [];
  final List<AssetAction> _assetActions = [];
  final List<TiledObjectMapper> _tiledObjectMappers = [];
  final List<SceneValidator> _validators = [];
  final List<SceneTreeAction> _sceneTreeActions = [];
  final List<SceneTreeRowDecoration> _rowDecorations = [];
  final List<EntityIcon> _entityIcons = [];
  final List<EntityProtectionRule> _protectionRules = [];
  final List<InspectorSection> _inspectorSections = [];
  final List<EditorMarker> _markers = [];
  final List<EntityRayTest> _pickTests = [];

  /// The icons the viewport draws at entities of a kind: the editor's own,
  /// then each module's.
  List<EditorMarker> get markers => List.unmodifiable(_markers);

  /// What knows the real shape of some entities, for picking in 3-D.
  List<EntityRayTest> get pickTests => List.unmodifiable(_pickTests);

  final List<ViewportOverlay> _viewportOverlays = [];
  final List<ViewportHandles> _viewportHandles = [];
  final List<PrefabVariant> _prefabVariants = [];

  /// What lets the author drag points of the selection in the viewport.
  List<ViewportHandles> get viewportHandles => List.unmodifiable(_viewportHandles);

  /// The other ways the prefabs offered in space are offered too.
  List<PrefabVariant> get prefabVariants => List.unmodifiable(_prefabVariants);

  /// What the modules draw over the viewport, back to front.
  List<ViewportOverlay> get viewportOverlays =>
      List.unmodifiable(_viewportOverlays);

  /// The ids of the [viewportOverlays] turned off.
  final ValueNotifier<Set<String>> hiddenOverlays = ValueNotifier(const {});

  /// Turns the viewport overlay [id] on or off.
  void toggleOverlay(String id) {
    final hidden = {...hiddenOverlays.value};
    if (!hidden.remove(id)) hidden.add(id);
    hiddenOverlays.value = hidden;
  }

  /// Palette groups, built-in first, then each module's in order.
  List<PrefabCategory> get prefabCategories =>
      List.unmodifiable(_prefabCategories);

  /// Module controls appended to the designer status bar, by order.
  List<StatusBarControl> get statusControls =>
      List.unmodifiable(_statusControls);

  /// Module sections appended to the designer side panel, by order.
  List<SidePanelSection> get designerPanels =>
      List.unmodifiable(_designerPanels);

  /// Module sections in the settings dialog, by order.
  List<SettingsSection> get settingsSections =>
      List.unmodifiable(_settingsSections);

  /// Module docks appended after the built-in ones, by order.
  List<DockDefinition> get docks => List.unmodifiable(_docks);

  /// Full-screen tools modules add, by order.
  List<WorkspaceDefinition> get workspaces =>
      List.unmodifiable([...BuiltInWorkspaces.all, ..._workspaces]);

  /// Scene checks modules add to the editor's own.
  List<SceneValidator> get validators => List.unmodifiable(_validators);

  /// What modules offer to do with files in the Assets dock, by order.
  List<AssetAction> get assetActions => List.unmodifiable(_assetActions);

  /// What modules make of the objects in an imported Tiled map, by order.
  List<TiledObjectMapper> get tiledObjectMappers =>
      List.unmodifiable(_tiledObjectMappers);

  /// The camera the view is seen through; a bare one before the engine
  /// has a viewport.
  Camera get mainCamera => _mainCamera();

  /// How the editor sees the scene — what everything that draws over the
  /// viewport, picks or pans goes through: the view for the scene's mode
  /// (a module's, see [EditorModule.viewFactories], else the 2-D view on
  /// [mainCamera] or the 3-D [OrbitFlyEditorView] on it). One per mode,
  /// kept; switching mode hands the camera to the other.
  EditorView get editorView {
    final mode = sceneState.editingMode;
    final view = _views[mode] ??= (_viewFactories[mode] ?? _builtInView(mode))(this);
    if (_viewMode != mode) {
      _viewMode = mode;
      _takeCamera(view);
    }
    return view;
  }

  final Map<SceneMode, EditorView Function(EditorScope)> _viewFactories = {};
  final Map<SceneMode, EditorView> _views = {};
  SceneMode? _viewMode;

  static EditorView Function(EditorScope) _builtInView(SceneMode mode) => switch (mode) {
    SceneMode.threeD => (scope) => OrbitFlyEditorView(scope._mainCamera),
    SceneMode.twoD => (scope) => GameCameraEditorView(scope._mainCamera),
  };

  /// [view] becomes what the camera shows: a 3-D view puts its orbit on
  /// it; the 2-D view takes it back to a flat camera.
  void _takeCamera(EditorView view) {
    if (view is OrbitFlyEditorView) {
      view.sync();
      return;
    }
    final camera = _mainCamera();
    if (camera.isPlanar) return;
    camera
      ..lens = const CameraLens()
      ..pitch = 0
      ..yaw = 0
      ..z = 0;
  }

  /// The workspace that has the viewport, with the file it was opened on;
  /// null while the level has it.
  final Signal<OpenWorkspace?> activeWorkspace = Signal<OpenWorkspace?>(
    null,
    debugLabel: 'activeWorkspace',
  );

  /// Whether an open workspace fills the editor instead of sitting in it as
  /// a dialog. The author's choice, kept while the editor runs.
  final Signal<bool> workspaceFullScreen = Signal<bool>(
    false,
    debugLabel: 'workspaceFullScreen',
  );

  void toggleWorkspaceFullScreen() =>
      workspaceFullScreen.value = !workspaceFullScreen.value;

  /// Reloads what the editor shows from [paths] — project files or
  /// `packages/<name>/…` keys — after a tool or a module wrote them, each
  /// kind once. The plugin connects this; before it does, nothing happens.
  void reloadAssets(Iterable<String> paths) => assetReloader?.call(paths);

  /// What [reloadAssets] calls: set by the editor plugin while it runs.
  void Function(Iterable<String> paths)? assetReloader;

  /// Opens the workspace called [id], on [path] if given. False when no
  /// module provides it.
  ///
  /// Over an open workspace with unsaved work, the open one is asked first
  /// (see [setWorkspaceCloseGuard]); it opens only if that one agrees.
  bool openWorkspace(String id, {String? path}) {
    for (final w in workspaces) {
      if (w.id != id) continue;
      final open = activeWorkspace.value;
      final guard = _closeGuard;
      final replacing =
          open != null && (open.definition.id != id || open.path != path);
      if (guard != null && replacing) {
        unawaited(() async {
          if (!await guard()) return;
          _clearCloseGuard();
          activeWorkspace.value = OpenWorkspace(w, path);
        }());
        return true;
      }
      if (replacing) _clearCloseGuard();
      activeWorkspace.value = OpenWorkspace(w, path);
      return true;
    }
    return false;
  }

  Future<bool> Function()? _closeGuard;
  OpenWorkspace? _closeGuardOf;

  /// What the open workspace wants asked before it goes — "save your
  /// changes?" — or null to go without asking. Closing or replacing the
  /// workspace clears it.
  ///
  /// [of] is the workspace asking; the open one when null. Clearing is
  /// only ever for its own: a workspace let go after another has opened
  /// in its place does not take the new one's question with it.
  void setWorkspaceCloseGuard(
    Future<bool> Function()? guard, {
    OpenWorkspace? of,
  }) {
    final owner = of ?? activeWorkspace.value;
    if (guard == null && !identical(owner, _closeGuardOf)) return;
    _closeGuard = guard;
    _closeGuardOf = guard == null ? null : owner;
  }

  /// Closes the open workspace once its guard agrees. True when it closed.
  Future<bool> requestCloseWorkspace() async {
    final guard = _closeGuard;
    if (guard != null && !await guard()) return false;
    closeWorkspace();
    return true;
  }

  /// Opens whichever workspace best fits [path]'s ending. False when none
  /// does.
  bool openInWorkspace(String path) {
    WorkspaceDefinition? best;
    var bestMatch = 0;
    // The editor's own workspaces open files too, not only the modules'.
    for (final w in workspaces) {
      final match = w.matchOf(path);
      if (match > bestMatch) {
        best = w;
        bestMatch = match;
      }
    }
    if (best == null) return false;
    return openWorkspace(best.id, path: path);
  }

  /// Closes the open workspace at once. A workspace calls this itself once
  /// it has asked about its own unsaved work; anything else closing one
  /// goes through [requestCloseWorkspace].
  void closeWorkspace() {
    _clearCloseGuard();
    activeWorkspace.value = null;
  }

  void _clearCloseGuard() {
    _closeGuard = null;
    _closeGuardOf = null;
  }

  /// Module buttons appended after the built-in toolbar, by order.
  List<ToolbarButton> get toolbarButtons => List.unmodifiable(_toolbarButtons);

  /// What modules say on the start card, shown while no scene is open, by
  /// order.
  List<GettingStartedTip> get gettingStartedTips =>
      List.unmodifiable(_gettingStartedTips);

  /// Module entries in the scene tree's context menu, by order.
  List<SceneTreeAction> get sceneTreeActions =>
      List.unmodifiable(_sceneTreeActions);

  /// Module widgets drawn on every scene tree row, by order.
  List<SceneTreeRowDecoration> get rowDecorations =>
      List.unmodifiable(_rowDecorations);

  /// What the modules say the entities of their game look like.
  List<EntityIcon> get entityIcons => List.unmodifiable(_entityIcons);

  /// The icon for [entity]: a module's, if one claims it.
  IconData? iconFor(Entity entity) {
    for (final icon in _entityIcons) {
      final found = icon.of(entity);
      if (found != null) return found;
    }
    return null;
  }

  /// Module rules that keep an entity from being deleted or renamed.
  List<EntityProtectionRule> get protectionRules =>
      List.unmodifiable(_protectionRules);

  /// Module sections appended after the inspector's component sections.
  List<InspectorSection> get inspectorSections =>
      List.unmodifiable(_inspectorSections);

  /// The level designer in use: a module id, or null for the built-in
  /// one. Changed through [selectDesigner].
  final Signal<String?> activeDesigner = Signal(
    null,
    debugLabel: 'activeDesigner',
  );

  /// The modules that bring a level designer of their own, in registration
  /// order: what the designer's switch lists after the built-in one.
  List<EditorModule> get designers => [
    for (final module in modules.all)
      if (module.providesLevelDesigner) module,
  ];

  /// The modules whose designer contributions are live: the chosen
  /// designer's, or none for the built-in one.
  List<EditorModule> get designerModules {
    final id = activeDesigner.value;
    return id == null ? const [] : [?modules.byId(id)];
  }

  /// Switches the Level Designer to [id]'s module, or to the built-in one
  /// for null or an unknown id. Prefabs, layers, grid, palette categories,
  /// status controls and side-panel sections follow at once; an open
  /// session reloads its tools, overlays and module state.
  void selectDesigner(String? id) {
    final next = id != null && modules.byId(id) != null ? id : null;
    if (activeDesigner.value == next) return;
    // Rebuilt before anyone hears about it, so a listener sees the new
    // palette and grid rather than the old ones.
    activeDesigner.setSilent(next);
    _rebuildDesigner();
    activeDesigner.dispatchNotifications();
  }

  /// The running game's camera brain, or null for a scope over a bare world
  /// or an engine that has not started. Camera gizmos, the LIVE badge and
  /// Solo read it.
  CameraBrain? get cameraBrain {
    final e = engine;
    if (e == null || !e.isInitialized || !e.cameraSystem.isInitialized) {
      return null;
    }
    return e.cameraSystem.brain;
  }

  /// Where the palette group called [label] sorts; one nobody declared
  /// sorts after every declared one.
  int prefabCategoryOrder(String label) {
    for (final c in _prefabCategories) {
      if (c.label == label) return c.order;
    }
    return 1 << 20;
  }

  /// Whether any module protects [entity].
  bool isProtected(Entity entity) =>
      _protectionRules.any((r) => r.isProtected(entity));

  /// Which control edits which field type.
  FieldEditorRegistry get fieldEditors => container.get<FieldEditorRegistry>();

  /// Editor-only additions to how components are inspected.
  ComponentExtrasRegistry get extras =>
      container.get<ComponentExtrasRegistry>();

  /// What the inspector shows [component] through, or null when it has no
  /// definition and so cannot be saved either.
  ComponentDefinition? definitionForInspector(Component component) =>
      definitions.definitionFor(component);

  /// Prefabs the draw and paint tools can place.
  PrefabRegistry get prefabs => container.get<PrefabRegistry>();

  /// Named draw-order layers.
  LayerPresetRegistry get layers => container.get<LayerPresetRegistry>();

  /// The modules registered with this editor.
  ModuleRegistry get modules => container.get<ModuleRegistry>();

  /// Editor log.
  EditorLogService get log => container.get<EditorLogService>();

  /// Scene files on disk.
  SceneStore get scenes => container.get<SceneStore>();

  /// Selection, scene graph and grid state.
  EditorSceneState get sceneState => container.get<EditorSceneState>();

  /// Undo for everything the editor does: the scene tree, the inspector,
  /// the UI mode and the Level Designer.
  ///
  /// One stack per editor, not per designer session. Undo that only worked
  /// while a particular panel happened to be open was undo nobody could
  /// rely on, and two stacks meant Ctrl+Z reversed whichever of them the
  /// key happened to reach.
  EditorHistory get history => container.get<EditorHistory>();

  /// What is hidden and what is locked against picking — editor-only, and
  /// there whether or not the Level Designer is open.
  EditorViewState get view => container.get<EditorViewState>();

  /// Create, delete, group, re-parent and clipboard operations.
  ///
  /// On the scope because everything that edits the scene wants it, the
  /// interface editor in its own window included.
  EntityOps get entities => container.get<EntityOps>();

  /// The camera new entities are placed in front of; a bare one before the
  /// engine has a viewport, which is all a HUD's entities need.
  Camera _mainCamera() {
    final e = engine;
    if (e == null || !e.isInitialized || !e.cameraSystem.isInitialized) {
      // One kept, so a view on it stays where it was put.
      return _bareCamera;
    }
    return e.cameraSystem.mainCamera;
  }

  late final Camera _bareCamera = Camera();

  /// The tile maps being edited: in the scene or in their own files, what
  /// has changed, saving. On the scope because tools, panels, the inspector
  /// and the save all reach it.
  LevelMapDocuments get mapDocs => container.get<LevelMapDocuments>();

  /// The tile tools' shared state: the map and layer being painted, the
  /// brush, the modes.
  TileEditState get tiles => container.get<TileEditState>();

  /// Makes the scene's Level Map when something is first drawn on it.
  LevelMapProvision get mapProvision => container.get<LevelMapProvision>();

  /// The project's tags: its tag file, the tags code declares, and the ones
  /// the game's spawners give.
  ProjectTags get tags => container.get<ProjectTags>();

  /// The project's collision layers: their names and which collide. Every
  /// change is saved and reaches the running game.
  ProjectPhysicsLayers get physicsLayers =>
      container.get<ProjectPhysicsLayers>();

  /// The palettes and gradients the project keeps, and this user's recent
  /// colours: what every colour picker in the editor offers.
  ProjectColours get colours => container.get<ProjectColours>();

  /// Around the game as the viewport shows it, so the colour picker's
  /// eyedropper can read a pixel of it. Set on the viewport by the overlay.
  final GlobalKey viewportCaptureKey = GlobalKey(debugLabel: 'viewport');

  /// Finds and rewrites tags in saved scenes and timelines, through
  /// [definitions].
  TagReferences get tagReferences =>
      TagReferences(definitions.definitionByType);

  bool _tagsMade = false;

  /// Whether a play-test is on, paused or not — what an inspector showing
  /// live values follows. The plugin keeps it.
  final Signal<bool> isPlayTesting = Signal(false, debugLabel: 'playTesting');

  /// The collision layer being pointed at — a chip, a picker, a row of the
  /// Physics Layers dock — whose bodies the viewport rings. Null when none
  /// is.
  final Signal<int?> highlightedLayer = Signal(
    null,
    debugLabel: 'highlightedLayer',
  );

  /// The tag being pointed at — a chip under the mouse — whose entities the
  /// viewport rings. Null when none is.
  final Signal<String?> highlightedTag = Signal(
    null,
    debugLabel: 'highlightedTag',
  );

  /// What the game's spawn points can create, as the app registered it with
  /// the editor: what Play spawns, what a spawn point's "Spawns" field
  /// offers, and the tags that exist only once the game runs.
  final Signal<List<Spawner>> spawners = Signal(
    const [],
    debugLabel: 'spawners',
  );

  List<TagDefinition> _declaredTags() => [
    for (final module in modules.all) ...module.tags,
  ];

  /// The tags the project's scene files — and the open world — carry: what
  /// a project that has no tag file yet already uses.
  Set<String> _tagsTheScenesCarry() {
    final found = <String>{};
    try {
      found.addAll(world.tagsInUse);
    } on Object {
      // No world yet: the files are enough.
    }
    final references = tagReferences;
    for (final name in scenes.listSceneNames()) {
      final raw = scenes.readRawSync(name);
      if (raw == null) continue;
      final migrated = SceneFormat.migrate(raw, hooks: context.migrations);
      for (final use in references.inScene(migrated)) {
        if (use.kind == TagUseKind.carried) found.add(use.tag);
      }
    }
    return found;
  }

  /// After a hot reload: the editor's own presets made again, each module
  /// told ([EditorModule.onReassemble]), then every registry rebuilt from
  /// the code as it now is ([reload]), and the palette in use shown as it
  /// now is. `JustGameEditorPlugin.reassemble` calls this.
  void reassemble() {
    theme.resetPresets();
    final context = EditorModuleContext(scope: this, isDebug: _isDebug);
    for (final module in modules.all) {
      if (_registered.contains(module)) module.onReassemble(context);
    }
    reload();
    theme.refreshCurrent();
  }

  /// Rebuilds every scope-level registry from scratch: built-ins, then each
  /// module's contributions in registration order. Idempotent, so it is safe
  /// on every hot reload — and nothing a module stopped contributing survives.
  /// A module's [EditorModule.onRegister] runs on its first pass only.
  void reload() {
    fieldEditors.clear();
    fieldEditors.registerAll(BuiltInFieldEditors.all);
    extras.clear();
    extras.registerAll(BuiltInExtras.all);
    extras.registerAll(PhysicsBodyExtras.all(this));
    extras.registerAll(BuiltInCameraContributions.extras);
    extras.registerAll(BuiltInTileContributions.extras);
    // 3-D physics tooling only where the engine has 3-D physics.
    final physics3D = BuiltInPhysics3DContributions.appliesTo(this.context);
    if (physics3D) extras.registerAll(BuiltInPhysics3DContributions.extras);
    commands.clear();
    commands.registerAll(BuiltInCommands.all);
    commands.bindAll(BuiltInBindings.of(config));
    for (final l in [
      _settingsSections,
      _docks,
      _toolbarButtons,
      _gettingStartedTips,
      _workspaces,
      _assetActions,
      _tiledObjectMappers,
      _validators,
      _sceneTreeActions,
      _rowDecorations,
      _entityIcons,
      _protectionRules,
      _inspectorSections,
    ]) {
      l.clear();
    }
    _viewFactories.clear();
    _markers
      ..clear()
      ..addAll(EditorMarker.builtIn);
    _pickTests.clear();
    _viewportOverlays.clear();
    _viewportHandles.clear();
    _prefabVariants.clear();
    final kinds = AssetKinds();
    // The editor's own camera tooling arrives the way a module's would.
    _sceneTreeActions.addAll(BuiltInCameraContributions.sceneTreeActions);
    _rowDecorations.addAll(BuiltInCameraContributions.rowDecorations);
    _rowDecorations.addAll(BuiltInRowDecorations.all);
    _sceneTreeActions.addAll(BuiltInTagContributions.sceneTreeActions);
    _rowDecorations.addAll(BuiltInTagContributions.rowDecorations);
    _entityIcons.addAll(BuiltInTileContributions.entityIcons);
    _assetActions.addAll(BuiltInTileContributions.assetActions);
    if (physics3D) {
      _viewportOverlays.addAll(BuiltInPhysics3DContributions.viewportOverlays);
      _prefabVariants.addAll(BuiltInPhysics3DContributions.prefabVariants);
    }
    final context = EditorModuleContext(scope: this, isDebug: _isDebug);
    for (final module in modules.all) {
      fieldEditors.registerAll(module.fieldEditors, override: true);
      fieldEditors.inheritedColors.addAll(module.inheritedColors);
      extras.registerAll(module.componentExtras);
      commands.registerAll(module.commands, override: true);
      commands.bindAll(module.keyBindings);
      _settingsSections.addAll(module.settingsSections);
      _docks.addAll(module.docks);
      _toolbarButtons.addAll(module.toolbarButtons);
      _gettingStartedTips.addAll(module.gettingStartedTips);
      _workspaces.addAll(module.workspaces);
      _assetActions.addAll(module.assetActions);
      _tiledObjectMappers.addAll(module.tiledObjectMappers);
      _validators.addAll(module.validators);
      _sceneTreeActions.addAll(module.sceneTreeActions);
      _rowDecorations.addAll(module.rowDecorations);
      _entityIcons.addAll(module.entityIcons);
      if (module.protectionRule case final rule?) _protectionRules.add(rule);
      _inspectorSections.addAll(module.inspectorSections);
      _viewFactories.addAll(module.viewFactories);
      _markers.addAll(module.markers);
      _pickTests.addAll(module.pickTests);
      module.assetKinds.forEach(kinds.add);
      _viewportOverlays.addAll(module.viewportOverlays);
      _viewportHandles.addAll(module.viewportHandles);
      _prefabVariants.addAll(module.prefabVariants);
      module.themePresets.forEach(theme.register);
      // Once per module: setup that loads files or installs into the engine
      // must not run again on each rebuild — see [reassemble].
      if (_registered.add(module)) module.onRegister(context);
    }
    _registered.retainWhere(modules.all.contains);
    _viewportOverlays.sort((a, b) => a.order.compareTo(b.order));
    // What a file is, for the browser and drops: the editor's kinds and the
    // modules'.
    AssetKinds.active = kinds;
    ModuleDataFiles.replace([
      for (final module in modules.all) ...module.dataFileSuffixes,
    ]);
    // Made when first asked for — reading it scans the scenes — and kept
    // in step with the modules from then on.
    if (_tagsMade) tags.setDeclared(_declaredTags());
    // The bindings are as built: the keys changed in the settings go over
    // them, on this and every later rebuild.
    commands.markBuilt();
    if (_following) {
      final shortcuts = prefs.settings.value.shortcuts;
      commands.applyShortcuts(shortcuts);
      _appliedShortcuts = shortcuts;
    }
    _settingsSections.sort((a, b) => a.order.compareTo(b.order));
    _docks.sort((a, b) => a.order.compareTo(b.order));
    _toolbarButtons.sort((a, b) => a.order.compareTo(b.order));
    _gettingStartedTips.sort((a, b) => a.order.compareTo(b.order));
    _workspaces.sort((a, b) => a.order.compareTo(b.order));
    _assetActions.sort((a, b) => a.order.compareTo(b.order));
    _tiledObjectMappers.sort((a, b) => a.order.compareTo(b.order));
    // A workspace whose module went away gives the viewport back. The
    // editor's own never go away: a reload must not shut one that is open.
    final open = activeWorkspace.value;
    if (open != null && !workspaces.any((w) => w.id == open.definition.id)) {
      activeWorkspace.value = null;
    }
    _sceneTreeActions.sort((a, b) => a.order.compareTo(b.order));
    _rowDecorations.sort((a, b) => a.order.compareTo(b.order));
    _entityIcons.sort((a, b) => a.order.compareTo(b.order));
    _inspectorSections.sort((a, b) => a.order.compareTo(b.order));
    // A designer whose module went away falls back to the built-in one.
    final active = activeDesigner.value;
    if (active != null && modules.byId(active) == null) {
      activeDesigner.setSilent(null);
    }
    _rebuildDesigner();
    if (active != activeDesigner.value) activeDesigner.dispatchNotifications();
  }

  /// Rebuilds what the Level Designer shows from the built-ins and the
  /// chosen designer's module; the other designers wait to be chosen.
  void _rebuildDesigner() {
    _prefabCategories
      ..clear()
      ..addAll(BuiltInPrefabs.categories);
    _statusControls.clear();
    _designerPanels.clear();
    _grid = const SquareGrid();
    prefabs.clear();
    BuiltInPrefabs.registerAll(prefabs);
    for (final module in modules.all) {
      prefabs.registerAll(module.sharedPrefabs);
    }
    layers.clear();
    layers.registerAll(LayerPresetRegistry.builtIn);
    for (final module in designerModules) {
      _prefabCategories.addAll(module.prefabCategories);
      _statusControls.addAll(module.statusControls);
      _designerPanels.addAll(module.designerPanels);
      _grid = module.gridTopology ?? _grid;
      prefabs.registerAll(module.prefabs);
      layers.registerAll(module.layers);
    }
    _statusControls.sort((a, b) => a.order.compareTo(b.order));
    _designerPanels.sort((a, b) => a.order.compareTo(b.order));
  }

  /// Opens a child container for per-session services (a designer session's
  /// history, tools, snap providers). Closed by the caller.
  DiScope openSession({String? debugLabel}) =>
      container.createScope(debugLabel: debugLabel);

  /// Disposes every service this scope owns, in reverse registration order.
  void dispose() {
    _stopFollowingSettings?.call();
    activeDesigner.dispose();
    activeWorkspace.dispose();
    workspaceFullScreen.dispose();
    spawners.dispose();
    highlightedTag.dispose();
    highlightedLayer.dispose();
    hiddenOverlays.dispose();
    isPlayTesting.dispose();
    container.close();
  }
}

/// Makes an [EditorScope] available to a widget subtree.
class EditorScopeProvider extends InheritedWidget {
  const EditorScopeProvider({
    super.key,
    required this.scope,
    required super.child,
  });

  final EditorScope scope;

  /// The nearest scope above [context].
  static EditorScope of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<EditorScopeProvider>();
    assert(provider != null, 'No EditorScopeProvider above this widget');
    return provider!.scope;
  }

  /// The nearest scope above [context], or null.
  static EditorScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EditorScopeProvider>()?.scope;

  @override
  bool updateShouldNotify(EditorScopeProvider old) => old.scope != scope;
}

/// A workspace that is open, and the file it was opened on.
class OpenWorkspace {
  const OpenWorkspace(this.definition, [this.path]);

  final WorkspaceDefinition definition;
  final String? path;
}
