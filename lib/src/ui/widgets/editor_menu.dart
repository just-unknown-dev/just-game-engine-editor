/// Menus in the editor's colours.
///
/// A popup menu takes its text and its divider from the ambient Material
/// theme, which here is the light default: black on the editor's near-black
/// menu is unreadable. Every menu in the editor goes through these, so none
/// of them can forget.
library;

import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';
import '../kit/look.dart';

/// One line of a menu.
PopupMenuItem<T> editorMenuItem<T>(
  T value,
  String label, {
  bool enabled = true,
  Color? color,
  double height = 30,
  IconData? icon,

  /// The icon's own colour, where the icon *is* the point — a swatch in
  /// a list of colours, which was otherwise eight identical grey squares.
  Color? iconColor,

  /// The key that does the same, at the right: `Ctrl+D`.
  String? shortcut,

  /// Keeps an icon's room when there is no [icon], so that in a menu where
  /// some lines have one — a tick by the current choice — every label
  /// starts in the same column.
  bool iconSlot = false,
}) => PopupMenuItem<T>(
  value: value,
  height: height,
  enabled: enabled,
  child: EditorLook(
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 13,
            color: enabled
                ? (iconColor ?? color ?? EditorTheme.textSecondary)
                : EditorTheme.textMuted,
          ),
          const SizedBox(width: 8),
        ] else if (iconSlot)
          const SizedBox(width: 13 + 8),
        // With a key at the right, the label takes the room between them.
        Flexible(
          fit: shortcut == null ? FlexFit.loose : FlexFit.tight,
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
        if (shortcut != null) ...[
          const SizedBox(width: 16),
          Text(
            shortcut,
            style: TextStyle(
              color: EditorTheme.textMuted,
              fontSize: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    ),
  ),
);

/// A group's name, above the things in it. Not something to choose.
PopupMenuItem<T> editorMenuHeading<T>(String label) => PopupMenuItem<T>(
  enabled: false,
  height: 22,
  child: EditorLook(
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        color: EditorTheme.textMuted,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
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
/// Opens [items] [gap] below the widget [anchor] is the context of: from
/// its left edge, or — where there is no room to the right — its right
/// edge, so a menu from a button at the end of a row opens inward instead
/// of pressed against the header and the window's edge.
Future<T?> showEditorMenuBelow<T>(
  BuildContext anchor,
  List<PopupMenuEntry<T>> items, {
  double gap = 4,
}) {
  final box = anchor.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final left = box.localToGlobal(Offset.zero, ancestor: overlay).dx;
  final bottom =
      box
          .localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay)
          .dy +
      gap;
  return showMenu<T>(
    context: anchor,
    color: EditorTheme.menuBg,
    position: RelativeRect.fromRect(
      Rect.fromLTRB(left, bottom, left + box.size.width, bottom),
      Offset.zero & overlay.size,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: EditorTheme.border),
    ),
    items: items,
  );
}

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
    side: BorderSide(color: EditorTheme.border),
  ),
  items: items,
);
