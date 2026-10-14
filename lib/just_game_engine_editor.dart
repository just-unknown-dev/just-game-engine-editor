library;

export 'src/ui/dialogs/add_component_picker.dart';
export 'src/core/ecs/registry/component_registry.dart';
export 'src/ui/dialogs/create_scene_overlay.dart';
export 'src/ui/overlay/editor_overlay.dart' show JustGameEditorOverlay;
export 'src/ui/overlay/shared/snackbar.dart'
    show
        EditorMessenger,
        EditorSnack,
        EditorSnackBarController,
        EditorSnackBarEntry,
        EditorSnackBarStep,
        EditorSnackBarType;
export 'src/core/plugin/editor_plugin.dart';
// Where `packages/<name>/…` assets are on disk: the Asset Store's items, and
// any other package that ships assets.
export 'src/core/assets/package_asset_paths.dart';
export 'src/core/play/play_controller.dart';
export 'src/core/scene/editor_scene.dart';
export 'src/core/scene/scene_io.dart';
export 'src/core/entity/entity_ops.dart';
export 'src/core/entity/hierarchy_commands.dart';
export 'src/core/state/editor_view_state.dart';
export 'src/core/state/transform_mode.dart';
export 'src/core/input/handle_drag_session.dart';
export 'src/core/input/viewport_input.dart';
export 'src/core/state/editor_scene_state.dart';
export 'src/core/serialization/editor_serialization_service.dart';
export 'src/ui/panels/entity_inspector_panel.dart';
export 'src/integration/just_game_editor_adapter.dart';
export 'src/ui/overlay/gizmo_painter.dart';
export 'src/ui/overlay/transform_gizmo.dart';
export 'src/ui/overlay/viewport_menu.dart' show showViewportMenu;
export 'src/core/serialization/scene_codec.dart';
export 'src/core/serialization/scene_store.dart';
export 'src/core/serialization/unknown_components.dart';
export 'src/core/serialization/scene_manager.dart';
export 'src/core/serialization/scene_name_validator.dart';
export 'src/core/services/editor_log_service.dart';
export 'src/ui/panels/scene_picker_panel.dart';
export 'src/ui/scene_tree/scene_tree_controller.dart';
export 'src/ui/scene_tree/scene_tree_model.dart';
export 'src/ui/scene_tree/scene_tree_panel.dart';
export 'src/ui/scene_tree/scene_tree_row.dart';
export 'src/ui/widgets/scrubbable_number_field.dart';
export 'src/ui/kit/kit.dart';
export 'src/core/theme/editor_metrics.dart';
export 'src/ui/inspector/field_style.dart';
export 'src/ui/inspector/edge_insets_row.dart';
export 'src/core/validation/scene_validator.dart';
export 'src/ui/widgets/editor_dropdown.dart';
export 'src/ui/widgets/editor_menu.dart';
export 'src/ui/widgets/editor_scrollbar.dart';
export 'src/core/ecs/systems/editor_log_capture_system.dart';
export 'src/core/ecs/systems/physics_body_binding_system.dart';

// One editor's registries, services and state — and the modules that
// contribute to it.
export 'src/core/scope/editor_scope.dart';
export 'src/core/view/editor_view.dart';
export 'src/core/view/entity_picker.dart';
export 'src/core/view/orbit_fly_editor_view.dart';
export 'src/core/view/ray_entity_picker.dart';
export 'src/core/input/gizmo_drag_solver.dart';
export 'src/core/input/ray_gizmo_drag_solver.dart';
export 'src/extension/asset_kind.dart';
export 'src/extension/editor_marker.dart';
export 'src/extension/prefab_variant.dart';
export 'src/extension/viewport_handles.dart';
export 'src/extension/viewport_overlay.dart';
export 'src/ui/overlay/gizmo_3d.dart';
export 'src/extension/editor_module.dart';
export 'src/extension/designer_contributions.dart';
export 'src/extension/editor_contributions.dart';
export 'src/core/prefs/editor_prefs.dart';
export 'src/core/theme/editor_theme_data.dart';
export 'src/core/theme/theme_controller.dart';
export 'src/ui/overlay/docks/dock_controller.dart';
export 'src/ui/overlay/chrome_state.dart' show EditorChromeState;
export 'src/ui/overlay/settings/overlay_ui_settings.dart';

// Editor chrome constants, so an extension's own panels can match the editor
// rather than looking bolted on.
export 'src/core/constants/editor_constants.dart'
    show EditorTheme, OverlayLayout, GizmoConstants, kComponentGroups;

// The inspector: which control edits which field type, and what the editor
// adds to a component beyond its fields.
export 'src/ui/inspector/field_editor.dart';
export 'src/ui/inspector/tag_field_editors.dart';
export 'src/ui/inspector/entity_header.dart';
export 'src/core/tags/project_tags.dart';
export 'src/core/tags/tag_references.dart';
export 'src/core/tags/tag_refactor.dart';
export 'src/core/tags/tag_edits.dart';
export 'src/extension/built_in_tag_contributions.dart';
export 'src/ui/overlay/docks/tags/tags_dock.dart';
export 'src/ui/inspector/field_rows.dart';
export 'src/ui/inspector/property_table_editor.dart';
export 'src/ui/inspector/component_extras.dart';
export 'src/ui/inspector/definition_section.dart';
export 'src/ui/inspector/physics_shape_editor.dart';
export 'src/ui/inspector/physics_field_editors.dart';
export 'src/ui/inspector/physics/physics_body_extras.dart';
export 'src/ui/inspector/physics/collider_edit_session.dart';
export 'src/ui/overlay/docks/physics/physics_layers_dock.dart';
export 'src/core/physics/project_physics_layers.dart';
export 'src/core/colours/project_colours.dart';
export 'src/core/theme/editor_material_theme.dart';
export 'src/ui/inspector/colour_picking.dart';
export 'src/ui/inspector/live_preview.dart';
export 'src/core/physics/layer_refactor.dart';
export 'src/ui/inspector/built_in_field_editors.dart';

// Level Designer — the dedicated level-authoring workspace.
export 'src/ui/level_designer/level_designer.dart';
export 'src/ui/overlay/camera_rig_painter.dart';
export 'src/extension/built_in_camera_contributions.dart';
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
export 'src/extension/tiled_object_mapper.dart';
export 'src/ui/tileset/collision_shape_editor.dart';
export 'src/ui/tileset/create_tileset_dialog.dart';
export 'src/ui/tileset/tile_animation_editor.dart';
export 'src/ui/tileset/tile_properties_editor.dart';
export 'src/ui/tileset/tileset_session.dart';
export 'src/ui/tileset/tileset_workspace.dart';
export 'src/ui/tileset/wang_set_editor.dart';
export 'src/ui/inspector/collection_editor.dart';
