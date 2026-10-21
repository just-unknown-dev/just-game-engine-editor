import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' show SceneMode;

import 'package:just_editor_core/host.dart';
import '../../level_designer/panels/tool_palette.dart';
import '../../level_designer_3d/panels/space_status_controls.dart';
import 'gizmo_menu.dart';
import 'transform_toolbar.dart';

/// Which of the bar's panels is out.
enum _Row { none, gizmos, snap, grid }

/// What is drawn and how things move, at hand, standing on the settings
/// gear: the gizmos of the editor's mode now ([mode]) shown or hidden, then
/// — while editing — the one snap switch (the Level Designer's Snap is the
/// same) above the grid, shown or not. Right-click any and a panel slides
/// out to its left: which gizmos, the step moving snaps in, or the grid's
/// size.
class QuickSnapBar extends StatefulWidget {
  const QuickSnapBar({
    super.key,
    required this.scope,
    required this.settings,
    required this.mode,
    this.snapping = true,
  });

  final EditorScope scope;
  final OverlayUiSettings settings;

  /// Whose gizmos the top button shows and hides: the editor's, the Level
  /// Designer's or a play-test's, each its own.
  final GizmoMode mode;

  /// Whether snapping and the grid are under it: not in a play-test, where
  /// only the gizmos are.
  final bool snapping;

  /// The commands its buttons run: no keys of their own until one is
  /// given them on the Keyboard page.
  static const String gizmosCommandId = 'editor.gizmos.toggle';
  static const String snapCommandId = 'editor.snap.toggle';
  static const String gridCommandId = 'editor.grid.toggle';

  /// The steps the snap row offers, in world units; 0 is the grid's own.
  static const List<double> steps = [0, 1, 2, 4, 8, 16, 32, 64];

  /// How tall it stands, for what has to clear it: three of the tool
  /// strip's buttons, one above the other, in the frame the strip has; one
  /// without [snapping].
  static double heightFor({bool snapping = true}) =>
      FloatingToolFrame.heightFor(ToolStripButton.extent * (snapping ? 3 : 1));

  /// [step] as the rows and the settings write it: `8`, `0.5`.
  static String formatStep(double step) =>
      step == step.roundToDouble() ? step.toInt().toString() : step.toString();

  @override
  State<QuickSnapBar> createState() => _QuickSnapBarState();
}

class _QuickSnapBarState extends State<QuickSnapBar> {
  _Row _open = _Row.none;

  EditorScope get _scope => widget.scope;

  String? _key(String commandId) {
    final bound = _scope.commands.bindingsFor(commandId);
    return bound.isEmpty ? null : bound.first.shortcut;
  }

  /// Right-click: [row] out, or away if it was — and the others away.
  void _toggle(_Row row) =>
      setState(() => _open = _open == row ? _Row.none : row);

  void _close() {
    if (_open != _Row.none) setState(() => _open = _Row.none);
  }

  /// Moving snaps in [step] from now — and snapping is on, since a step
  /// was asked for.
  void _pickStep(double step) {
    _scope.prefs.change(
      (s) => s.copyWith(moveStep: step, gridSnappingEnabled: true),
    );
    _close();
  }

  /// The grid is [size] from now — and shown, since a size was asked for.
  void _pickGrid(double size) {
    _scope.prefs.change((s) => s.copyWith(gridSize: size, showGrid: true));
    _close();
  }

  /// In space: moving snaps in [metres], and the grid is drawn at it —
  /// snapping on when a step was asked for, the grid shown when a size was.
  void _pickStep3D(double metres, {bool grid = false}) {
    _scope.prefs.change(
      (s) => s.copyWith(
        moveStep3D: metres,
        gridSnappingEnabled: grid ? null : true,
        showGrid: grid ? true : null,
      ),
    );
    _close();
  }

  /// [metres] as a corner label: `0.25`, `1`.
  static String _short(double metres) =>
      MoveStep3DField.label(metres).replaceFirst(' m', '');

