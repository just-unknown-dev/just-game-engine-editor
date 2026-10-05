import 'package:flutter/material.dart';

import '../constants/editor_constants.dart';
import 'editor_metrics.dart';
import 'editor_theme_data.dart';

/// A Material theme in the editor's colours, for widgets from other
/// packages that take their colours from [Theme] — the colour picker.
///
/// The app the editor runs in has no theme of its own (the light default),
/// and the editor's own widgets paint their colours by hand, so a Material
/// widget opened from the editor would otherwise come up light lavender in
/// a dark editor.
ThemeData editorMaterialTheme([EditorThemeData? data]) {
  final t = data ?? EditorTheme.current;
  final scheme = ColorScheme.dark(
    primary: t.primaryActive,
    onPrimary: t.textBright,
    primaryContainer: t.selectionBg,
    onPrimaryContainer: t.textPrimary,
    secondary: t.primaryBright,
    onSecondary: t.textBright,
    surface: t.dialogBg,
    onSurface: t.textPrimary,
    onSurfaceVariant: t.textMuted,
    surfaceContainerLowest: t.surfaceDarkest,
    surfaceContainerLow: t.surfaceBg,
    surfaceContainer: t.dialogBg,
    surfaceContainerHigh: t.menuBg,
    surfaceContainerHighest: t.inputBg,
    outline: t.borderStrong,
    outlineVariant: t.borderStrong,
    error: t.error,
    onError: t.textBright,
    inverseSurface: t.panelRaised,
    onInverseSurface: t.textPrimary,
  );
  final radius = BorderRadius.circular(EditorMetrics.radiusSm + 1);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: t.panelBg,
    canvasColor: t.dialogBg,
    dividerColor: t.borderStrong,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.primaryBright,
      selectionColor: t.primary.withValues(alpha: 0.35),
      selectionHandleColor: t.primaryBright,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.textSecondary,
        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.primaryActive,
        foregroundColor: t.textBright,
        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.menuBg),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: t.borderStrong)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: radius),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: MenuItemButton.styleFrom(
        foregroundColor: t.textPrimary,
        minimumSize: const Size(0, 30),
        textStyle: const TextStyle(fontSize: 12),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.menuBg,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: t.textPrimary, fontSize: 12),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: t.borderStrong),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.dialogBg,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: t.inputBg,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: t.borderStrong),
      ),
    ),
  );
}
