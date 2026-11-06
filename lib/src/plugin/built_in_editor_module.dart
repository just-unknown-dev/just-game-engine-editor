import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import '../inspector/built_in_extras.dart';
import '../inspector/built_in_field_editors.dart';
import '../physics/physics_body_extras.dart';
import 'commands/built_in_bindings.dart';
import 'commands/built_in_commands.dart';
import '../level_designer/state/built_in_prefabs.dart';
import '../timeline/field_key_button.dart';
import '../timeline/timeline_renames.dart';
import '../timeline/timeline_session.dart';
import '../entities/scope_entities.dart';
import '../prefabs/prefab_files.dart';
import '../prefabs/prefab_inspector.dart';
import '../level_designer/level_designer_3d/built_in_designer_3d_contributions.dart';
import '../audio/built_in_audio_contributions.dart';
import '../graphics/graphics_2d/built_in_lighting_2d_contributions.dart';
import '../camera/built_in_camera_contributions.dart';
import '../physics/physics_3d/built_in_physics_3d_contributions.dart';
import '../scene_tree/built_in_row_decorations.dart';
import '../tags/built_in_tag_contributions.dart';
import '../level_map/built_in_tile_contributions.dart';
import '../docks/scope_docks.dart';
import '../level_map/scope_level_maps.dart';
import '../level_designer/level_designer_3d/aids/level_3d_checks.dart';
import '../level_map/level_map_checks.dart';
import '../physics/physics_3d/physics_3d_checks.dart';
import '../physics/physics_checks.dart';
import '../problems/scene_checks.dart';
import '../tags/tag_checks.dart';
import '../assets/json_workspace.dart';
import '../tileset/tileset_workspace.dart';

/// The editor's own tools, arriving the way a module's do: its field
/// editors and inspector extras, its commands and keys, the Level
/// Designer's default kits (2-D and 3-D) and palette, the Tileset Editor,
/// the camera, sound, tag, tile and 3-D physics tooling, the 3-D view, and
/// the timeline's key button.
///
/// The editor makes every scope with it ahead of the other modules
/// (`EditorScope(builtIns: [BuiltInEditorModule.new])`), so a module
/// replaces any of it by reusing an id. Its Level Designer contributions are
/// live whichever designer is chosen.
class BuiltInEditorModule extends EditorModule {
  /// The editor's tools for [scope]; a scope makes it from
  /// `builtIns: [BuiltInEditorModule.new]`.
  BuiltInEditorModule(this.scope);

  /// The scope it belongs to.
  final EditorScope scope;

  /// The module for [scope]: how the editor makes its built-ins.
  static EditorModule make(EditorScope scope) => BuiltInEditorModule(scope);

  /// Its id: one module of the editor's own per scope.
  static const String moduleId = 'editor';

  @override
  String get id => moduleId;

  @override
  String get name => 'Editor';

  /// Its Level Designer contributions are the built-in designer's, live
  /// whichever is chosen: it is never a designer to choose.
  @override
  bool get providesLevelDesigner => false;

  /// 3-D physics tooling only where the engine has 3-D physics.
  bool get _physics3D => BuiltInPhysics3DContributions.isFor(scope.context);

  @override
  Map<String, FieldEditorBuilder> get fieldEditors => BuiltInFieldEditors.all;

  @override
  List<ComponentEditorExtras> get componentExtras => [
    ...BuiltInExtras.all,
    ...PhysicsBodyExtras.all(scope),
    ...BuiltInCameraContributions.extras,
    ...BuiltInTileContributions.extras,
    if (_physics3D) ...BuiltInPhysics3DContributions.extras,
  ];

  @override
  List<DesignerCommand> get commands => [
    ...BuiltInCommands.all,
    ...BuiltInLighting2DContributions.commands,
  ];

  @override
  List<KeyBinding> get keyBindings => [
    ...BuiltInBindings.of(scope.config),
    ...BuiltInLighting2DContributions.keyBindings,
  ];

  /// The default kits' palettes: the 2-D shapes and the 3-D ones, each
  /// offered in its own kind of scene.
  @override
  List<PrefabDefinition> get prefabs => [
    ...BuiltInPrefabs.all,
    ...BuiltInDesigner3DContributions.prefabs,
  ];

  late final EntityRayTest _shapeTest =
      BuiltInDesigner3DContributions.shapeTest();

  @override
  List<EntityRayTest> get pickTests => [_shapeTest];

  /// Prefab files: dropped on the viewport, an instance of one.
  @override
  List<AssetKind> get assetKinds => const [PrefabFiles.kind];

  late final List<PrefabPicture> _pictures =
      BuiltInDesigner3DContributions.prefabPictures();

  @override
  List<PrefabPicture> get prefabPictures => _pictures;

