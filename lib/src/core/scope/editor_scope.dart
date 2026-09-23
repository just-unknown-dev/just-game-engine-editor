import 'package:flutter/widgets.dart';
import 'package:just_di/just_di.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_signals/just_signals.dart';

import '../validation/scene_validator.dart';
import '../../extension/editor_module.dart';
import '../../ui/level_designer/state/built_in_prefabs.dart';
import '../../ui/level_designer/state/layer_preset.dart';
import '../../ui/level_designer/state/prefab_registry.dart';
import '../../ui/inspector/built_in_extras.dart';
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
import '../state/editor_scene_state.dart';
import '../../extension/built_in_row_decorations.dart';
import '../entity/entity_ops.dart';
import '../state/editor_view_state.dart';
import '../../ui/level_designer/ui_mode/ui_mode_session.dart';
import '../../ui/level_designer/ui_mode/ui_workspace.dart';
import '../../extension/built_in_camera_contributions.dart';

/// Everything one editor owns: its registries, services and state, in a
/// `just_di` container that is disposed with it.
///
/// There are no process-wide registries. Two scopes in one process — two
/// tests, or two editors side by side — share nothing except the engine's
/// component definitions, which the *game* registers at boot and which the
/// scope reads by default.
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
    ComponentDefinitionRegistry? definitions,
    DiContainer? parent,
    EditorLogService? log,
    String? scenesRoot,
    DesignerConfig config = const DesignerConfig(),
    OverlaySettingsStore? settingsStore,
    SelectionHandleLayout handles = const SelectionHandleLayout(),
    bool isDebug = true,
  }) : assert(engine != null || world != null, 'Pass an engine or a world'),
       engine = engine,
       _world = world,
       container = DiContainer(parent: parent),
       _isDebug = isDebug {
    final defs = definitions ?? ComponentDefinitionRegistry.instance;
    registerCoreCodecs(defs);
    if (engine != null) container.registerSingleton<Engine>(engine);
    container
      ..registerSingleton<ComponentDefinitionRegistry>(defs)
      ..registerSingleton<DesignerConfig>(config)
      ..registerSingleton<SelectionHandleLayout>(handles)
      ..registerLazySingleton<CommandRegistry>(CommandRegistry.new)
      ..registerLazySingleton<EditorPrefs>(
        () => EditorPrefs(
          store: settingsStore ?? OverlaySettingsStore(JustStorage.standard()),
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
          camera: _mainCamera,
          onChanged: sceneState.refresh,
        ),
      )
      ..registerLazySingleton<UiModeSession>(
        () => UiModeSession(world: () => this.world),
        dispose: (u) => u.dispose(),
      );
    this.modules.registerAll(modules);
    reload();
  }

  /// The container behind the typed accessors, for anything a module wants
  /// to register alongside.
  final DiContainer container;

  final bool _isDebug;

  /// The engine being edited, or null for a scope over a bare [world].
  final Engine? engine;

  final World? _world;

  /// The world being edited.
  ///
  /// Read lazily: an engine's world does not exist until it initialises, and
  /// the plugin is built before that.
  World get world => _world ?? engine!.world;

  /// Ways of putting the world back to the scene as authored, for whatever
  /// shows something else in it for a while — a timeline being previewed.
  final List<void Function()> authoredStateGuards = [];

  /// Called by whoever is about to read the scene as authored: a save, the
  /// snapshot a play-test starts from.
  void restoreAuthoredState() {
    for (final restore in List.of(authoredStateGuards)) {
      restore();
    }
  }

  /// Resolves a service by type. Prefer the typed accessors on hot paths.
  T get<T extends Object>() => container.get<T>();

  /// Component definitions: what can be saved, sized and drawn.
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
  EditorPrefs get prefs => container.get<EditorPrefs>();

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
  final List<WorkspaceDefinition> _workspaces = [];
  final List<AssetAction> _assetActions = [];
  final List<SceneValidator> _validators = [];
  final List<SceneTreeAction> _sceneTreeActions = [];
  final List<SceneTreeRowDecoration> _rowDecorations = [];
  final List<EntityIcon> _entityIcons = [];
  final List<EntityProtectionRule> _protectionRules = [];
  final List<InspectorSection> _inspectorSections = [];

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

  /// Opens the workspace called [id], on [path] if given. False when no
  /// module provides it.
  bool openWorkspace(String id, {String? path}) {
    for (final w in workspaces) {
      if (w.id != id) continue;
      activeWorkspace.value = OpenWorkspace(w, path);
      // The interface editor's own flag follows the workspace, so the
      // buttons that light up when it is open have one thing to read.
      uiMode.enabled.value = id == BuiltInWorkspaces.ui;
      return true;
    }
    return false;
  }

  /// Opens whichever workspace best fits [path]'s ending. False when none
  /// does.
  bool openInWorkspace(String path) {
    WorkspaceDefinition? best;
    var bestMatch = 0;
    for (final w in _workspaces) {
      final match = w.matchOf(path);
      if (match > bestMatch) {
        best = w;
        bestMatch = match;
      }
    }
    if (best == null) return false;
    activeWorkspace.value = OpenWorkspace(best, path);
    return true;
  }

  void closeWorkspace() {
    activeWorkspace.value = null;
    uiMode.enabled.value = false;
  }

  /// Module buttons appended after the built-in toolbar, by order.
  List<ToolbarButton> get toolbarButtons => List.unmodifiable(_toolbarButtons);

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
      return Camera();
    }
    return e.cameraSystem.mainCamera;
  }

  /// The interface editor's state — which screen it is showing, what is
  /// snapped to, where each node landed. On the scope because a
  /// workspace is built from one: its builder gets nothing else.
  UiModeSession get uiMode => container.get<UiModeSession>();

  /// Rebuilds every scope-level registry from scratch: built-ins, then each
  /// module's contributions in registration order. Idempotent, so it is safe
  /// on every hot reload — and nothing a module stopped contributing survives.
  void reload() {
    fieldEditors.clear();
    fieldEditors.registerAll(BuiltInFieldEditors.all);
    extras.clear();
    extras.registerAll(BuiltInExtras.all);
    extras.registerAll(BuiltInCameraContributions.extras);
    commands.clear();
    commands.registerAll(BuiltInCommands.all);
    commands.bindAll(BuiltInBindings.of(config));
    for (final l in [
      _settingsSections,
      _docks,
      _toolbarButtons,
      _workspaces,
      _assetActions,
      _validators,
      _sceneTreeActions,
      _rowDecorations,
      _entityIcons,
      _protectionRules,
      _inspectorSections,
    ]) {
      l.clear();
    }
    // The editor's own camera tooling arrives the way a module's would.
    _sceneTreeActions.addAll(BuiltInCameraContributions.sceneTreeActions);
    _rowDecorations.addAll(BuiltInCameraContributions.rowDecorations);
    _rowDecorations.addAll(BuiltInRowDecorations.all);
    final context = EditorModuleContext(scope: this, isDebug: _isDebug);
    for (final module in modules.all) {
      fieldEditors.registerAll(module.fieldEditors, override: true);
      extras.registerAll(module.componentExtras);
      commands.registerAll(module.commands, override: true);
      commands.bindAll(module.keyBindings);
      _settingsSections.addAll(module.settingsSections);
      _docks.addAll(module.docks);
      _toolbarButtons.addAll(module.toolbarButtons);
      _workspaces.addAll(module.workspaces);
      _assetActions.addAll(module.assetActions);
      _validators.addAll(module.validators);
      _sceneTreeActions.addAll(module.sceneTreeActions);
      _rowDecorations.addAll(module.rowDecorations);
      _entityIcons.addAll(module.entityIcons);
      if (module.protectionRule case final rule?) _protectionRules.add(rule);
      _inspectorSections.addAll(module.inspectorSections);
      module.themePresets.forEach(theme.register);
      module.onRegister(context);
    }
    _settingsSections.sort((a, b) => a.order.compareTo(b.order));
    _docks.sort((a, b) => a.order.compareTo(b.order));
    _toolbarButtons.sort((a, b) => a.order.compareTo(b.order));
    _workspaces.sort((a, b) => a.order.compareTo(b.order));
    _assetActions.sort((a, b) => a.order.compareTo(b.order));
    // A workspace whose module went away gives the viewport back.
    final open = activeWorkspace.value;
    if (open != null && !_workspaces.any((w) => w.id == open.definition.id)) {
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
    activeDesigner.dispose();
    activeWorkspace.dispose();
    workspaceFullScreen.dispose();
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
