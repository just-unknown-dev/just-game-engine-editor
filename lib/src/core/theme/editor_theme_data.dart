import 'package:flutter/material.dart';

/// The editor's palette as a value, so it can change while the editor runs.
///
/// [classic] is the palette the editor shipped with. A preset is usually
/// [classic] with a different accent; a module may register a whole palette
/// of its own. `EditorTheme` reads whichever is applied.
@immutable
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
    required this.panelRaised,
    required this.surfaceDark,
    required this.surfaceDarker,
    required this.surfaceDarkest,
    required this.border,
    required this.borderStrong,
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
    required this.success,
    required this.info,
  });

  /// The palette the editor shipped with: dark, warm, a coral accent.
  static const EditorThemeData classic = EditorThemeData(
    primary: Color(0xFFF5746F),
    primaryBright: Color(0xFFFF9C98),
    primaryActive: Color(0xFFD95450),
    primaryMuted: Color(0xFF7A4A4A),
    primaryMutedLight: Color(0xFFC97E7E),
    selectionBg: Color(0xFF3D1A1A),
    dragOverBg: Color(0xFF4A1E1E),
    multiSelectBg: Color(0xFF301515),
    hoverBg: Color(0xFF33201E),
    hoverBgAlt: Color(0xFF4A2D2D),
    panelBg: Color(0xFF0F0E0E),
    surfaceBg: Color(0xFF1A1818),
    dialogBg: Color(0xFF161414),
    inputBg: Color(0xFF111010),
    menuBg: Color(0xFF1C1919),
    panelRaised: Color(0xFF262020),
    surfaceDark: Color(0xFF0C0B0B),
    surfaceDarker: Color(0xFF0A0909),
    surfaceDarkest: Color(0xFF080707),
    border: Color.fromARGB(13, 245, 115, 111),
    borderStrong: Color(0xFF3A2C2C),
    buttonBg: Color(0xFF44201F),
    statusBadgeBg: Color(0xE644201F),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFCCCCCC),
    textMuted: Color(0xFF999999),
    textBright: Color(0xFFFFFFFF),
    textBadge: Color(0xFFFFFFFF),
    error: Color(0xFFE54B4B),
    errorLight: Color(0xFFFF7070),
    warning: Color(0xFFFFD660),
    success: Color(0xFF7DE6B1),
    info: Color(0xFF4A9EFF),
  );

  /// The accent, and its brighter, pressed and quiet shades.
  final Color primary,
      primaryBright,
      primaryActive,
      primaryMuted,
      primaryMutedLight;

  /// Behind what is picked, dragged over, or under the pointer.
  final Color selectionBg, dragOverBg, multiSelectBg, hoverBg, hoverBgAlt;

  /// Surfaces, darkest to lightest roughly: what panels, dialogs, fields and
  /// menus are painted on.
  final Color panelBg, surfaceBg, dialogBg, inputBg, menuBg, panelRaised;
  final Color surfaceDark, surfaceDarker, surfaceDarkest;

  /// [border] is the faint line between regions; [borderStrong] the line
  /// that has to be seen — a dialog's panels, a field.
  final Color border, borderStrong;
  final Color buttonBg, statusBadgeBg;
  final Color textPrimary, textSecondary, textMuted, textBright, textBadge;

  /// What went wrong, what may, what went right, and what is merely said.
  final Color error, errorLight, warning, success, info;

  /// This palette re-accented: the accent family and the tinted surfaces
  /// take [accent]'s hue, each keeping how light and how coloured it was —
  /// so every accent reads like the classic coral one, in its own colour.
  EditorThemeData withAccent(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    Color shade(double lightness, [double alpha = 1]) => hsl
        .withLightness(lightness.clamp(0.0, 1.0))
        .toColor()
        .withValues(alpha: alpha);
    Color hued(Color c) => HSLColor.fromColor(c).withHue(hsl.hue).toColor();
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
      panelBg: hued(classic.panelBg),
      surfaceBg: hued(classic.surfaceBg),
      dialogBg: hued(classic.dialogBg),
      inputBg: hued(classic.inputBg),
      menuBg: hued(classic.menuBg),
      panelRaised: hued(classic.panelRaised),
      surfaceDark: hued(classic.surfaceDark),
      surfaceDarker: hued(classic.surfaceDarker),
      surfaceDarkest: hued(classic.surfaceDarkest),
      borderStrong: hued(classic.borderStrong),
    );
  }

  /// This palette with more contrast: secondary and muted text nearer white,
  /// lines between regions that show, the quiet shades of the accent and the
  /// selection brighter. The accent itself and the surfaces stay, so every
  /// accent still reads as itself.
  EditorThemeData highContrast() {
    Color lift(Color c, double by) {
      final hsl = HSLColor.fromColor(c);
      return hsl.withLightness((hsl.lightness + by).clamp(0.0, 1.0)).toColor();
    }

    return copyWith(
      textSecondary: const Color(0xFFF0F0F0),
      textMuted: const Color(0xFFC8C8C8),
      primaryMuted: lift(primaryMuted, 0.22),
      primaryMutedLight: lift(primaryMutedLight, 0.12),
      border: const Color(0x3DFFFFFF),
      borderStrong: lift(borderStrong, 0.28),
      selectionBg: lift(selectionBg, 0.1),
      multiSelectBg: lift(multiSelectBg, 0.08),
      hoverBg: lift(hoverBg, 0.08),
      hoverBgAlt: lift(hoverBgAlt, 0.08),
    );
  }

  /// This palette with status colours anyone can tell apart — the
  /// Okabe–Ito set, which does not lean on red against green: vermilion
  /// for errors, yellow for warnings, sky blue for success, reddish purple
  /// for information. The icons beside them say the same again.
  EditorThemeData colourBlindSafe() => copyWith(
    error: const Color(0xFFFF7A33),
    errorLight: const Color(0xFFFFA36B),
    warning: const Color(0xFFF0E442),
    success: const Color(0xFF56B4E9),
    info: const Color(0xFFCC79A7),
  );

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
    Color? panelRaised,
    Color? surfaceDark,
    Color? surfaceDarker,
    Color? surfaceDarkest,
    Color? border,
    Color? borderStrong,
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
    Color? success,
    Color? info,
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
    panelRaised: panelRaised ?? this.panelRaised,
    surfaceDark: surfaceDark ?? this.surfaceDark,
    surfaceDarker: surfaceDarker ?? this.surfaceDarker,
    surfaceDarkest: surfaceDarkest ?? this.surfaceDarkest,
    border: border ?? this.border,
    borderStrong: borderStrong ?? this.borderStrong,
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
    success: success ?? this.success,
    info: info ?? this.info,
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
