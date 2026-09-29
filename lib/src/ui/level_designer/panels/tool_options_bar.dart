import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../controls/designer_controls.dart';
import '../level_designer_session.dart';
import '../tools/level_tool.dart';

/// The tool in hand and its settings — the paint mode, the brush size, the
/// layer being painted — at the left end of the designer's status bar
/// along the bottom, so the whole of the viewport is the level's.
///
/// A tool with no settings says what it does instead. The status bar
/// scrolls it with the rest, so it takes the width it needs.
class ToolOptionsBar extends StatelessWidget {
  const ToolOptionsBar({super.key, required this.session});

  /// The designer session whose tool this shows.
  final LevelDesignerSession session;

  /// The most a tool's description takes before it is cut short.
  static const double maxDescriptionWidth = 360;

  @override
  Widget build(BuildContext context) => SignalBuilder2<String?, String>(
    // A designer switch swaps the tools under the same id.
    signal1: session.scope.activeDesigner,
    signal2: session.controller.toolId,
    builder: (context, _, _, _) => _buildOptions(context),
  );

  Widget _buildOptions(BuildContext context) {
    final tool = session.controller.activeTool;
    if (tool == null) return const SizedBox.shrink();
    final options = tool.buildOptions(
      context,
      ToolOptionsContext(
        scope: session.scope,
        controller: session.controller,
        world: session.world,
        setTool: session.setTool,
      ),
    );
    final description = tool.description;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        options ??
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxDescriptionWidth),
              child: Text(
                description ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
              ),
            ),
        const OptionsDivider(),
        Icon(tool.icon, size: 14, color: EditorTheme.primaryBright),
        const SizedBox(width: 6),
        Text(
          tool.label,
          style: TextStyle(
            color: EditorTheme.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (tool.shortcut != null) ...[
          const SizedBox(width: 5),
          _KeyCap(tool.shortcut!),
        ],
      ],
    );
  }
}

/// A shortcut letter drawn as a key.
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: EditorTheme.textMuted.withValues(alpha: 0.4)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: EditorTheme.textMuted,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
