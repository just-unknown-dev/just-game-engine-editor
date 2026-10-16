import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../level_designer_session.dart';

/// The designer's tool strip, floating at the top right of the viewport
/// under the All / Move / Scale / Rotate column — which is the select tool,
/// so it is not listed again here.
///
/// Tools stand under a caption per group — SELECT, SHAPES, TILES, MEASURE,
/// and any group a module adds — each with its shortcut letter in the
/// corner, because the keys are what anyone doing this repeatedly will
/// actually use; the buttons are for discovery. A tool's settings are at
/// the left of the status bar along the bottom, not here.
class ToolPalette extends StatelessWidget {
  const ToolPalette({super.key, required this.session});

  /// The designer session whose tool is being switched.
  final LevelDesignerSession session;

  /// Width of the strip, and of the transform column above it.
  static const double width = 48;

  @override
  Widget build(BuildContext context) => SignalBuilder<String?>(
    // Everything below follows the designer in use.
    signal: session.scope.activeDesigner,
    builder: (context, _, _) => _buildStrip(context),
  );

  Widget _buildStrip(BuildContext context) {
    // Floats under the transform column, as tall as its tools and no
    // taller — and scrolls when the window is shorter than that.
    return SizedBox(
      width: width,
      // Renders whatever is registered, so a project's tool appears here
      // without the editor package knowing it exists.
      child: SignalBuilder<String>(
        signal: session.controller.toolId,
        builder: (context, activeId, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: EditorScrollbar(
                builder: (_, scroll) => SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(children: _groups(activeId)),
                ),
              ),
            ),
            Container(height: 1, color: EditorTheme.border),
            const SizedBox(height: 4),
            _UndoButtons(session: session),
          ],
        ),
      ),
    );
  }

  /// A caption per group, then its tools. Not the select tool: the
  /// transform column's All, Move, Scale and Rotate are it. A group left
  /// with nothing is left out.
  List<Widget> _groups(String activeId) => [
    for (final (group, all) in session.tools.grouped)
      if ([
            for (final t in all)
              if (t.id != BuiltInTools.select) t,
          ]
          case final tools when tools.isNotEmpty) ...[
        ToolGroupCaption(label: group.label),
        for (final tool in tools)
          ToolStripButton(
            icon: tool.icon,
            tooltip: _tooltipFor(tool),
            shortcut: tool.shortcut,
            isActive: tool.id == activeId,
            onTap: () => session.setTool(tool.id),
          ),
      ],
  ];
}

/// The small caption over a group of tools.
class ToolGroupCaption extends StatelessWidget {
  const ToolGroupCaption({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 9, 2, 3),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: EditorTheme.textMuted,
        fontSize: 8,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    ),
  );
}

/// Label, shortcut and description, in whatever combination the tool supplies.
String _tooltipFor(LevelToolHandler tool) {
  final shortcut = tool.shortcut;
  final head = shortcut == null ? tool.label : '${tool.label}  ($shortcut)';
  final description = tool.description;
  return description == null ? head : '$head\n$description';
}

/// One button of the strip: the kit's tool button, as wide as the strip —
/// the icon, the shortcut letter in its corner, and for the tool in hand a
/// fill and an accent bar down its left edge.
class ToolStripButton extends StatelessWidget {
  const ToolStripButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
    this.shortcut,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  /// The key that picks it, shown in the corner.
  final String? shortcut;

  /// Greyed and not tappable when false.
  final bool enabled;

  /// A button's height and its icon's — the same for every button in a
  /// column down the right of the viewport: this strip, the transform
  /// column, the snapping buttons and the gear.
  static const double buttonHeight = 32;
  static const double iconSize = 18;

  /// Around each button: in from the frame's sides, two pixels apart.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 1,
  );

  /// How much of a column's height one button takes, [padding] included.
  static const double extent = buttonHeight + 2;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: EditorToolButton(
      icon: icon,
      // The tooltips here already name their key.
      tooltip: tooltip,
      shortcut: null,
      cornerLabel: shortcut,
      isActive: isActive,
      onTap: enabled ? onTap : null,
      width: double.infinity,
      height: buttonHeight,
      iconSize: iconSize,
    ),
  );
}

/// Undo and redo, bound directly to the history's signals so they enable and
/// disable themselves without anything having to push a rebuild.
class _UndoButtons extends StatelessWidget {
  const _UndoButtons({required this.session});

  final LevelDesignerSession session;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder2<bool, bool>(
      signal1: session.history.canUndo,
      signal2: session.history.canRedo,
      builder: (context, canUndo, canRedo, _) => Column(
        children: [
          ToolStripButton(
            icon: Icons.undo,
            tooltip: session.history.nextUndoLabel.value == null
                ? 'Nothing to undo'
                : 'Undo ${session.history.nextUndoLabel.value}  (Ctrl+Z)',
            isActive: false,
            enabled: canUndo,
            onTap: session.history.undo,
          ),
          ToolStripButton(
            icon: Icons.redo,
            tooltip: session.history.nextRedoLabel.value == null
                ? 'Nothing to redo'
                : 'Redo ${session.history.nextRedoLabel.value}  (Ctrl+Y)',
            isActive: false,
            enabled: canRedo,
            onTap: session.history.redo,
          ),
        ],
      ),
    );
  }
}
