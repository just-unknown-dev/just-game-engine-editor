import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/scope/editor_scope.dart';

/// Picks which level designer is live: the built-in one, or a module's.
///
/// Lists "Default" first, then every module that brings a designer of its
/// own ([EditorModule.providesLevelDesigner]). Selecting one swaps the
/// palette, tools, overlays, layers, grid and side-panel sections through
/// [EditorScope.selectDesigner]; the built-in tools stay in every designer.
///
/// The header shows it only when there is something to switch to.
class DesignerSwitch extends StatelessWidget {
  const DesignerSwitch({super.key, required this.scope});

  /// The editor whose designer this switches.
  final EditorScope scope;

  /// What the built-in designer is called in the menu.
  static const String defaultLabel = 'Default';

  // A PopupMenuButton treats a null value as "cancelled", so the built-in
  // designer travels as an empty id.
  static const String _defaultValue = '';

  @override
  Widget build(BuildContext context) {
    return SignalBuilder<String?>(
      signal: scope.activeDesigner,
      builder: (context, activeId, _) {
        final active = activeId == null ? null : scope.modules.byId(activeId);
        return PopupMenuButton<String>(
          tooltip: 'Switch level designer',
          padding: EdgeInsets.zero,
          position: PopupMenuPosition.under,
          color: EditorTheme.panelBg,
          onSelected: (value) =>
              scope.selectDesigner(value == _defaultValue ? null : value),
          itemBuilder: (context) => [
            _item(
              _defaultValue,
              Icons.map_outlined,
              defaultLabel,
              selected: activeId == null,
            ),
            for (final module in scope.designers)
              _item(
                module.id,
                module.icon ?? Icons.extension,
                module.name,
                selected: module.id == activeId,
              ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  active?.name ?? defaultLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: EditorTheme.textBright,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: EditorTheme.textMuted,
              ),
            ],
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _item(
    String value,
    IconData icon,
    String label, {
    required bool selected,
  }) => PopupMenuItem<String>(
    value: value,
    height: 32,
    child: Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: selected ? EditorTheme.primary : EditorTheme.textMuted,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: selected ? EditorTheme.textBright : EditorTheme.textMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}
