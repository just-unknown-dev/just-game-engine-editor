import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../level_designer_session.dart';
import '../tools/level_tool.dart';

/// The vertical tool strip down the left edge of the designer.
///
/// Keyboard shortcuts are shown in the tooltips because they are what anyone
/// doing this repeatedly will actually use; the buttons are for discovery.
class ToolPalette extends StatelessWidget {
  const ToolPalette({super.key, required this.session});

  /// The designer session whose tool is being switched.
  final LevelDesignerSession session;

  /// Width of the strip.
  static const double width = 44;

  @override
  Widget build(BuildContext context) => SignalBuilder<String?>(
    // Everything below follows the designer in use.
    signal: session.scope.activeDesigner,
    builder: (context, _, _) => _buildStrip(context),
  );

  Widget _buildStrip(BuildContext context) {
    return Container(
      width: width,
      color: EditorTheme.panelBg,
      // Renders whatever is registered, so a project's tool appears here
      // without the editor package knowing it exists.
      child: SignalBuilder<String>(
        signal: session.controller.toolId,
        builder: (context, activeId, _) => Column(
          children: [
            const SizedBox(height: 8),
            for (final tool in session.tools.all)
              _ToolButton(
                icon: tool.icon,
                tooltip: _tooltipFor(tool),
                isActive: tool.id == activeId,
                onTap: () => session.setTool(tool.id),
              ),
            const Spacer(),
            _UndoButtons(session: session),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Label, shortcut and description, in whatever combination the tool supplies.
String _tooltipFor(LevelToolHandler tool) {
  final shortcut = tool.shortcut;
  final head = shortcut == null ? tool.label : '${tool.label}  ($shortcut)';
  final description = tool.description;
  return description == null ? head : '$head\n$description';
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isActive ? EditorTheme.primaryMuted : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 34,
              child: Icon(
                icon,
                size: 18,
                color: isActive
                    ? EditorTheme.primaryBright
                    : EditorTheme.textSecondary,
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
          _ToolButton(
            icon: Icons.undo,
            tooltip: session.history.nextUndoLabel.value == null
                ? 'Nothing to undo'
                : 'Undo ${session.history.nextUndoLabel.value}  (Ctrl+Z)',
            isActive: false,
            onTap: canUndo ? session.history.undo : () {},
          ),
          _ToolButton(
            icon: Icons.redo,
            tooltip: session.history.nextRedoLabel.value == null
                ? 'Nothing to redo'
                : 'Redo ${session.history.nextRedoLabel.value}  (Ctrl+Y)',
            isActive: false,
            onTap: canRedo ? session.history.redo : () {},
          ),
        ],
      ),
    );
  }
}
