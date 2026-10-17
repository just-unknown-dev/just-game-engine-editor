library;

export 'package:just_editor_core/just_editor_core.dart';
export 'src/ui/dialogs/create_scene_overlay.dart';
export 'src/ui/overlay/editor_overlay.dart' show JustGameEditorOverlay;
export 'src/core/plugin/editor_plugin.dart';
// Where `packages/<name>/…` assets are on disk: the Asset Store's items, and
// any other package that ships assets.
export 'src/core/play/play_controller.dart';
export 'src/core/scene/scene_io.dart';
export 'src/core/prefabs/prefab_instances.dart';
export 'src/core/scene/scene_loading.dart';
export 'src/core/entity/entity_ops.dart';
export 'src/core/input/viewport_input.dart';
export 'src/core/serialization/editor_serialization_service.dart';
export 'src/ui/panels/entity_inspector_panel.dart';
export 'src/integration/just_game_editor_adapter.dart';
export 'src/ui/overlay/gizmo_painter.dart';
export 'src/ui/overlay/transform_gizmo.dart';
export 'src/ui/overlay/viewport_menu.dart' show showViewportMenu;
export 'src/core/serialization/scene_manager.dart';
export 'src/core/serialization/scene_name_validator.dart';
export 'src/ui/panels/scene_picker_panel.dart';
export 'src/ui/scene_tree/scene_tree_controller.dart';
export 'src/ui/scene_tree/scene_tree_panel.dart';
export 'src/core/validation/built_in_validators.dart';
export 'src/core/validation/physics_checks.dart';
export 'src/core/validation/tag_checks.dart';
export 'src/core/ecs/systems/editor_log_capture_system.dart';
export 'src/core/ecs/systems/physics_body_binding_system.dart';

// One editor's registries, services and state — and the modules that
// contribute to it.
export 'src/core/scope/editor_scope_services.dart';
export 'src/extension/built_in_editor_module.dart';
export 'src/core/view/planar_entity_picker.dart';
export 'src/core/view/orbit_fly_editor_view.dart';
export 'src/core/input/gizmo_drag_solver.dart';
export 'src/core/input/ray_gizmo_drag_solver.dart';
export 'src/core/input/selection_pivot.dart';
export 'src/core/input/translate_snaps_3d.dart';
export 'src/ui/overlay/gizmo_3d.dart';
export 'src/ui/level_designer/commands/editor_command_context.dart';
export 'src/ui/overlay/docks/dock_controller.dart';

// Editor chrome constants, so an extension's own panels can match the editor
// rather than looking bolted on.

// The inspector: which control edits which field type, and what the editor
// adds to a component beyond its fields.
export 'src/ui/inspector/tag_field_editors.dart';
export 'src/ui/inspector/entity_header.dart';
export 'src/core/tags/tag_refactor.dart';
export 'src/core/tags/tag_edits.dart';
export 'src/extension/built_in_tag_contributions.dart';
export 'src/ui/overlay/docks/tags/tags_dock.dart';
export 'src/ui/inspector/property_table_editor.dart';
export 'src/ui/inspector/physics_shape_editor.dart';
export 'src/ui/inspector/physics_field_editors.dart';
export 'src/ui/inspector/physics/physics_body_extras.dart';
export 'src/ui/inspector/physics/collider_edit_session.dart';
export 'src/ui/overlay/docks/physics/physics_layers_dock.dart';
export 'src/core/physics/layer_refactor.dart';
export 'src/ui/inspector/built_in_field_editors.dart';

// Level Designer — the dedicated level-authoring workspace.
export 'src/ui/level_designer/level_designer.dart';
export 'src/extension/built_in_3d_designer_contributions.dart';
export 'src/ui/overlay/camera_rig_painter.dart';
export 'src/extension/built_in_camera_contributions.dart';
// Sound in the editor: source and listener markers, a 3-D source's range,
// the Audio prefabs, audio files dropped as sources.
export 'src/extension/built_in_audio_contributions.dart';
export 'src/extension/built_in_lighting_2d_contributions.dart';
// 3-D physics in the editor: collider outlines, scene checks, Solid and
// Trigger shapes — built in, for projects whose engine has Physics3D.
export 'src/extension/built_in_physics_3d_contributions.dart';
export 'src/core/physics/collider_overlay_3d.dart';
export 'src/core/physics/hull_outline.dart';
export 'src/core/validation/physics_3d_checks.dart';
export 'src/extension/built_in_tile_contributions.dart';
export 'src/core/level_map/tile_commands.dart';
export 'src/core/level_map/tile_edit_state.dart';
export 'src/core/level_map/level_map_documents.dart';
export 'src/core/level_map/level_map_focus.dart';
export 'src/core/level_map/level_map_provision.dart';
export 'src/core/level_map/tile_selection_ops.dart';
export 'src/core/level_map/tiles_to_entity.dart';
export 'src/core/level_map/tile_turn.dart';
export 'src/core/level_map/tiled_export.dart';
export 'src/core/level_map/tiled_import.dart';
export 'src/ui/tileset/collision_shape_editor.dart';
export 'src/ui/tileset/create_tileset_dialog.dart';
export 'src/ui/tileset/tile_animation_editor.dart';
export 'src/ui/tileset/tile_properties_editor.dart';
export 'src/ui/tileset/tileset_session.dart';
export 'src/ui/tileset/tileset_workspace.dart';
export 'src/ui/tileset/wang_set_editor.dart';
