import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import '../core/scope/editor_scope_services.dart';
import '../core/view/orbit_fly_editor_view.dart';
import '../ui/inspector/built_in_extras.dart';
import '../ui/inspector/built_in_field_editors.dart';
import '../ui/inspector/physics/physics_body_extras.dart';
import '../ui/level_designer/commands/built_in_bindings.dart';
import '../ui/level_designer/commands/built_in_commands.dart';
import '../ui/level_designer/state/built_in_prefabs.dart';
import '../ui/tileset/built_in_workspaces.dart';
import '../ui/timeline/field_key_button.dart';
import '../ui/timeline/timeline_session.dart';
import '../core/prefabs/prefab_files.dart';
import '../ui/inspector/prefab_inspector.dart';
import 'built_in_3d_designer_contributions.dart';
import 'built_in_audio_contributions.dart';
import 'built_in_camera_contributions.dart';
import 'built_in_physics_3d_contributions.dart';
import 'built_in_row_decorations.dart';
import 'built_in_tag_contributions.dart';
import 'built_in_tile_contributions.dart';

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
  BuiltInEditorModule(this.scope);

  /// The scope it belongs to.
  final EditorScope scope;

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
  bool get _physics3D => BuiltInPhysics3DContributions.appliesTo(scope.context);

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
  List<DesignerCommand> get commands => BuiltInCommands.all;

  @override
  List<KeyBinding> get keyBindings => BuiltInBindings.of(scope.config);

  /// The default kits' palettes: the 2-D shapes and the 3-D ones, each
  /// offered in its own kind of scene.
  @override
  List<PrefabDefinition> get prefabs => [
    ...BuiltInPrefabs.all,
    ...BuiltIn3DDesignerContributions.prefabs,
  ];

  late final EntityRayTest _shapeTest =
      BuiltIn3DDesignerContributions.shapeTest();

  @override
  List<EntityRayTest> get pickTests => [_shapeTest];

  /// Prefab files: dropped on the viewport, an instance of one.
  @override
  List<AssetKind> get assetKinds => const [PrefabFiles.kind];

  @override
  List<PrefabPicture> get prefabPictures =>
      BuiltIn3DDesignerContributions.prefabPictures;

  @override
  List<ViewportHandles> get viewportHandles =>
      BuiltIn3DDesignerContributions.viewportHandles;

  @override
  List<PrefabCategory> get prefabCategories => BuiltInPrefabs.categories;

  @override
  List<WorkspaceDefinition> get workspaces => BuiltInWorkspaces.all;

  @override
  List<EditorMarker> get markers => [
    ...EditorMarker.builtIn,
    ...BuiltInAudioContributions.markers,
  ];

  @override
  List<ViewportOverlay> get viewportOverlays => [
    ...BuiltInAudioContributions.viewportOverlays,
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

  /// The key button after a row, while a timeline is open that could
  /// animate its fields on this entity.
  static Widget? _timelineKey(FieldAccessoryContext c) {
    final session = TimelineSession.of(c.scope);
    if (session.asset.value == null || session.bindingFor(c.entity) == null) {
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
  static void _recordEdit(EditorScope scope) =>
      TimelineSession.of(scope).captureEdits();

  @override
  void onRegister(EditorModuleContext context) {
    scope.dockOpener = (id) => scope.dockController.open(id);
    // Made now rather than when first asked for: it follows the selection
    // and the scene from the start, so a map selected before any tile panel
    // is opened is already the one to paint.
    scope.tiles;
  }
}
