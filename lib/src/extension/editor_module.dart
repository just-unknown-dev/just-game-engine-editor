import '../core/validation/scene_validator.dart';
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../core/scope/editor_scope.dart';
import '../core/state/editor_scene_state.dart';
import '../ui/level_designer/overlays/designer_overlay.dart';
import '../ui/level_designer/state/editor_history.dart';
import '../ui/level_designer/state/layer_preset.dart';
import '../ui/level_designer/state/prefab_registry.dart';
import '../ui/inspector/component_extras.dart';
import '../ui/inspector/field_editor.dart';
import '../ui/level_designer/commands/designer_command.dart';
import '../ui/level_designer/grid/grid_topology.dart';
import '../ui/level_designer/level_designer_session.dart';
import '../ui/level_designer/state/snap_provider.dart';
import 'designer_contributions.dart';
import '../core/theme/editor_theme_data.dart';
import 'editor_contributions.dart';
import '../ui/level_designer/tools/level_tool.dart';

/// What a module is handed when it registers.
class EditorModuleContext {
  const EditorModuleContext({required this.scope, required this.isDebug});

  /// The editor this module was registered into.
  final EditorScope scope;

  /// The world being edited.
  jge.World get world => scope.world;

  /// Always true in practice — the editor does not exist otherwise — but
  /// explicit beats assumed.
  final bool isDebug;
}

/// What a tool needs from the designer session it belongs to.
///
/// Tools are built per session rather than once, because anything that edits
/// the scene has to act on *that* session's selection and push onto *that*
/// session's undo history. Neither exists until the designer opens.
class DesignerToolContext {
  const DesignerToolContext({
    required this.scope,
    required this.world,
    required this.sceneState,
    required this.history,
    required this.uniqueName,
  });

  /// The editor the session belongs to; its codec, definitions and log.
  final EditorScope scope;

  /// The world being edited.
  final jge.World world;

  /// Selection and grid state shared with the rest of the editor.
  final EditorSceneState sceneState;

  /// The undo stack. Every edit a tool makes should be one command on it.
  final EditorHistory history;

  /// Returns an entity name not already in use, built from [prefix].
  final String Function(String prefix) uniqueName;
}

/// Everything a project contributes to the editor, in one place.
///
/// The editor knows how to select, move, align, snap, layer and undo. It knows
/// nothing about platforms, patrol routes or spawn zones, and it should not
/// have to. A module is how a game teaches it: what can be placed, what tools
/// make sense, what to draw on the viewport, and how its own components
/// appear in the inspector.
///
/// Every member has a default, so a module that only adds two prefabs is two
/// overridden getters. Pass modules to the [EditorScope]:
///
/// ```dart
/// EditorScope(engine: engine, modules: [MyGameModule()]);
/// ```
///
/// Contributions are re-read on every reload, so an edited module takes
/// effect on hot reload without restarting.
abstract class EditorModule {
  /// Stable identifier. Registering twice with the same id replaces the first.
  String get id;

  /// Display name, shown wherever modules are listed.
  String get name;

  /// Optional icon for that listing.
  IconData? get icon => null;

  /// Inspector editors for this module's own field types, by
  /// [jge.FieldType.id]. Registered over the built-ins, so a module can also
  /// replace one of those.
  Map<String, FieldEditorBuilder> get fieldEditors => const {};

  /// Editor-only additions to how components are inspected: header actions,
  /// a custom section, a replacement editor for one field.
  List<ComponentEditorExtras> get componentExtras => const [];

  /// Palette entries the draw and paint tools can place.
  List<PrefabDefinition> get prefabs => const [];

  /// Viewport tools, built fresh for each designer session. Ids should be
  /// prefixed to avoid colliding with built-ins; reusing a built-in's id
  /// replaces it.
  List<LevelToolHandler> createTools(DesignerToolContext context) => const [];

  /// The shape of the designer's cells, when this module changes it. The
  /// last module to answer wins; null keeps the square grid.
  GridTopology? get gridTopology => null;

  /// Palette groups this module's prefabs use, with their order.
  List<PrefabCategory> get prefabCategories => const [];

  /// Ways of snapping, built fresh per session. Priority decides where they
  /// sit relative to the built-ins (entities 100, grid 0).
  List<SnapProvider> createSnapProviders(DesignerToolContext context) =>
      const [];

  /// State this module keeps per designer session — a route being edited,
  /// say. Tools reach it with `context.stateOf<T>()`; it survives a reload.
  Object? createSessionState(DesignerToolContext context) => null;

  /// What this module saves in the scene file's `editor` section, under its
  /// own id. Null saves nothing.
  Map<String, Object?>? saveEditorData(LevelDesignerSession session) => null;

  /// Restores what [saveEditorData] wrote for this scene.
  void restoreEditorData(
    LevelDesignerSession session,
    Map<String, Object?> data,
  ) {}

