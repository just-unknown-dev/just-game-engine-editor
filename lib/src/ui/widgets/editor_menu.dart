/// Menus in the editor's colours.
///
/// A popup menu takes its text and its divider from the ambient Material
/// theme, which here is the light default: black on the editor's near-black
/// menu is unreadable. Every menu in the editor goes through these, so none
/// of them can forget.
library;

import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';

/// One line of a menu.
PopupMenuItem<T> editorMenuItem<T>(
  T value,
  String label, {
  bool enabled = true,
  Color? color,
  double height = 30,
  IconData? icon,
}) => PopupMenuItem<T>(
  value: value,
  height: height,
  enabled: enabled,
  child: Row(
    children: [
      if (icon != null) ...[
        Icon(
          icon,
          size: 13,
          color: enabled ? EditorTheme.textSecondary : EditorTheme.textMuted,
        ),
        const SizedBox(width: 8),
      ],
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: enabled
                ? (color ?? EditorTheme.textPrimary)
                : EditorTheme.textMuted,
            fontSize: 11,
          ),
        ),
      ),
    ],
  ),
);

/// A group's name, above the things in it. Not something to choose.
PopupMenuItem<T> editorMenuHeading<T>(String label) => PopupMenuItem<T>(
  enabled: false,
  height: 22,
  child: Text(
    label.toUpperCase(),
    style: const TextStyle(
      color: EditorTheme.textMuted,
      fontSize: 9,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    ),
  ),
);

/// The rule between groups of items.
PopupMenuDivider editorMenuDivider() => PopupMenuDivider(
  height: 7,
  thickness: 1,
  color: EditorTheme.textPrimary.withValues(alpha: 0.10),
);

/// Opens [items] at the global point [at].
Future<T?> showEditorMenu<T>(
  BuildContext context,
  Offset at,
  List<PopupMenuEntry<T>> items,
) => showMenu<T>(
  context: context,
  color: EditorTheme.menuBg,
  position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(4),
    side: const BorderSide(color: EditorTheme.border),
  ),
  items: items,
);
