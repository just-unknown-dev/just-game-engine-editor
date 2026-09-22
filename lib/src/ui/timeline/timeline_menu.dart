/// Menus in the editor's colours, as the Timeline names them.
///
/// The implementations moved to `widgets/editor_menu.dart` once the scene
/// tree needed the same thing; these stay so the Timeline's call sites read
/// as they always have.
library;

import 'package:flutter/material.dart';

import '../widgets/editor_menu.dart';

/// One line of a menu.
PopupMenuItem<T> timelineMenuItem<T>(
  T value,
  String label, {
  bool enabled = true,
  Color? color,
  double height = 30,
}) => editorMenuItem<T>(
  value,
  label,
  enabled: enabled,
  color: color,
  height: height,
);

/// The rule between groups of items.
PopupMenuDivider timelineMenuDivider() => editorMenuDivider();

/// Opens [items] at the global point [at].
Future<T?> showTimelineMenu<T>(
  BuildContext context,
  Offset at,
  List<PopupMenuEntry<T>> items,
) => showEditorMenu<T>(context, at, items);