  @override
  List<ViewportHandles> get viewportHandles =>
      BuiltInDesigner3DContributions.viewportHandles;

  @override
  List<PrefabCategory> get prefabCategories => BuiltInPrefabs.categories;

  /// The checks it makes of every scene, in the order the Problems dock
  /// lists what they find (errors first).
  static const List<SceneValidator> _checks = [
    SceneChecks.missingAssets,
    SceneChecks.unresolvedEntityReferences,
    SceneChecks.animatorClips,
    SceneChecks.timelines,
    SceneChecks.camerasWithoutTargets,
    TagChecks.unknownTags,
    TagChecks.spawnPoints,
    TagChecks.unresolvedTargets,
    ...PhysicsChecks.all,
    Physics3DChecks.all,
    Level3DChecks.all,
    SceneChecks.drawnWithoutTransform,
    LevelMapChecks.levelMaps,
    LevelMapChecks.unshippedTileAssets,
    SceneChecks.unknownComponents,
    BuiltInLighting2DContributions.lightsWithoutLighting,
  ];

  @override
  List<SceneValidator> get validators => _checks;

  @override
  List<WorkspaceDefinition> get workspaces => [
    TilesetWorkspace.definition,
    JsonWorkspace.definition,
  ];

  @override
  List<EditorMarker> get markers => [
    ...EditorMarker.builtIn,
    ...BuiltInAudioContributions.markers,
    ...BuiltInLighting2DContributions.markers,
  ];

  @override
  List<ViewportOverlay> get viewportOverlays => [
    ...BuiltInAudioContributions.viewportOverlays,
    ...BuiltInLighting2DContributions.viewportOverlays,
    if (_physics3D) ...BuiltInPhysics3DContributions.viewportOverlays,
  ];

  @override
  List<PrefabVariant> get prefabVariants =>
      _physics3D ? BuiltInPhysics3DContributions.prefabVariants : const [];

  @override
  List<SceneTreeAction> get sceneTreeActions => [
    ...BuiltInCameraContributions.sceneTreeActions,
    ...BuiltInTagContributions.sceneTreeActions,
  ];

  @override
  List<SceneTreeRowDecoration> get rowDecorations => [
    ...BuiltInCameraContributions.rowDecorations,
    ...BuiltInRowDecorations.all,
    ...BuiltInTagContributions.rowDecorations,
  ];

  @override
  List<EntityIcon> get entityIcons => BuiltInTileContributions.entityIcons;

  @override
  List<AssetAction> get assetActions => BuiltInTileContributions.assetActions;

  @override
  Map<jge.SceneMode, EditorView Function(EditorScope scope)>
  get viewFactories => {
    jge.SceneMode.threeD: (scope) => OrbitFlyEditorView(() => scope.mainCamera),
  };

  @override
  List<FieldAccessory> get fieldAccessories => [
    const FieldAccessory(
      id: 'timeline.key',
      build: _timelineKey,
      onEdited: _recordEdit,
    ),
    PrefabInspector.marks,
  ];

  /// A prefab instance's part: which prefab, what it changes, Apply,
  /// Revert, Unpack and editing the prefab.
  @override
  List<InspectorSection> get inspectorSections => [PrefabInspector.section];

  /// The key button after a row, while a Timeline dock shows a timeline
  /// that could animate its fields on this entity — and not during a
  /// play-test, whose values are the game's, not keys.
  static Widget? _timelineKey(FieldAccessoryContext c) {
    final session = TimelineSession.of(c.scope);
    if (!session.isShown ||
        !session.isAuthoring() ||
        session.asset.value == null ||
        session.bindingFor(c.entity) == null) {
      return null;
    }
    final keyable = [
      for (final f in c.fields)
        if (jge.PropertyAccess.canAnimate(f)) f,
    ];
    if (keyable.isEmpty ||
        TimelineSession.unrecorded.contains(c.definition.type)) {
      return null;
    }
    return FieldKeyButton(
      session: session,
      entity: c.entity,
      component: c.component,
      fields: keyable,
    );
  }

  /// An edit through the inspector, recorded while a timeline records.
  static void _recordEdit(EditorScope scope) {
    final session = TimelineSession.of(scope);
    if (session.isShown) session.captureEdits();
  }

  @override
  void onRegister(EditorModuleContext context) {
    // Inline timelines' tracks bound to an entity by name follow its
    // rename, from the tree, the inspector or anywhere else. Keyed, so it
    // is never there twice.
    scope.entities.renameFollowers['timeline'] = (_, from, to) =>
        TimelineRenames.commandFor(scope, from, to);
    scope.dockOpener = (id) => scope.dockController.open(id);
    // Made now rather than when first asked for: it follows the selection
    // and the scene from the start, so a map selected before any tile panel
    // is opened is already the one to paint.
    scope.tiles;
  }
}
