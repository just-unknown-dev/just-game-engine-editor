import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/scope/editor_scope.dart';
import '../../../core/theme/editor_metrics.dart';
import '../../kit/kit.dart';
import '../settings/overlay_ui_settings.dart';
import '../../level_designer/panels/tool_palette.dart';
import 'transform_toolbar.dart';

/// Which of the bar's rows is out.
enum _Row { none, snap, grid }

/// Snapping at hand, standing on the settings gear while editing: the one
/// snap switch — the Level Designer's Snap is the same — above the grid,
/// shown or not. Right-click either and a row slides out to its left, level
/// with it: the step moving snaps in, or the grid's size.
class QuickSnapBar extends StatefulWidget {
  const QuickSnapBar({super.key, required this.scope, required this.settings});

  final EditorScope scope;
  final OverlayUiSettings settings;

  /// The commands its buttons run: no keys of their own until one is
  /// given them on the Keyboard page.
  static const String snapCommandId = 'editor.snap.toggle';
  static const String gridCommandId = 'editor.grid.toggle';

  /// The steps the snap row offers, in world units; 0 is the grid's own.
  static const List<double> steps = [0, 1, 2, 4, 8, 16, 32, 64];

  /// How tall it stands, for what has to clear it: two of the tool
  /// strip's buttons, one above the other, in the frame the strip has.
  static double heightFor(OverlayUiSettings settings) =>
      FloatingToolFrame.heightFor(ToolStripButton.extent * 2);

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

  /// Right-click: [row] out, or away if it was — and the other away.
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

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final snapping = settings.gridSnappingEnabled;
    final grid = settings.showGrid;
    final step = settings.moveStep;
    final size = QuickSnapBar.formatStep(settings.gridSize);
    final moves = step > 0
        ? '${QuickSnapBar.formatStep(step)} u steps'
        : 'grid cells';
    // The tool strip's frame, width and buttons, so the column down the
    // right of the viewport reads as one set from the top to the gear.
    final bar = FloatingToolFrame(
      settings: settings,
      child: SizedBox(
        width: ToolPalette.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: ToolStripButton.padding,
              child: EditorToolButton(
                icon: Icons.grid_4x4_rounded,
                glyph: (colour, size) =>
                    MagnetGlyph(colour: colour, size: size),
                tooltip:
                    '${snapping ? 'Snapping is on' : 'Snapping is off'} — moves '
                    'in $moves. Right-click for the step.',
                shortcut: _key(QuickSnapBar.snapCommandId),
                showShortcut: false,
                // The step, when it is not the grid's: seen without asking.
                cornerLabel: step > 0 ? QuickSnapBar.formatStep(step) : null,
                isActive: snapping,
                onTap: () => _scope.prefs.change(
                  (s) =>
                      s.copyWith(gridSnappingEnabled: !s.gridSnappingEnabled),
                ),
                onSecondaryTap: () => _toggle(_Row.snap),
                width: double.infinity,
                height: ToolStripButton.buttonHeight,
                iconSize: ToolStripButton.iconSize,
              ),
            ),
            Padding(
              padding: ToolStripButton.padding,
              child: EditorToolButton(
                icon: grid ? Icons.grid_on_rounded : Icons.grid_off_rounded,
                tooltip:
                    '${grid ? 'The grid is shown' : 'The grid is hidden'} — '
                    '$size u cells. Right-click for the size.',
                shortcut: _key(QuickSnapBar.gridCommandId),
                showShortcut: false,
                // Its size, always: what the lines are drawn at.
                cornerLabel: size,
                isActive: grid,
                onTap: () => _scope.prefs.change(
                  (s) => s.copyWith(showGrid: !s.showGrid),
                ),
                onSecondaryTap: () => _toggle(_Row.grid),
                width: double.infinity,
                height: ToolStripButton.buttonHeight,
                iconSize: ToolStripButton.iconSize,
              ),
            ),
          ],
        ),
      ),
    );
    final Widget? row = switch (_open) {
      _Row.none => null,
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
                  ? 'The grid\'s own: $size u'
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
    // The row and the bar are one region: a click anywhere else puts the
    // row away. Each row sits level with its button — the snap row with
    // the magnet at the top, the grid's with the grid at the foot.
    return TapRegion(
      onTapOutside: row == null ? null : (_) => _close(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: _open == _Row.grid
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
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
