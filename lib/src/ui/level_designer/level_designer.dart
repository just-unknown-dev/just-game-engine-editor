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
export 'panels/layers_panel.dart';
export 'panels/prefab_palette_panel.dart';
export 'panels/tool_palette.dart';
export 'panels/transform_panel.dart';
export 'grid/grid_topology.dart';
export 'grid/hex_grid.dart';
export 'grid/square_grid.dart';
export 'commands/built_in_bindings.dart';
export 'commands/built_in_commands.dart';
export 'commands/designer_command.dart';
export 'state/component_resizer.dart';
export 'state/designer_config.dart';
export 'state/modifier_keys.dart';
export 'state/selection_handle_layout.dart';
export 'state/selection_ops.dart';
export 'state/smart_snap.dart';
export 'state/snap_provider.dart';
export 'state/designer_geometry.dart';
export 'state/editor_commands.dart';
export 'state/level_designer_controller.dart';
export 'overlays/built_in_overlays.dart';
export 'overlays/designer_overlay.dart';
export 'overlays/measurement_overlay.dart';
export 'overlays/minimap_overlay.dart';
export 'overlays/transform_overlays.dart';
export 'painters/designer_canvas.dart';
export 'painters/level_designer_painter.dart';
export 'state/layer_preset.dart';
export 'state/built_in_prefabs.dart';
export 'state/prefab_registry.dart';
export 'tools/draw_rect_tool.dart';
export 'tools/measure_tool.dart';
export 'tools/paint_tool.dart';
export 'tools/path_tool.dart';
export 'tools/select_tool.dart';
export 'tools/tool_registry.dart';
export 'tools/level_tool.dart';
export 'state/editor_history.dart';
export 'ui_mode/ui_device.dart';
export 'ui_mode/ui_mode_overlay.dart';
export 'ui_mode/ui_mode_session.dart';
export 'ui_mode/ui_workspace.dart';
