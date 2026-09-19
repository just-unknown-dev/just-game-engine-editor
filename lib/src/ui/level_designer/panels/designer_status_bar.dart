import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../level_designer_session.dart';
import '../state/level_designer_controller.dart';
import '../tools/tool_registry.dart';

/// The strip along the bottom of the designer: snapping options, overlay
/// toggles, and whatever the active tool is currently reporting.
class DesignerStatusBar extends StatelessWidget {
  const DesignerStatusBar({
    super.key,
    required this.session,
    required this.gridSize,
    required this.onGridSizeChanged,
  });

  /// The designer session this reflects.
  final LevelDesignerSession session;

  /// Current grid size, owned by the plugin's overlay settings.
  final double gridSize;

  /// Called when the grid size is changed here, so the plugin and the settings
  /// dialog stay in agreement.
  final ValueChanged<double> onGridSizeChanged;

  /// Height of the strip.
  static const double height = 30;

  @override
  Widget build(BuildContext context) => SignalBuilder<String?>(
    // Everything below follows the designer in use.
    signal: session.scope.activeDesigner,
    builder: (context, _, _) => _buildBar(context),
  );

  Widget _buildBar(BuildContext context) {
    final controller = session.controller;

    return Container(
      height: height,
      color: EditorTheme.surfaceDark,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      // The controls scroll rather than overflow — extensions add overlays
      // and the paint tool adds its modes, so how much there is to show is
      // not the editor's to decide. The status message keeps a fixed share on
      // the right and truncates.
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ..._snapControls(controller),
                    const SizedBox(width: 12),
                    _overlayToggles(controller),
                    _paintControls(controller),
                    // What the modules add, after the built-ins.
                    for (final control in session.scope.statusControls) ...[
                      const SizedBox(width: 8),
                      Builder(
                        builder: (context) => control.build(context, session),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: math.min(320, constraints.maxWidth * 0.35),
              child: SignalBuilder<String>(
                signal: controller.status,
                builder: (context, status, _) => Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: EditorTheme.textSecondary,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _snapControls(LevelDesignerController controller) => [
    SignalBuilder<bool>(
      signal: controller.snapEnabled,
      builder: (context, enabled, _) => _Toggle(
        icon: Icons.grid_4x4,
        label: 'Snap',
        isOn: enabled,
        tooltip: 'Snapping  (hold Ctrl while dragging to suspend)',
        onTap: () => controller.snapEnabled.value = !enabled,
      ),
    ),
    SignalBuilder<bool>(
      signal: controller.smartSnap,
      builder: (context, enabled, _) => _Toggle(
        icon: Icons.align_horizontal_left,
        label: 'Smart',
        isOn: enabled,
        tooltip:
            'Also snap to other entities’ edges and centres, and to ruler '
            'guides',
        onTap: () => controller.smartSnap.value = !enabled,
      ),
    ),
    _GridSizeField(
      value: gridSize,
      sizes: session.scope.config.gridSizes,
      onChanged: onGridSizeChanged,
    ),
  ];

  /// One icon per registered overlay, including any an extension added, with
  /// the name in the tooltip.
  Widget _overlayToggles(LevelDesignerController controller) =>
      SignalBuilder<Set<String>>(
        signal: controller.hiddenOverlays,
        builder: (context, hidden, _) => Row(
          children: [
            for (final overlay in session.overlays.all)
              _Toggle(
                icon: overlay.icon,
                isOn: !hidden.contains(overlay.id),
                tooltip: overlay.description == null
                    ? overlay.label
                    : '${overlay.label}: ${overlay.description}',
                onTap: () => controller.setOverlayVisible(
                  overlay.id,
                  visible: hidden.contains(overlay.id),
                ),
              ),
          ],
        ),
      );

  /// Paint modes and brush size, shown only while painting — the rest of the
  /// time they would be clutter that implies they do something.
  Widget _paintControls(LevelDesignerController controller) =>
      SignalBuilder2<String, PaintMode>(
        signal1: controller.toolId,
        signal2: controller.paintMode,
        builder: (context, toolId, mode, _) {
          if (toolId != BuiltInTools.paint) return const SizedBox.shrink();
          return Row(
            children: [
              const SizedBox(width: 12),
              for (final entry in const [
                (mode: PaintMode.brush, icon: Icons.brush, label: 'Brush'),
                (
                  mode: PaintMode.rectangle,
                  icon: Icons.crop_square,
                  label: 'Rect',
                ),
                (
                  mode: PaintMode.eraser,
                  icon: Icons.cleaning_services,
                  label: 'Erase',
                ),
                (
                  mode: PaintMode.fill,
                  icon: Icons.format_color_fill,
                  label: 'Fill',
                ),
              ])
                _Toggle(
                  icon: entry.icon,
                  label: entry.label,
                  isOn: mode == entry.mode,
                  tooltip: entry.mode == PaintMode.fill
                      ? 'Fill the enclosed empty region you click'
                      : entry.label,
                  onTap: () => controller.paintMode.value = entry.mode,
                ),
              // Brush width only affects the brush and the eraser.
              if (mode == PaintMode.brush || mode == PaintMode.eraser)
                SignalBuilder<int>(
                  signal: controller.brushSize,
                  builder: (context, size, _) => Row(
                    children: [
                      const SizedBox(width: 8),
                      for (final option in const [1, 3, 5])
                        _Toggle(
                          icon: Icons.grid_on,
                          label: '$option',
                          isOn: size == option,
                          tooltip: '$option × $option brush  ([ and ])',
                          onTap: () => controller.brushSize.value = option,
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.isOn,
    required this.tooltip,
    required this.onTap,
    this.label,
  });

  final IconData icon;

  /// Shown beside the icon; null for an icon-only toggle, whose name is then
  /// in the tooltip.
  final String? label;
  final bool isOn;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isOn ? EditorTheme.primaryBright : EditorTheme.textMuted,
              ),
              if (label != null) ...[
                const SizedBox(width: 4),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 11,
                    color: isOn
                        ? EditorTheme.textBright
                        : EditorTheme.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Steps the grid size through the usual power-of-two sizes.
///
/// A slider would be wrong here: grid sizes that are not powers of two do not
/// tile against each other, so free choice mostly produces levels that will
/// not line up.
class _GridSizeField extends StatelessWidget {
  const _GridSizeField({
    required this.value,
    required this.sizes,
    required this.onChanged,
  });

  /// The sizes on offer; the scope's config.
  final List<double> sizes;

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = sizes.contains(value)
        ? value
        : (sizes.isEmpty ? 32.0 : sizes.first);
    // A popup menu rather than a DropdownButton. The status bar is flush with
    // the bottom of the window, and a DropdownButton there fails an assertion
    // as it opens: it centres the selected item over a button shorter than
    // an item, pushing the menu past the bottom edge. A popup menu is kept on
    // screen and opens upward when there is no room below.
    return PopupMenuButton<double>(
      tooltip: 'Grid size',
      initialValue: current,
      color: EditorTheme.menuBg,
      position: PopupMenuPosition.over,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final size in sizes)
          PopupMenuItem(
            value: size,
            height: 30,
            child: Text(
              '${size.toInt()}px',
              style: TextStyle(
                color: size == current
                    ? EditorTheme.textPrimary
                    : EditorTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${current.toInt()}px',
              style: const TextStyle(
                color: EditorTheme.textSecondary,
                fontSize: 11,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: EditorTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
