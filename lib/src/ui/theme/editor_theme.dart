import 'package:flutter/material.dart';

/// Single source of truth for all editor UI colors.
///
/// To retheme the editor, change the values here — nothing else needs to touch.
abstract final class EditorTheme {
  // ── Accent ───────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFFF5746F);
  static const Color primaryBright = Color(0xFFFF9C98);
  static const Color primaryActive = Color(0xFFD95450);
  static const Color primaryMuted = Color(0xFF7A4A4A);
  static const Color primaryMutedLight = Color(0xFFC97E7E);

  // ── Selection / hover backgrounds ────────────────────────────────────────
  static const Color selectionBg = Color(0xFF3D1A1A);
  static const Color dragOverBg = Color(0xFF4A1E1E);
  static const Color multiSelectBg = Color(0xFF301515);
  static const Color hoverBg = Color(0xFF33201E);
  static const Color hoverBgAlt = Color(0xFF4A2D2D);

  // ── Surfaces ─────────────────────────────────────────────────────────────
  static const Color panelBg = Color(0xFF0F0E0E);
  static const Color surfaceBg = Color(0xFF1A1818);
  static const Color dialogBg = Color(0xFF161414);
  static const Color inputBg = Color(0xFF111010);
  static const Color menuBg = Color(0xFF1C1919);
  static const Color surfaceDark = Color(0xFF0C0B0B);
  static const Color surfaceDarker = Color(0xFF0A0909);
  static const Color surfaceDarkest = Color(0xFF080707);

  // ── Borders / dividers ───────────────────────────────────────────────────
  static const Color border = Color.fromARGB(13, 245, 115, 111);

  // ── Button / badge backgrounds ───────────────────────────────────────────
  static const Color buttonBg = Color(0xFF44201F);
  static const Color statusBadgeBg = Color(0xE644201F);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFCCCCCC);
  static const Color textMuted = Color(0xFF999999);
  static const Color textBright = Color(0xFFFFFFFF);
  static const Color textBadge = Color(0xFFFFFFFF);

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const Color error = Color(0xFFE54B4B);
  static const Color errorLight = Color(0xFFFF7070);
  static const Color warning = Color(0xFFFFD660);
}
