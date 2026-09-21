/// Menus in the editor's colours.
///
/// A popup menu takes its text and its divider from the ambient Material
/// theme, which here is the light default: black on the editor's near-black
/// menu is unreadable. Every menu in the Timeline goes through these, so
/// none of them can forget.
library;

import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';

/// One line of a menu.
PopupMenuItem<T> timelineMenuItem<T>(
  T value,
  String label, {
  bool enabled = true,
  Color? color,
  double height = 30,
}) => PopupMenuItem<T>(
  value: value,
  height: height,
  enabled: enabled,
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
);

/// The rule between groups of items.
PopupMenuDivider timelineMenuDivider() => PopupMenuDivider(
  height: 7,
  thickness: 1,
  color: EditorTheme.textPrimary.withValues(alpha: 0.10),
);

/// Opens [items] at the global point [at].
Future<T?> showTimelineMenu<T>(
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
