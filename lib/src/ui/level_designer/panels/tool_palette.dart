import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../level_designer_session.dart';
import '../tools/level_tool.dart';
import '../tools/tool_registry.dart';
import '../../widgets/editor_scrollbar.dart';

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
      style: const TextStyle(
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

/// One button of the strip: the icon, the shortcut letter in its corner, and
/// — for the tool in hand — a fill and an accent bar down its left edge.
class ToolStripButton extends StatefulWidget {
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

  @override
  State<ToolStripButton> createState() => _ToolStripButtonState();
}

class _ToolStripButtonState extends State<ToolStripButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final Color iconColor = !widget.enabled
        ? EditorTheme.textMuted.withValues(alpha: 0.4)
        : active
        ? EditorTheme.primaryBright
        : _hover
        ? EditorTheme.textPrimary
        : EditorTheme.textSecondary;
    final shortcut = widget.shortcut;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? widget.onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              height: 32,
              decoration: BoxDecoration(
                color: active
                    ? EditorTheme.primaryMuted.withValues(alpha: 0.55)
                    : _hover && widget.enabled
                    ? EditorTheme.hoverBg
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Stack(
                children: [
                  if (active)
                    Positioned(
                      left: 0,
                      top: 5,
                      bottom: 5,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: EditorTheme.primaryBright,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  Center(child: Icon(widget.icon, size: 18, color: iconColor)),
                  if (shortcut != null)
                    Positioned(
                      right: 3,
                      bottom: 1,
                      child: Text(
                        shortcut,
                        style: TextStyle(
                          color: active
                              ? EditorTheme.primaryMutedLight
                              : EditorTheme.textMuted,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
