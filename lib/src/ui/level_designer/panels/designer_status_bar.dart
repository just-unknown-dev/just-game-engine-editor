import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../controls/designer_controls.dart';
import '../level_designer_session.dart';
import 'tool_options_bar.dart';
import '../../level_designer_3d/panels/space_status_controls.dart';
import '../../level_designer_3d/aids/ruler_3d.dart';
import '../../../core/scope/editor_scope_services.dart';

/// The strip along the bottom of the designer: at its left the tool in hand
/// and its settings ([ToolOptionsBar]), then snapping options, overlay
/// toggles, the cell under the pointer while painting tiles, and whatever the
/// active tool is currently reporting.
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

  /// Height of the strip: room above and below its 24 px toggles, so their
  /// lit fills sit in the bar rather than filling it edge to edge.
  static const double height = 34;

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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // The controls scroll rather than overflow — extensions add overlays
      // and status controls, so how much there is to show is not the
      // editor's to decide. The status message keeps a fixed share on
      // the right and truncates.
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ToolOptionsBar(session: session),
                    const _SectionDivider(),
                    ..._spaced(_snapControls(controller)),
                    const _SectionDivider(),
                    _overlayToggles(controller),
                    _tileReadout(controller),
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
                  style: TextStyle(
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
      builder: (context, enabled, _) => DesignerToggle(
        icon: Icons.grid_4x4,
        label: 'Snap',
        isOn: enabled,
        tooltip: 'Snapping  (hold Ctrl while dragging to suspend)',
        onTap: () => session.setSnapping(!enabled),
      ),
    ),
    // Smart snapping and the grid in pixels are the 2-D tools'; in space the
    // step is in metres, and things go on the working plane.
    if (_flat)
      ..._snapControls2D(controller)
    else ...[
      MoveStep3DField(scope: session.scope),
      SignalBuilder<bool>(
        signal: session.scope.designer3D.surfaceSnap,
        builder: (context, on, _) => DesignerToggle(
          icon: Icons.vertical_align_bottom,
          label: 'Surface',
          isOn: on,
          tooltip:
              'A move sets things on the surface under the pointer  '
              '(hold V to put a corner on a corner)',
          onTap: () => session.scope.designer3D.surfaceSnap.value = !on,
        ),
      ),
      SignalBuilder<bool>(
        signal: session.scope.designer3D.boundsSnap,
        builder: (context, on, _) => DesignerToggle(
          icon: Icons.border_outer,
          label: 'Bounds',
          isOn: on,
          tooltip: 'A move lines things up with the boxes of things near them',
          onTap: () => session.scope.designer3D.boundsSnap.value = !on,
        ),
      ),
      PivotModeField(scope: session.scope),
      WorkingPlaneControl(
        scope: session.scope,
        selection: session.selectionEntities,
      ),
      PerformanceMeter(scope: session.scope),
    ],
  ];

  bool get _flat => session.scope.sceneState.editingMode == jge.SceneMode.twoD;

  List<Widget> _snapControls2D(LevelDesignerController controller) => [
    SignalBuilder<bool>(
      signal: controller.smartSnap,
      builder: (context, enabled, _) => DesignerToggle(
        icon: Icons.align_horizontal_left,
        label: 'Smart',
        isOn: enabled,
        tooltip:
            'Also snap to other entities’ edges and centres, and to ruler '
            'guides',
        onTap: () => session.setSmartSnap(!enabled),
      ),
    ),
    _GridSizeField(
      value: gridSize,
      sizes: session.scope.config.gridSizes,
      onChanged: onGridSizeChanged,
    ),
  ];

  /// The gap between two toggles side by side: their lit fills stay apart,
  /// each its own target, rather than running into one bar.
  static const double _gap = 6;

  static List<Widget> _spaced(List<Widget> children) => [
    for (var i = 0; i < children.length; i++) ...[
      if (i > 0) const SizedBox(width: _gap),
      children[i],
    ],
  ];

  /// One icon per registered overlay, including any an extension added, with
  /// the name in the tooltip.
  Widget _overlayToggles(LevelDesignerController controller) =>
      SignalBuilder<Set<String>>(
        signal: controller.hiddenOverlays,
        builder: (context, hidden, _) => Row(
          children: _spaced([
            for (final overlay in session.overlays.all)
              DesignerToggle(
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
          ]),
        ),
      );

  /// The cell under the pointer and what it holds, while a tile tool is in
  /// hand.
  Widget _tileReadout(LevelDesignerController controller) =>
      SignalBuilder<String>(
        signal: controller.toolId,
        builder: (context, _, _) => controller.activeGroup != ToolGroups.tiles
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _TileHoverReadout(session: session),
              ),
      );
}

/// Between the tool's own settings and the designer's.
class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: EditorTheme.border,
  );
}

/// The cell under the pointer and what it holds.
class _TileHoverReadout extends StatelessWidget {
  const _TileHoverReadout({required this.session});

  final LevelDesignerSession session;

  /// What [session]'s painted layer holds at [cell], for the status bar.
  static String describe(LevelDesignerSession session, jge.TileCoord cell) {
    final tiles = session.scope.tiles;
    final target = tiles.peek(session.world);
    final layer = target == null ? null : tiles.peekLayer(target);
    final where = '${cell.x}, ${cell.y}';
    if (target == null || layer == null) return where;
    final value = layer.cells.cellAt(cell.x, cell.y);
    if (jge.TileCell.isEmpty(value)) return '$where · empty';
    final ts = target.tilesetAt(jge.TileCell.slotOf(value));
    final id = jge.TileCell.localIdOf(value);
    final turned = [
      if (jge.TileCell.isFlippedH(value)) 'H',
      if (jge.TileCell.isFlippedV(value)) 'V',
      if (jge.TileCell.isFlippedD(value)) 'D',
      if (jge.TileCell.isRotated120(value)) 'R',
    ].join();
    return '$where · ${ts?.name ?? 'missing tileset'} #$id'
        '${turned.isEmpty ? '' : ' ($turned)'}';
  }

  @override
  Widget build(BuildContext context) => SignalBuilder<jge.TileCoord?>(
    signal: session.scope.tiles.hover,
    builder: (context, cell, _) => cell == null
        ? const SizedBox.shrink()
        : Text(
            describe(session, cell),
            style: TextStyle(
              color: EditorTheme.textSecondary,
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
  );
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
    // A popup menu rather than a DropdownButton. The status bar sits at the
    // foot of the window — flush with it when the status strip is hidden —
    // and a DropdownButton there fails an assertion
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
              style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
            ),
            Icon(
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
