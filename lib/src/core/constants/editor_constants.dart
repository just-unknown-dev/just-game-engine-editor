import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/editor_metrics.dart';
import '../theme/editor_theme_data.dart';
import '../theme/theme_controller.dart';

/// Single source of truth for editor-wide constants — colors, layout
/// dimensions, persisted-setting keys, and other shared values.
///
/// To retheme or resize the editor, change the values here — nothing else
/// needs to touch.

// ── Theme ────────────────────────────────────────────────────────────────────

abstract final class EditorTheme {
  /// The palette in force at [context]. The getters below read the same
  /// palette without a context.
  static EditorThemeData of(BuildContext context) =>
      EditorThemeScope.of(context);

  /// The palette every colour below reads: [EditorThemeData.classic] until
  /// the overlay applies the accent the user picked, or a module's preset.
  static EditorThemeData get current => _current;
  static EditorThemeData _current = EditorThemeData.classic;

  /// Makes [data] the palette. The overlay does this when the theme changes,
  /// and rebuilds everything it draws so what reads a colour here sees the
  /// new one; anything else built after this reads it too.
  static void apply(EditorThemeData data) => _current = data;

  /// The accent: what is picked, switched on, or wants to be seen.
  static Color get accent => _current.primary;

  // ── Accent ─────────────────────────────────────────────────────────────────
  static Color get primary => _current.primary;
  static Color get primaryBright => _current.primaryBright;
  static Color get primaryActive => _current.primaryActive;
  static Color get primaryMuted => _current.primaryMuted;
  static Color get primaryMutedLight => _current.primaryMutedLight;

  // ── Selection / hover backgrounds ──────────────────────────────────────────
  static Color get selectionBg => _current.selectionBg;
  static Color get dragOverBg => _current.dragOverBg;
  static Color get multiSelectBg => _current.multiSelectBg;
  static Color get hoverBg => _current.hoverBg;
  static Color get hoverBgAlt => _current.hoverBgAlt;

  // ── Surfaces ───────────────────────────────────────────────────────────────
  static Color get panelBg => _current.panelBg;
  static Color get surfaceBg => _current.surfaceBg;
  static Color get dialogBg => _current.dialogBg;
  static Color get inputBg => _current.inputBg;
  static Color get menuBg => _current.menuBg;
  static Color get panelRaised => _current.panelRaised;
  static Color get surfaceDark => _current.surfaceDark;
  static Color get surfaceDarker => _current.surfaceDarker;
  static Color get surfaceDarkest => _current.surfaceDarkest;

  // ── Borders / dividers ─────────────────────────────────────────────────────
  static Color get border => _current.border;
  static Color get borderStrong => _current.borderStrong;

  // ── Button / badge backgrounds ─────────────────────────────────────────────
  static Color get buttonBg => _current.buttonBg;
  static Color get statusBadgeBg => _current.statusBadgeBg;

  // ── Text ───────────────────────────────────────────────────────────────────
  static Color get textPrimary => _current.textPrimary;
  static Color get textSecondary => _current.textSecondary;
  static Color get textMuted => _current.textMuted;
  static Color get textBright => _current.textBright;
  static Color get textBadge => _current.textBadge;

  // ── Semantic ───────────────────────────────────────────────────────────────
  static Color get error => _current.error;
  static Color get errorLight => _current.errorLight;
  static Color get warning => _current.warning;
  static Color get success => _current.success;
  static Color get info => _current.info;
}

// ── Overlay layout ───────────────────────────────────────────────────────────

abstract final class OverlayLayout {
  /// The status bar: one line of text.
  static double get compactDockPanelHeight =>
      EditorMetrics.settings.largeTargets ? 34 : 26;
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

  /// How near an arrow's shaft a press has to be to take it.
  static const double axisHitWidth = 6.0;

  /// How near the rotate ring a press has to be to take it.
  static const double ringHitWidth = 8.0;

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
  static const String prefThemeId = 'editor.overlay.themeId';
  static const String prefAccent = 'editor.overlay.accent';

  /// The accent as an index into the five built-in ones, from before a
  /// module could add its own; read once, when there is no [prefThemeId].
  static const String prefLegacyThemePreset = 'editor.overlay.themePreset';
  static const String prefCompactness = 'editor.overlay.compactness';
  static const String prefAnimationSpeed = 'editor.overlay.animationSpeed';
  static const String prefMetricRefreshMs = 'editor.overlay.metricRefreshMs';
  static const String prefShowGrid = 'editor.overlay.showGrid';
  static const String prefGridSnappingEnabled =
      'editor.overlay.gridSnappingEnabled';
  static const String prefGridSize = 'editor.overlay.gridSize';

  // Accessibility.
  static const String prefBoldText = 'editor.a11y.boldText';
  static const String prefHighContrast = 'editor.a11y.highContrast';
  static const String prefColourBlindSafe = 'editor.a11y.colourBlindSafe';
  static const String prefReduceMotion = 'editor.a11y.reduceMotion';
  static const String prefLongerTimings = 'editor.a11y.longerTimings';
  static const String prefAlwaysShowFocus = 'editor.a11y.alwaysShowFocus';
  static const String prefLargeTargets = 'editor.a11y.largeTargets';

  // Saving and starting.
  static const String prefAutosaveMinutes = 'editor.save.autosaveMinutes';
  static const String prefAutosaveMode = 'editor.save.autosaveMode';
  static const String prefBackupsToKeep = 'editor.save.backupsToKeep';
  static const String prefReopenLastScene = 'editor.startup.reopenLastScene';
  static const String prefReopenDesigner = 'editor.startup.reopenDesigner';

  // Keyboard: the commands whose keys were changed, as JSON.
  static const String prefShortcuts = 'editor.keys.shortcuts';

  // Performance.
  static const String prefTargetFps = 'editor.performance.targetFps';

  // Editing.
  static const String prefRotationStep = 'editor.edit.rotationStep';
  static const String prefScaleStep = 'editor.edit.scaleStep';
  static const String prefNudgeDistance = 'editor.edit.nudgeDistance';
  static const String prefSmartSnap = 'editor.edit.smartSnap';
  static const String prefMoveStep = 'editor.edit.moveStep';
  static const String prefUndoLimit = 'editor.edit.undoLimit';
  static const String prefConfirmDelete = 'editor.edit.confirmDelete';
  static const String prefClosePrompt = 'editor.edit.closePrompt';

  // The viewport's look.
  static const String prefGridColour = 'editor.viewport.gridColour';
  static const String prefGridOpacity = 'editor.viewport.gridOpacity';
  static const String prefBackdrop = 'editor.viewport.backdrop';
  static const String prefGizmoScale = 'editor.viewport.gizmoScale';
  static const String prefSelectionColour = 'editor.viewport.selectionColour';

  // Play-testing.
  static const String prefPauseOnError = 'editor.play.pauseOnError';
  static const String prefHideChromeWhilePlaying = 'editor.play.hideChrome';

  // The Console and messages.
  static const String prefConsoleMaxEntries = 'editor.console.maxEntries';
  static const String prefConsoleHiddenLevels = 'editor.console.hiddenLevels';
  static const String prefConsoleTimestamps = 'editor.console.timestamps';
  static const String prefMessageLevel = 'editor.messages.level';

  // Where the last session left off — kept, not settings: never exported.
  static const String sessionLastScene = 'editor.session.lastScene';
  static const String sessionDesignerOpen = 'editor.session.designerOpen';
  static const String sessionRecentScenes = 'editor.session.recentScenes';

  // How the Scenes list is sorted — kept with the session, not a setting.
  static const String scenesSort = 'editor.scenes.sort';
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
