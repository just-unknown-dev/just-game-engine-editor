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
