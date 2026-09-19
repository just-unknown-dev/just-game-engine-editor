import 'package:flutter/material.dart';

import '../constants/editor_constants.dart';

/// The editor's palette as a value, so it can change while the editor runs.
///
/// [classic] is exactly what the `EditorTheme` constants have always been.
/// A preset is usually [classic] with a different accent; a module may
/// register a whole palette of its own.
class EditorThemeData {
  const EditorThemeData({
    required this.primary,
    required this.primaryBright,
    required this.primaryActive,
    required this.primaryMuted,
    required this.primaryMutedLight,
    required this.selectionBg,
    required this.dragOverBg,
    required this.multiSelectBg,
    required this.hoverBg,
    required this.hoverBgAlt,
    required this.panelBg,
    required this.surfaceBg,
    required this.dialogBg,
    required this.inputBg,
    required this.menuBg,
    required this.surfaceDark,
    required this.surfaceDarker,
    required this.surfaceDarkest,
    required this.border,
    required this.buttonBg,
    required this.statusBadgeBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textBright,
    required this.textBadge,
    required this.error,
    required this.errorLight,
    required this.warning,
  });

  /// The palette the editor shipped with.
  static const EditorThemeData classic = EditorThemeData(
    primary: EditorTheme.primary,
    primaryBright: EditorTheme.primaryBright,
    primaryActive: EditorTheme.primaryActive,
    primaryMuted: EditorTheme.primaryMuted,
    primaryMutedLight: EditorTheme.primaryMutedLight,
    selectionBg: EditorTheme.selectionBg,
    dragOverBg: EditorTheme.dragOverBg,
    multiSelectBg: EditorTheme.multiSelectBg,
    hoverBg: EditorTheme.hoverBg,
    hoverBgAlt: EditorTheme.hoverBgAlt,
    panelBg: EditorTheme.panelBg,
    surfaceBg: EditorTheme.surfaceBg,
    dialogBg: EditorTheme.dialogBg,
    inputBg: EditorTheme.inputBg,
    menuBg: EditorTheme.menuBg,
    surfaceDark: EditorTheme.surfaceDark,
    surfaceDarker: EditorTheme.surfaceDarker,
    surfaceDarkest: EditorTheme.surfaceDarkest,
    border: EditorTheme.border,
    buttonBg: EditorTheme.buttonBg,
    statusBadgeBg: EditorTheme.statusBadgeBg,
    textPrimary: EditorTheme.textPrimary,
    textSecondary: EditorTheme.textSecondary,
    textMuted: EditorTheme.textMuted,
    textBright: EditorTheme.textBright,
    textBadge: EditorTheme.textBadge,
    error: EditorTheme.error,
    errorLight: EditorTheme.errorLight,
    warning: EditorTheme.warning,
  );

  final Color primary,
      primaryBright,
      primaryActive,
      primaryMuted,
      primaryMutedLight;
  final Color selectionBg, dragOverBg, multiSelectBg, hoverBg, hoverBgAlt;
  final Color panelBg, surfaceBg, dialogBg, inputBg, menuBg;
  final Color surfaceDark, surfaceDarker, surfaceDarkest;
  final Color border, buttonBg, statusBadgeBg;
  final Color textPrimary, textSecondary, textMuted, textBright, textBadge;
  final Color error, errorLight, warning;

  /// This palette re-accented: the primary family and the tinted surfaces
  /// follow [accent], everything else stays.
  EditorThemeData withAccent(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    Color shade(double lightness, [double alpha = 1]) => hsl
        .withLightness(lightness.clamp(0.0, 1.0))
        .toColor()
        .withValues(alpha: alpha);
    return copyWith(
      primary: accent,
      primaryBright: shade(hsl.lightness + 0.12),
      primaryActive: shade(hsl.lightness - 0.1),
      primaryMuted: shade(0.38),
      primaryMutedLight: shade(0.62),
      selectionBg: shade(0.17),
      dragOverBg: shade(0.2),
      multiSelectBg: shade(0.14),
      hoverBg: shade(0.16),
      hoverBgAlt: shade(0.23),
      border: shade(0.7, 0.05),
      buttonBg: shade(0.19),
      statusBadgeBg: shade(0.19, 0.9),
    );
  }

  EditorThemeData copyWith({
    Color? primary,
    Color? primaryBright,
    Color? primaryActive,
    Color? primaryMuted,
    Color? primaryMutedLight,
    Color? selectionBg,
    Color? dragOverBg,
    Color? multiSelectBg,
    Color? hoverBg,
    Color? hoverBgAlt,
    Color? panelBg,
    Color? surfaceBg,
    Color? dialogBg,
    Color? inputBg,
    Color? menuBg,
    Color? surfaceDark,
    Color? surfaceDarker,
    Color? surfaceDarkest,
    Color? border,
    Color? buttonBg,
    Color? statusBadgeBg,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textBright,
    Color? textBadge,
    Color? error,
    Color? errorLight,
    Color? warning,
  }) => EditorThemeData(
    primary: primary ?? this.primary,
    primaryBright: primaryBright ?? this.primaryBright,
    primaryActive: primaryActive ?? this.primaryActive,
    primaryMuted: primaryMuted ?? this.primaryMuted,
    primaryMutedLight: primaryMutedLight ?? this.primaryMutedLight,
    selectionBg: selectionBg ?? this.selectionBg,
    dragOverBg: dragOverBg ?? this.dragOverBg,
    multiSelectBg: multiSelectBg ?? this.multiSelectBg,
    hoverBg: hoverBg ?? this.hoverBg,
    hoverBgAlt: hoverBgAlt ?? this.hoverBgAlt,
    panelBg: panelBg ?? this.panelBg,
    surfaceBg: surfaceBg ?? this.surfaceBg,
    dialogBg: dialogBg ?? this.dialogBg,
    inputBg: inputBg ?? this.inputBg,
    menuBg: menuBg ?? this.menuBg,
    surfaceDark: surfaceDark ?? this.surfaceDark,
    surfaceDarker: surfaceDarker ?? this.surfaceDarker,
    surfaceDarkest: surfaceDarkest ?? this.surfaceDarkest,
    border: border ?? this.border,
    buttonBg: buttonBg ?? this.buttonBg,
    statusBadgeBg: statusBadgeBg ?? this.statusBadgeBg,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    textBright: textBright ?? this.textBright,
    textBadge: textBadge ?? this.textBadge,
    error: error ?? this.error,
    errorLight: errorLight ?? this.errorLight,
    warning: warning ?? this.warning,
  );
}

/// A named palette the settings dialog offers.
class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.label,
    required this.data,
  });
  final String id;
  final String label;
  final EditorThemeData data;
}
