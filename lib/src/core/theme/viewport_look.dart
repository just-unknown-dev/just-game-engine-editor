import 'package:flutter/painting.dart';

import '../../ui/overlay/settings/overlay_ui_settings.dart';

/// How the viewport draws what the editor adds to the game — the grid, the
/// handles, the selection — as the settings make it.
///
/// Read by painters, which run on the engine's canvas outside any widget,
/// so like `EditorMetrics` these are statics: the plugin applies the
/// settings, and the next frame paints with them.
abstract final class ViewportLook {
  static OverlayUiSettings _s = const OverlayUiSettings.defaults();

  /// Takes the look from [s].
  static void apply(OverlayUiSettings s) => _s = s;

  /// A grid line at [alpha] of full strength, as the settings colour and
  /// strengthen it: `gridLine(0.14)` for a major line, drawn as before at
  /// the defaults.
  static Color gridLine(double alpha) => _s.gridColour.withValues(
    alpha: (alpha * _s.gridOpacity).clamp(0.0, 1.0).toDouble(),
  );

  /// How big the move, scale and turn handles are drawn, and how far off a
  /// pointer still takes hold of one: 1 is as built.
  static double get gizmoScale => _s.gizmoScale;

  /// The outline round what is selected in the editor's view.
  static Color get selection => _s.selectionColour ?? const Color(0xFF40E0D0);

  /// The outline round what is selected in the Level Designer.
  static Color get designerSelection =>
      _s.selectionColour ?? const Color(0xFF5AC8FA);
}
