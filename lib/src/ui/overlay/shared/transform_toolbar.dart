import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../../level_designer/level_designer_session.dart';
import '../../level_designer/panels/tool_palette.dart';
import '../../../core/scope/editor_scope_services.dart';

/// All, Move, Scale and Rotate — Q, W, E and R — in a column at the top
/// right of the viewport, in the editor and the Level Designer alike; the
/// editor's own features ([ToolColumnButtons]) and the designer's tool
/// strip hang below it.
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

  /// How tall it stands while showing: a strip button per mode, in the
  /// frame.
  static double get height => FloatingToolFrame.heightFor(
    ToolStripButton.extent * TransformMode.values.length,
  );

  @override
  Widget build(BuildContext context) => SignalBuilder<LevelDesignerSession?>(
    signal: plugin.designer,
    builder: (context, session, _) => ThrottledSignalConsumer(
      // Which modes the selection offers can change with an edit; not
      // every move of a drag.
      often: plugin.sceneState.revision,
      signals: [
        plugin.isAuthoring,
        plugin.sceneState.activeScene,
        plugin.scope.view.transformMode,
        plugin.sceneState.selectedEntity,
        plugin.sceneState.multiSelectedIds,
        plugin.scope.tiles.selection,
        ?session?.controller.toolId,
      ],
      builder: (context) => _bar(),
    ),
  );

  Widget _bar() {
    // Nothing to transform with no scene open.
    if (!plugin.isAuthoring.value || !plugin.sceneState.hasScene) {
      return const SizedBox.shrink();
    }
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

  /// The key bound to [mode]'s command: Q, W, E, R unless a module rebound
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

/// The buttons that stand in a frame of their own under the
/// [TransformToolbar] ([ToolbarSlot.toolColumn]): features of the editor
/// itself rather than a module's tools, such as the Asset Store. As wide as
/// the column, with its buttons; up in the transform tools' place while
/// they are gone (no scene, a play-test); nothing when there are none.
class ToolColumnButtons extends StatelessWidget {
  const ToolColumnButtons({
    super.key,
    required this.plugin,
    required this.settings,
  });

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;

  /// The buttons that stand here, in order.
  static List<ToolbarButton> buttonsOf(EditorScope scope) => [
    for (final b in scope.toolbarButtons)
      if (b.slot == ToolbarSlot.toolColumn) b,
  ];

  /// How tall [count] of them stand, in their frame; nothing for none.
  static double heightFor(int count) => count == 0
      ? 0
      : FloatingToolFrame.heightFor(ToolStripButton.extent * count);

  @override
  Widget build(BuildContext context) {
    final scope = plugin.scope;
    final buttons = buttonsOf(scope);
    if (buttons.isEmpty) return const SizedBox.shrink();
    // A button lit while its workspace is open (`isActive`) has to hear the
    // workspace open and close.
    return SignalBuilder<OpenWorkspace?>(
      signal: scope.activeWorkspace,
      builder: (context, _, _) => FloatingToolFrame(
        settings: settings,
        child: SizedBox(
          width: ToolPalette.width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final b in buttons)
                ToolStripButton(
                  icon: b.icon,
                  tooltip: b.tooltip,
                  isActive: b.isActive?.call(scope) ?? false,
                  enabled: b.isEnabled?.call(scope) ?? true,
                  onTap: () => b.onPressed(scope),
                ),
            ],
          ),
        ),
      ),
    );
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
    this.backgroundColor,
    this.borderWidth = 1,
    this.horizontalPadding = 0,
  });

  final OverlayUiSettings settings;
  final Widget child;

  /// The frame's line; the accent when null. The play controls' frame
  /// takes the play state's colour.
  final Color? borderColor;

  /// The frame's fill; the badge colour when null. The play controls'
  /// frame takes a tint of the play state's colour.
  final Color? backgroundColor;
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
      color: backgroundColor ?? EditorTheme.statusBadgeBg,
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
