/// The Level Designer — a dedicated authoring workspace layered over the
/// existing editor overlay.
///
/// Toggled from the play-controls toolbar. With it off, the overlay behaves
/// exactly as it always has; with it on, the viewport gains a tool palette,
/// marquee selection, multi-entity manipulation, layers, a prefab palette and
/// a full undo stack.
///
/// Everything here is debug-only: the editor package is never part of a
/// shipped build.
library;

export 'level_designer_session.dart';
export 'level_designer_workspace.dart';
export 'panels/align_bar.dart';
export 'panels/designer_status_bar.dart';
export 'panels/designer_switch.dart';
export 'panels/level_layers_panel.dart';
export 'panels/prefab_palette_panel.dart';
export 'panels/tileset_palette_panel.dart';
export 'panels/tool_options_bar.dart';
export 'panels/tool_palette.dart';
export 'controls/designer_controls.dart';
export 'grid/hex_grid.dart';
export 'commands/built_in_bindings.dart';
export 'commands/built_in_commands.dart';
export 'state/component_resizer.dart';
export 'state/selection_ops.dart';
export 'state/map_placement.dart';
export 'overlays/built_in_overlays.dart';
export 'overlays/measurement_overlay.dart';
export 'overlays/minimap_overlay.dart';
export 'overlays/tile_overlays.dart';
export 'overlays/transform_overlays.dart';
export 'painters/level_designer_painter.dart';
export 'state/built_in_prefabs.dart';
export 'tools/draw_rect_tool.dart';
export 'tools/measure_tool.dart';
export 'tools/paint_tool.dart';
export 'tools/select_tool.dart';
export 'tools/tiles/tile_brush_tools.dart';
export 'tools/tiles/tile_select_tool.dart';
export 'tools/tiles/tile_terrain_tool.dart';
export 'tools/tiles/tile_tool_base.dart';
export '../tileset/built_in_workspaces.dart';

// The default kit for 3-D scenes.
export '../level_designer_3d/overlays/marquee_3d_overlay.dart';
export '../level_designer_3d/overlays/place_ghost_3d_overlay.dart';
export '../level_designer_3d/panels/array_3d_panel.dart';
export '../level_designer_3d/panels/groups_3d_panel.dart';
export '../level_designer_3d/panels/materials_3d_panel.dart';
export '../level_designer_3d/tools/material_paint_3d_tool.dart';
export '../level_designer_3d/shapes/shape_pictures.dart';
export '../level_designer_3d/panels/space_status_controls.dart';
export '../level_designer_3d/panels/view_3d_panel.dart';
export '../level_designer_3d/panels/view_cube.dart';
export '../level_designer_3d/shapes/polygon_handles.dart';
export '../level_designer_3d/shapes/collider_size_handles.dart';
export '../level_designer_3d/shapes/face_handles.dart';
export '../level_designer_3d/shapes/shape_size_handles.dart';
export '../level_designer_3d/split/split_views.dart';
export '../level_designer_3d/shapes/shape_prefabs.dart';
export '../level_designer_3d/shapes/shape_ray_test.dart';
export '../level_designer_3d/tools/place_3d_tool.dart';
export '../level_designer_3d/tools/select_3d_tool.dart';
