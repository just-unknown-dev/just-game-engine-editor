import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/editor_theme_data.dart';
import '../theme/theme_controller.dart';

/// Single source of truth for editor-wide constants — colors, layout
/// dimensions, persisted-setting keys, and other shared values.
///
/// To retheme or resize the editor, change the values here — nothing else
/// needs to touch.

// ── Theme ────────────────────────────────────────────────────────────────────

abstract final class EditorTheme {
  /// The palette in force at [context]: a module's preset, the accent the
  /// user picked, or these constants when nothing has changed them. New code
  /// reads colours here; the constants below are the classic palette.
  static EditorThemeData of(BuildContext context) =>
      EditorThemeScope.of(context);

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

// ── Overlay layout ───────────────────────────────────────────────────────────

abstract final class OverlayLayout {
  /// The status bar: one line of text.
  static const double compactDockPanelHeight = 26;
  static const double rightPanelDefaultWidth = 360;
  static const double rightPanelMinWidth = 280;
  static const double rightPanelMaxWidth = 640;
  static const int perfHistoryCapacity = 180;
}

abstract final class TimelinePanelLayout {
  static const double labelWidth = 68.0;
  static const double rulerHeight = 22.0;
  static const double frameTrackHeight = 36.0;
  static const double trackHeight = 26.0;
  static const double eventTrackHeight = 26.0;
  static const double defaultPxPerSecond = 120.0;
}

// ── Gizmo painting / hit-testing ──────────────────────────────────────────────

/// Shared between [GizmoPainter] (drawing) and [GizmoHitTester] (hit-testing)
/// so the clickable areas always line up with what's actually drawn.
abstract final class GizmoConstants {
  // Shared with hit-testing — keep in sync with what's drawn.
  static const double arrowLength = 52.0;
  static const double rotRadius = 60.0;
  static const double scaleHandle = 7.0;
  static const double rotSweep = math.pi * 0.75;
  static const double axisSquareOffset = 30.0;

  // Painter-only.
  static const double arrowHeadLength = 12.0;
  static const double arrowHeadWidth = 7.0;
  static const double dotRadius = 5.0;
  static const double moveHandleRadius = 8.0;
  static const double axisSquareHalf = 5.0;
  static const double minGridScreenSpacing = 14.0;

  // Hit-tester-only.
  static const double arrowTipRadius = 14.0;
  static const double rotDotRadius = 10.0;
  static const double axisSquareHitRadius = 9.0;
  static const double moveHandleHitRadius = 11.0;

  // Colours.
  static const Color colX = Color(0xFFE54B4B);
  static const Color colY = Color(0xFF4BCC73);
  static const Color colRot = Color(0xFFFFD660);
  static const Color colScale = Color(0xFFCCCCCC);
  static const Color colSel = Color(0xFF40E0D0);
  static const Color colOrigin = Color(0xFFFFFFFF);
  static const Color colMove = Color(0xFF40E0D0);

  static const Size defaultSelectionSize = Size(32, 32);
}

// ── Persisted overlay settings keys ───────────────────────────────────────────

abstract final class OverlaySettingsPrefKeys {
  static const String prefTextScale = 'editor.overlay.textScale';
  static const String prefCornerRadius = 'editor.overlay.cornerRadius';
  static const String prefThemePreset = 'editor.overlay.themePreset';
  static const String prefCompactness = 'editor.overlay.compactness';
  static const String prefAnimationSpeed = 'editor.overlay.animationSpeed';
  static const String prefEcsWarnOnInactive =
      'editor.overlay.ecsWarnOnInactive';
  static const String prefEcsWarnOnNoSystems =
      'editor.overlay.ecsWarnOnNoSystems';
  static const String prefWarningSeverity = 'editor.overlay.warningSeverity';
  static const String prefMetricRefreshMs = 'editor.overlay.metricRefreshMs';
  static const String prefLogLineClamp = 'editor.overlay.logLineClamp';
  static const String prefLogsAutoScroll = 'editor.overlay.logsAutoScroll';
  static const String prefAccessibilityMode =
      'editor.overlay.accessibilityMode';
  static const String prefShowGrid = 'editor.overlay.showGrid';
  static const String prefGridSnappingEnabled =
      'editor.overlay.gridSnappingEnabled';
  static const String prefGridSize = 'editor.overlay.gridSize';
}

// ── Editor log service ────────────────────────────────────────────────────────

abstract final class EditorLogConstants {
  static const int maxEntries = 1000;

  /// Maximum file size in bytes before the log is rotated (~5 MB).
  static const int maxFileSizeBytes = 5 * 1024 * 1024;

  /// Number of backup files to keep alongside the primary log.
  static const int maxBackupFiles = 2;
}

// ── Color history ─────────────────────────────────────────────────────────────

abstract final class ColorHistoryConstants {
  /// At most this many entries are kept; adding a duplicate bumps it to front.
  static const int maxColors = 16;
  static const String dbName = 'just_game_editor';
  static const String table = 'editor_color_history';
}

// ── Component picker ──────────────────────────────────────────────────────────

/// Groups used to categorise the component list in the picker.
/// Preferred ordering for the Add Component picker's sections.
///
/// This is an *ordering hint*, not a whitelist. Anything a descriptor declares
/// that is not listed here still appears, after these. It used to be a hard
/// filter, which meant a project's own component group was invisible in the
/// picker — including via search, since filtering ran before the check.
const List<String> kComponentGroups = [
  'Core',
  'Rendering',
  'Physics',
  'Gameplay',
  'Input',
  'Camera',
  'Audio',
  'Animation',
  'Hierarchy',
  'Effects',
  'UI',
];
