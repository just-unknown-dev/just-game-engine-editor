import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/theme/editor_metrics.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../../../core/state/transform_mode.dart';
import '../../level_designer/level_designer_session.dart';
import '../../level_designer/panels/tool_palette.dart';
import '../settings/overlay_ui_settings.dart';

/// All, Move, Scale and Rotate — V, W, E and R — in a column at the top
/// right of the viewport, in the editor and the Level Designer alike; the
/// designer's tool strip hangs below it.
///
/// Each button picks which gizmo the selection shows; in the designer they
/// are the select tool, so picking one picks that up too. The one showing
/// is lit while the gizmos are in hand. A mode what is selected cannot
/// take is greyed out (a level map only moves; tiles move and turn); with
/// nothing selected every one can be picked, for what is selected next.
/// Gone during a play-test, when the letters are the game's.
class TransformToolbar extends StatelessWidget {
  const TransformToolbar({
    super.key,
    required this.plugin,
    required this.settings,
  });

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) => SignalBuilder<LevelDesignerSession?>(
    signal: plugin.designer,
    builder: (context, session, _) => SignalConsumer(
      signals: [
        plugin.isAuthoring,
        plugin.scope.view.transformMode,
        plugin.sceneState.selectedEntity,
        plugin.sceneState.multiSelectedIds,
        plugin.sceneState.revision,
        plugin.scope.tiles.selection,
        ?session?.controller.toolId,
      ],
      builder: (context, _) => _bar(),
    ),
  );

  Widget _bar() {
    if (!plugin.isAuthoring.value) return const SizedBox.shrink();
    final available = plugin.transformModesAvailable;
    final lit = plugin.isTransformToolInHand
        ? plugin.shownTransformMode ?? plugin.scope.view.transformMode.value
        : null;
    return FloatingToolFrame(
      settings: settings,
      child: SizedBox(
        width: ToolPalette.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in TransformMode.values)
              ToolStripButton(
                icon: mode.icon,
                tooltip: _tooltip(mode),
                shortcut: _keyOf(mode),
                isActive: mode == lit,
                enabled: available.isEmpty || available.contains(mode),
                onTap: () => plugin.chooseTransformMode(mode),
              ),
          ],
        ),
      ),
    );
  }

  /// The key bound to [mode]'s command: V, W, E, R unless a module rebound
  /// it.
  String? _keyOf(TransformMode mode) {
    final bound = plugin.scope.commands.bindingsFor(mode.commandId);
    return bound.isEmpty ? null : bound.first.shortcut;
  }

  String _tooltip(TransformMode mode) {
    final key = _keyOf(mode);
    return key == null ? mode.label : '${mode.label}  ($key)';
  }
}

/// The rounded, bordered frame everything floating over the viewport sits
/// in — the play controls, the transform column, the Level Designer's tool
/// strip, the settings gear — so they read as one set.
class FloatingToolFrame extends StatelessWidget {
  const FloatingToolFrame({
    super.key,
    required this.settings,
    required this.child,
    this.borderColor,
    this.borderWidth = 1,
    this.horizontalPadding = 0,
  });

  final OverlayUiSettings settings;
  final Widget child;

  /// The frame's line; the accent when null. The play controls' frame
  /// takes the play state's colour.
  final Color? borderColor;
  final double borderWidth;
  final double horizontalPadding;

  /// How tall a frame around [content] stands: its padding above and
  /// below, and its line.
  static double heightFor(double content, {double borderWidth = 1}) =>
      content + EditorMetrics.space(6) + borderWidth * 2;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: EditorMetrics.motionFast,
    decoration: BoxDecoration(
      color: EditorTheme.statusBadgeBg,
      borderRadius: BorderRadius.circular(EditorMetrics.radiusLg),
      border: Border.all(
        color: borderColor ?? EditorTheme.accent,
        width: borderWidth,
      ),
    ),
    padding: EdgeInsets.symmetric(
      vertical: EditorMetrics.space(3),
      horizontal: horizontalPadding,
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