  /// One of the bar's buttons: the tool strip's size, the whole width.
  Widget _button({
    required IconData icon,
    required String tooltip,
    required String commandId,
    required bool isActive,
    required VoidCallback onTap,
    required VoidCallback onSecondaryTap,
    String? cornerLabel,
    Widget Function(Color colour, double size)? glyph,
  }) => Padding(
    padding: ToolStripButton.padding,
    child: EditorToolButton(
      icon: icon,
      glyph: glyph,
      tooltip: tooltip,
      shortcut: _key(commandId),
      showShortcut: false,
      cornerLabel: cornerLabel,
      isActive: isActive,
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      width: double.infinity,
      height: ToolStripButton.buttonHeight,
      iconSize: ToolStripButton.iconSize,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final mode = widget.mode;
    final gizmos = settings.gizmos.of(mode);
    final kindsOn = GizmoKind.values.length - gizmos.hidden.length;
    final snapping = settings.gridSnappingEnabled;
    final grid = settings.showGrid;
    // In space, moving snaps — and the ground grid is drawn — in the 3-D
    // move step, in metres; the 2-D grid size and step are the plane's.
    final space = _scope.sceneState.editingMode == SceneMode.threeD;
    final step = space ? settings.moveStep3D : settings.moveStep;
    final size = space
        ? MoveStep3DField.label(settings.moveStep3D)
        : '${QuickSnapBar.formatStep(settings.gridSize)} u';
    final moves = space
        ? '${MoveStep3DField.label(step)} steps'
        : step > 0
        ? '${QuickSnapBar.formatStep(step)} u steps'
        : 'grid cells';
    final stepLabel = space
        ? _short(step)
        : step > 0
        ? QuickSnapBar.formatStep(step)
        : null;
    final sizeLabel = space
        ? _short(settings.moveStep3D)
        : QuickSnapBar.formatStep(settings.gridSize);
    // Snapping's panels go with snapping: none in a play-test.
    final open = widget.snapping || _open == _Row.gizmos ? _open : _Row.none;
    // The tool strip's frame, width and buttons, so the column down the
    // right of the viewport reads as one set from the top to the gear.
    final bar = FloatingToolFrame(
      settings: settings,
      child: SizedBox(
        width: ToolPalette.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _button(
              icon: Icons.filter_center_focus_rounded,
              tooltip:
                  '${mode.label} gizmos are '
                  '${gizmos.shown ? 'shown' : 'hidden'} — markers, camera '
                  'frames, colliders, outlines. Right-click for which.',
              commandId: QuickSnapBar.gizmosCommandId,
              // How many kinds are on, when not all: seen without asking.
              cornerLabel: gizmos.hidden.isEmpty ? null : '$kindsOn',
              isActive: gizmos.shown,
              onTap: () => _scope.prefs.change(
                (s) => s.copyWith(gizmos: s.gizmos.toggled(mode)),
              ),
              onSecondaryTap: () => _toggle(_Row.gizmos),
            ),
            if (widget.snapping) ...[
              _button(
                icon: Icons.grid_4x4_rounded,
                glyph: (colour, size) =>
                    MagnetGlyph(colour: colour, size: size),
                tooltip:
                    '${snapping ? 'Snapping is on' : 'Snapping is off'} — moves '
                    'in $moves. Right-click for the step.',
                commandId: QuickSnapBar.snapCommandId,
                // The step, when it is not the grid's: seen without asking.
                cornerLabel: stepLabel,
                isActive: snapping,
                onTap: () => _scope.prefs.change(
                  (s) =>
                      s.copyWith(gridSnappingEnabled: !s.gridSnappingEnabled),
                ),
                onSecondaryTap: () => _toggle(_Row.snap),
              ),
              _button(
                icon: grid ? Icons.grid_on_rounded : Icons.grid_off_rounded,
                tooltip:
                    '${grid ? 'The grid is shown' : 'The grid is hidden'} — '
                    '$size cells. Right-click for the size.',
                commandId: QuickSnapBar.gridCommandId,
                // Its size, always: what the lines are drawn at.
                cornerLabel: sizeLabel,
                isActive: grid,
                onTap: () => _scope.prefs.change(
                  (s) => s.copyWith(showGrid: !s.showGrid),
                ),
                onSecondaryTap: () => _toggle(_Row.grid),
              ),
            ],
          ],
        ),
      ),
    );
    final Widget? row = switch (open) {
      _Row.none => null,
      _Row.gizmos => GizmoMenu(
        key: const ValueKey('gizmoMenu'),
        scope: _scope,
        settings: settings,
        mode: mode,
        onClose: _close,
      ),
      _Row.snap when space => QuickValueRow(
        key: const ValueKey('snapSteps'),
        settings: settings,
        label: 'Step',
        options: [
          for (final s in MoveStep3DField.steps)
            (s, _short(s), MoveStep3DField.label(s)),
        ],
        current: step,
        onPick: _pickStep3D,
        onClose: _close,
      ),
      _Row.grid when space => QuickValueRow(
        key: const ValueKey('gridSizes'),
        settings: settings,
        label: 'Grid Size',
        options: [
          for (final s in MoveStep3DField.steps)
            (s, _short(s), '${MoveStep3DField.label(s)} a cell: the move step'),
        ],
        current: settings.moveStep3D,
        onPick: (s) => _pickStep3D(s, grid: true),
        onClose: _close,
      ),
      _Row.snap => QuickValueRow(
        key: const ValueKey('snapSteps'),
        settings: settings,
        label: 'Step',
        options: [
          for (final s in QuickSnapBar.steps)
            (
              s,
              s == 0 ? 'Auto' : QuickSnapBar.formatStep(s),
              s == 0
                  ? 'The grid\'s own: $size'
                  : '${QuickSnapBar.formatStep(s)} world units',
            ),
        ],
        current: step,
        onPick: _pickStep,
        onClose: _close,
      ),
      _Row.grid => QuickValueRow(
        key: const ValueKey('gridSizes'),
        settings: settings,
        label: 'Grid Size',
        options: [
          for (final s in _scope.config.gridSizes)
            (
              s,
              QuickSnapBar.formatStep(s),
              '${QuickSnapBar.formatStep(s)} world units a cell',
            ),
        ],
        current: settings.gridSize,
        onPick: _pickGrid,
        onClose: _close,
      ),
    };
    // The panel and the bar are one region: a click anywhere else puts the
    // panel away. The snap row sits level with the magnet in the middle;
    // the grid's with the grid at the foot, and the gizmos' menu stands on
    // the bar's foot too, taller than it, so the bar never moves.
    return TapRegion(
      onTapOutside: row == null ? null : (_) => _close(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: open == _Row.snap
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.end,
        children: [
          if (row != null) ...[row, const SizedBox(width: 6)],
          bar,
        ],
      ),
    );
  }
}