  /// Controls added to the designer's status bar.
  List<StatusBarControl> get statusControls => const [];

  /// Sections added to the designer's side panel.
  List<SidePanelSection> get designerPanels => const [];

  /// Things drawn over the level, each with its own visibility toggle.
  List<DesignerOverlay> get overlays => const [];

  /// Named draw-order layers this genre expects.
  List<LayerPreset> get layers => const [];

  /// Whether this module is a level designer of its own: an entry in the
  /// designer's switch beside the built-in one, whose designer
  /// contributions are live only while it is chosen.
  ///
  /// True by default when the module contributes anything the switch
  /// scopes — prefabs, overlays, layers, a grid, palette categories, status
  /// controls or side-panel sections. A designer made only of tools, snap
  /// providers or session state overrides this to return true.
  bool get providesLevelDesigner =>
      prefabs.isNotEmpty ||
      overlays.isNotEmpty ||
      layers.isNotEmpty ||
      gridTopology != null ||
      prefabCategories.isNotEmpty ||
      statusControls.isNotEmpty ||
      designerPanels.isNotEmpty;

  /// Add-Component picker groups this module's definitions use, in the order
  /// they should appear after the built-in groups.
  List<String> get componentGroups => const [];

  /// Commands this module adds, or replaces by reusing a built-in's id.
  List<DesignerCommand> get commands => const [];

  /// Key chords for commands, this module's or anyone's. A chord bound here
  /// takes precedence over a built-in binding of the same chord.
  List<KeyBinding> get keyBindings => const [];

  /// Sections on the settings dialog's Modules tab.
  List<SettingsSection> get settingsSections => const [];

  /// Bottom docks beside the built-in ones.
  List<DockDefinition> get docks => const [];

  /// Full-screen tools that take the viewport: a sprite editor, a dialogue
  /// graph. Opened with [EditorScope.openWorkspace].
  List<WorkspaceDefinition> get workspaces => const [];

  /// Checks this module makes of the open scene, listed in the Problems
  /// dock beside the editor's own: a level with no spawn point, say.
  List<SceneValidator> get validators => const [];

  /// What this module can do with a file in the Assets dock.
  List<AssetAction> get assetActions => const [];

  /// Buttons after the built-in play controls.
  List<ToolbarButton> get toolbarButtons => const [];

  /// Entries in an entity's scene-tree context menu.
  List<SceneTreeAction> get sceneTreeActions => const [];

  /// Things drawn at the end of scene-tree rows.
  List<SceneTreeRowDecoration> get rowDecorations => const [];

  /// Which entities the scene tree must not delete, beyond the camera.
  EntityProtectionRule? get protectionRule => null;

  /// Palettes offered in the settings dialog beside the built-in accents.
  List<ThemePreset> get themePresets => const [];

  /// Inspector sections after the component sections.
  List<InspectorSection> get inspectorSections => const [];

  /// Called once per registration pass, after the built-ins are in place.
  void onRegister(EditorModuleContext context) {}

  /// Called when a scene finishes loading.
  void onSceneOpened(String sceneName) {}

  /// Called every editor tick.
  void onUpdate(double dt) {}

  /// Called when the owning editor is disposed.
  void dispose() {}
}

/// The modules registered with one editor, and how their contributions reach
/// the editor's registries.
///
/// Owned by an [EditorScope]; there is no process-wide list. [reload]
/// rebuilds every scope-level registry from scratch — built-ins first, then
/// each module in registration order — so a module can replace a built-in by
/// reusing its id, and nothing a module *stopped* contributing lingers.
class ModuleRegistry {
  ModuleRegistry();

  final Map<String, EditorModule> _modules = {};

  /// All registered modules, in registration order.
  List<EditorModule> get all => List.unmodifiable(_modules.values);

  /// Looks up a module by id.
  EditorModule? byId(String id) => _modules[id];

  /// Registers [module], replacing any existing one with the same id.
  void register(EditorModule module) => _modules[module.id] = module;

  /// Registers several modules.
  void registerAll(Iterable<EditorModule> modules) => modules.forEach(register);

  /// Removes a module.
  void unregister(String id) => _modules.remove(id)?.dispose();

  /// Every component group declared by a module, in registration order.
  List<String> get componentGroups => [
    for (final m in _modules.values) ...m.componentGroups,
  ];

  /// Forwards a scene load.
  void notifySceneOpened(String sceneName) {
    for (final m in _modules.values) {
      m.onSceneOpened(sceneName);
    }
  }

  /// Forwards an editor tick.
  void notifyUpdate(double dt) {
    for (final m in _modules.values) {
      m.onUpdate(dt);
    }
  }

  /// Disposes every module and forgets them.
  void disposeAll() {
    for (final m in _modules.values) {
      m.dispose();
    }
    _modules.clear();
  }
}