/// A row of values to pick from, sliding out beside a quick-bar button:
/// the steps moving snaps in, the grid's sizes. Picking one puts it away;
/// so does Esc.
class QuickValueRow extends StatefulWidget {
  const QuickValueRow({
    super.key,
    required this.settings,
    required this.label,
    required this.options,
    required this.current,
    required this.onPick,
    required this.onClose,
  });

  final OverlayUiSettings settings;

  /// What the values are: `Step`, `Grid Size`.
  final String label;

  /// Each value, its chip's label and its tooltip.
  final List<(double, String, String)> options;

  /// The value now; its chip is marked.
  final double current;
  final ValueChanged<double> onPick;
  final VoidCallback onClose;

  @override
  State<QuickValueRow> createState() => _QuickValueRowState();
}

class _QuickValueRowState extends State<QuickValueRow> {
  final FocusNode _focus = FocusNode(debugLabel: 'quickValues');

  @override
  void initState() {
    super.initState();
    // Keys to it at once: Esc puts it away, Tab walks the values.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onClose();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: FloatingToolFrame(
      settings: widget.settings,
      horizontalPadding: EditorMetrics.space(4),
      // As tall as one of the bar's buttons with its gap, so the row sits
      // level with the button it came out of.
      child: SizedBox(
        height: ToolStripButton.buttonHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: TextStyle(color: EditorTheme.textBright, fontSize: 10.5),
            ),
            const SizedBox(width: 8),
            for (final (value, label, tooltip) in widget.options) ...[
              EditorChip(
                label: label,
                tooltip: tooltip,
                selected: value == widget.current,
                onTap: () => widget.onPick(value),
              ),
              const SizedBox(width: 3),
            ],
          ],
        ),
      ),
    ),
  );
}

/// A horseshoe magnet: snapping's sign. Material has none.
class MagnetGlyph extends StatelessWidget {
  const MagnetGlyph({super.key, required this.colour, required this.size});

  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _MagnetPainter(colour));
}

class _MagnetPainter extends CustomPainter {
  const _MagnetPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final w = s * 0.22;
    final r = s * 0.27;
    final cx = size.width / 2;
    final cy = size.height * 0.44;
    final bend = s * 0.64;
    final tipTop = s * 0.70;
    final tipBottom = s * 0.90;
    final stroke = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    // The bend and the arms, open at the foot.
    final body = Path()
      ..moveTo(cx - r, bend)
      ..lineTo(cx - r, cy)
      ..arcToPoint(Offset(cx + r, cy), radius: Radius.circular(r))
      ..lineTo(cx + r, bend);
    canvas.drawPath(body, stroke);
    // The poles, set off from the arms by a gap.
    for (final x in [cx - r, cx + r]) {
      canvas.drawLine(Offset(x, tipTop), Offset(x, tipBottom), stroke);
    }
  }

  @override
  bool shouldRepaint(_MagnetPainter old) => old.colour != colour;
}
