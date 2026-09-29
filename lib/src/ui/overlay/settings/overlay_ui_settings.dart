import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// How tightly the editor's chrome is packed: the three steps the settings
/// dialog offers for [OverlayUiSettings.compactness].
enum OverlayDensity { compact, standard, comfortable }

extension OverlayDensityX on OverlayDensity {
  String get label => switch (this) {
    OverlayDensity.compact => 'Compact',
    OverlayDensity.standard => 'Default',
    OverlayDensity.comfortable => 'Comfortable',
  };

  double get compactness => switch (this) {
    OverlayDensity.compact => 0.85,
    OverlayDensity.standard => 1.0,
    OverlayDensity.comfortable => 1.15,
  };
}

/// What the autosave does with a scene that has changed.
enum AutosaveMode {
  /// A copy beside the project, in `.editor_backups/`; the scene file is
  /// left alone until it is saved.
  backup,

  /// The scene itself is saved, as Ctrl+S would.
  save,
}

/// When closing a scene asks first.
enum ClosePrompt {
  /// Only when it has changes that are not saved.
  unsaved,

  /// Every time.
  always,
}

/// Which messages show over the editor.
enum MessageLevel {
  /// Everything.
  all,

  /// Warnings and errors, and anything that follows a task.
  important,

  /// Errors, and anything that follows a task.
  errors,
}

/// A setting's allowed range, for the dialog's slider and for reading back a
/// stored value that an older editor let go further.
class SettingRange {
  const SettingRange(this.min, this.max);

  final double min;
  final double max;

  double clamp(double value) => value.clamp(min, max).toDouble();
}

/// The editor's own preferences: how its chrome looks, how it can be made
/// easier to use, how the viewport draws and snaps, how scenes are kept
/// safe, and the keys that run its commands. Persisted by the settings
/// store; modules keep theirs as [SettingPref]s beside it.
@immutable
class OverlayUiSettings {
  const OverlayUiSettings({
    required this.textScale,
    required this.cornerRadius,
    required this.themeId,
    required this.accent,
    required this.compactness,
    required this.animationSpeed,
    required this.metricRefreshMs,
    required this.showGrid,
    required this.gridSnappingEnabled,
    required this.gridSize,
    this.boldText = false,
    this.highContrast = false,
    this.colourBlindSafe = false,
    this.reduceMotion = false,
    this.longerTimings = false,
    this.alwaysShowFocus = false,
    this.largeTargets = false,
    this.autosaveMinutes = defaultAutosaveMinutes,
    this.autosaveMode = AutosaveMode.backup,
    this.backupsToKeep = defaultBackupsToKeep,
    this.reopenLastScene = true,
    this.reopenDesigner = true,
    this.shortcuts = const {},
    this.targetFps = defaultTargetFps,
    this.rotationStep = defaultRotationStep,
    this.scaleStep = defaultScaleStep,
    this.nudgeDistance = 0,
    this.moveStep = 0,
    this.smartSnap = true,
    this.gridColour = defaultGridColour,
    this.gridOpacity = 1,
    this.backdrop,
    this.gizmoScale = 1,
    this.selectionColour,
    this.pauseOnError = false,
    this.hideChromeWhilePlaying = false,
    this.undoLimit = defaultUndoLimit,
    this.confirmDelete = false,
    this.closePrompt = ClosePrompt.unsaved,
    this.consoleMaxEntries = defaultConsoleMaxEntries,
    this.consoleHiddenLevels = const [],
    this.consoleTimestamps = true,
    this.messageLevel = MessageLevel.all,
  });

  const OverlayUiSettings.defaults()
    : textScale = 1.0,
      cornerRadius = 4,
      themeId = defaultThemeId,
      accent = defaultAccent,
      compactness = 1.0,
      animationSpeed = 1.0,
      metricRefreshMs = 120,
      showGrid = true,
      gridSnappingEnabled = true,
      gridSize = 32,
      boldText = false,
      highContrast = false,
      colourBlindSafe = false,
      reduceMotion = false,
      longerTimings = false,
      alwaysShowFocus = false,
      largeTargets = false,
      autosaveMinutes = defaultAutosaveMinutes,
      autosaveMode = AutosaveMode.backup,
      backupsToKeep = defaultBackupsToKeep,
      reopenLastScene = true,
      reopenDesigner = true,
      shortcuts = const {},
      targetFps = defaultTargetFps,
      rotationStep = defaultRotationStep,
      scaleStep = defaultScaleStep,
      nudgeDistance = 0,
      moveStep = 0,
      smartSnap = true,
      gridColour = defaultGridColour,
      gridOpacity = 1,
      backdrop = null,
      gizmoScale = 1,
      selectionColour = null,
      pauseOnError = false,
      hideChromeWhilePlaying = false,
      undoLimit = defaultUndoLimit,
      confirmDelete = false,
      closePrompt = ClosePrompt.unsaved,
      consoleMaxEntries = defaultConsoleMaxEntries,
      consoleHiddenLevels = const [],
      consoleTimestamps = true,
      messageLevel = MessageLevel.all;

  /// The built-in Sunrise theme.
  static const String defaultThemeId = 'sunrise';
  static const Color defaultAccent = Color(0xFFF5746F);

  static const double defaultAutosaveMinutes = 2;
  static const int defaultBackupsToKeep = 10;
  static const double defaultTargetFps = 60;
  static const double defaultRotationStep = 15;
  static const double defaultScaleStep = 0.1;
  static const Color defaultGridColour = Color(0xFFFFFFFF);
  static const int defaultUndoLimit = 200;
  static const int defaultConsoleMaxEntries = 1000;

  static const SettingRange textScaleRange = SettingRange(0.85, 1.35);
  static const SettingRange cornerRadiusRange = SettingRange(0, 14);
  static const SettingRange compactnessRange = SettingRange(0.8, 1.2);
  static const SettingRange animationSpeedRange = SettingRange(0.5, 2);

  /// The status strip's ticker never runs faster than 100 ms.
  static const SettingRange metricRefreshRange = SettingRange(100, 2000);
  static const SettingRange gridSizeRange = SettingRange(4, 256);

  /// Minutes between autosaves; 0 is off.
  static const SettingRange autosaveRange = SettingRange(0, 60);
  static const SettingRange backupsRange = SettingRange(1, 50);
  static const SettingRange targetFpsRange = SettingRange(24, 240);

  /// Degrees.
  static const SettingRange rotationStepRange = SettingRange(1, 90);
  static const SettingRange scaleStepRange = SettingRange(0.01, 1);

  /// World units; 0 is one grid cell.
  static const SettingRange nudgeRange = SettingRange(0, 256);

  /// World units; 0 is the grid's own.
  static const SettingRange moveStepRange = SettingRange(0, 256);

  /// A multiple of the grid's own faint lines.
  static const SettingRange gridOpacityRange = SettingRange(0.25, 3);
  static const SettingRange gizmoScaleRange = SettingRange(0.75, 2);
  static const SettingRange undoLimitRange = SettingRange(20, 2000);
  static const SettingRange consoleEntriesRange = SettingRange(100, 10000);

  final double textScale;
  final double cornerRadius;

  /// The [ThemePreset] picked — a built-in accent or one a module added.
  final String themeId;

  /// That theme's accent, kept beside its id so the chrome can draw with it
  /// before the theme controller has heard from the modules.
  final Color accent;
  final double compactness;
  final double animationSpeed;
  final double metricRefreshMs;
  final bool showGrid;
  final bool gridSnappingEnabled;
  final double gridSize;

  // ── Accessibility ──────────────────────────────────────────────────────

  /// All of the chrome's text a weight heavier.
  final bool boldText;

  /// Brighter secondary text, lines that show, stronger outlines.
  final bool highContrast;

  /// Error, warning and success in colours told apart by everyone — no red
  /// against green.
  final bool colourBlindSafe;

  /// Nothing slides, fades or eases: every change is at once.
  final bool reduceMotion;

  /// Tooltips come sooner and stay longer; messages stay longer.
  final bool longerTimings;

  /// An outline on whatever has the keyboard, however it got it.
  final bool alwaysShowFocus;

  /// Every button and row at least 32 px, not 24.
  final bool largeTargets;

  // ── Saving ─────────────────────────────────────────────────────────────

  /// Minutes between autosaves of a scene with changes; 0 is off.
  final double autosaveMinutes;

  /// Whether an autosave makes a backup or saves the scene itself.
  final AutosaveMode autosaveMode;

  /// Backups kept per scene; older ones are deleted.
  final int backupsToKeep;

  /// Open the scene that was open last time, as the editor starts.
  final bool reopenLastScene;

  /// And the Level Designer, if it was open on it.
  final bool reopenDesigner;

  // ── Keyboard ───────────────────────────────────────────────────────────

  /// Commands whose keys have been changed: the command's id, and the keys
  /// that run it now as they read — `Ctrl+Shift+S` — none for no key.
  final Map<String, List<String>> shortcuts;

  // ── Performance ────────────────────────────────────────────────────────

  /// The frame rate the game aims for: the budget the status bar and the
  /// Profiler measure a frame against.
  final double targetFps;

  // ── Editing ────────────────────────────────────────────────────────────

  /// Degrees a snapped turn moves in.
  final double rotationStep;

  /// What a snapped scale moves in: 0.1 is 10 %.
  final double scaleStep;

  /// World units an arrow key moves the selection; 0 is the snap step.
  final double nudgeDistance;

  /// World units moving snaps in, whatever the grid drawn; 0 is the grid's
  /// own size. On a grid of hexagons moving snaps to the cells.
  final double moveStep;

  /// What moving snaps in on a grid of [gridSize]: [moveStep], or the grid.
  double moveStepFor(double gridSize) => moveStep > 0 ? moveStep : gridSize;

  /// In the Level Designer, snap to other things' edges and centres, and
  /// to ruler guides, as well as to the grid.
  final bool smartSnap;

  /// Steps the undo history keeps.
  final int undoLimit;

  /// Ask before deleting what is selected.
  final bool confirmDelete;

  /// When closing a scene asks first.
  final ClosePrompt closePrompt;

  // ── Viewport look ──────────────────────────────────────────────────────

  final Color gridColour;

  /// A multiple of the grid's usual faintness: 1 is as it was.
  final double gridOpacity;

  /// What the viewport clears to while editing; null keeps the game's own.
  final Color? backdrop;

  /// How big the move, scale and turn handles are drawn: 1 is as they were.
  final double gizmoScale;

  /// The outline round what is selected; null keeps each view's own.
  final Color? selectionColour;

  // ── Play-testing ───────────────────────────────────────────────────────

  /// Pause the play-test the moment an error is logged.
  final bool pauseOnError;

  /// While the play-test runs, the game fills the window and the editor
  /// steps aside to a small bar; pausing brings it back.
  final bool hideChromeWhilePlaying;

  // ── Console and messages ───────────────────────────────────────────────

  /// Lines the Console keeps; the oldest go first.
  final int consoleMaxEntries;

  /// Levels a new Console hides until they are asked for, by name.
  final List<String> consoleHiddenLevels;

  /// Show each line's time.
  final bool consoleTimestamps;

  /// Which messages show over the editor.
  final MessageLevel messageLevel;

  Color get themeColor => accent;

  /// The text scale the chrome draws with.
  double get effectiveTextScale => textScale;

  /// [rotationStep], in radians.
  double get rotationStepRadians => rotationStep * math.pi / 180;

  /// How often an autosave runs, or null when it is off.
  Duration? get autosaveInterval => autosaveMinutes <= 0
      ? null
      : Duration(milliseconds: (autosaveMinutes * 60000).round());

  /// One frame's time at [targetFps], in milliseconds.
  double get frameBudgetMs => 1000 / targetFps;

  /// The density step nearest [compactness].
  OverlayDensity get density {
    var best = OverlayDensity.standard;
    for (final d in OverlayDensity.values) {
      if ((d.compactness - compactness).abs() <
          (best.compactness - compactness).abs()) {
        best = d;
      }
    }
    return best;
  }

  /// A copy with the given settings changed. [backdrop] and
  /// [selectionColour] can be put back to "as built" with [clearBackdrop]
  /// and [clearSelectionColour].
  OverlayUiSettings copyWith({
    double? textScale,
    double? cornerRadius,
    String? themeId,
    Color? accent,
    double? compactness,
    double? animationSpeed,
    double? metricRefreshMs,
    bool? showGrid,
    bool? gridSnappingEnabled,
    double? gridSize,
    bool? boldText,
    bool? highContrast,
    bool? colourBlindSafe,
    bool? reduceMotion,
    bool? longerTimings,
    bool? alwaysShowFocus,
    bool? largeTargets,
    double? autosaveMinutes,
    AutosaveMode? autosaveMode,
    int? backupsToKeep,
    bool? reopenLastScene,
    bool? reopenDesigner,
    Map<String, List<String>>? shortcuts,
    double? targetFps,
    double? rotationStep,
    double? scaleStep,
    double? nudgeDistance,
    double? moveStep,
    bool? smartSnap,
    Color? gridColour,
    double? gridOpacity,
    Color? backdrop,
    bool clearBackdrop = false,
    double? gizmoScale,
    Color? selectionColour,
    bool clearSelectionColour = false,
    bool? pauseOnError,
    bool? hideChromeWhilePlaying,
    int? undoLimit,
    bool? confirmDelete,
    ClosePrompt? closePrompt,
    int? consoleMaxEntries,
    List<String>? consoleHiddenLevels,
    bool? consoleTimestamps,
    MessageLevel? messageLevel,
  }) {
    return OverlayUiSettings(
      textScale: textScale ?? this.textScale,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      themeId: themeId ?? this.themeId,
      accent: accent ?? this.accent,
      compactness: compactness ?? this.compactness,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      metricRefreshMs: metricRefreshMs ?? this.metricRefreshMs,
      showGrid: showGrid ?? this.showGrid,
      gridSnappingEnabled: gridSnappingEnabled ?? this.gridSnappingEnabled,
      gridSize: gridSize ?? this.gridSize,
      boldText: boldText ?? this.boldText,
      highContrast: highContrast ?? this.highContrast,
      colourBlindSafe: colourBlindSafe ?? this.colourBlindSafe,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      longerTimings: longerTimings ?? this.longerTimings,
      alwaysShowFocus: alwaysShowFocus ?? this.alwaysShowFocus,
      largeTargets: largeTargets ?? this.largeTargets,
      autosaveMinutes: autosaveMinutes ?? this.autosaveMinutes,
      autosaveMode: autosaveMode ?? this.autosaveMode,
      backupsToKeep: backupsToKeep ?? this.backupsToKeep,
      reopenLastScene: reopenLastScene ?? this.reopenLastScene,
      reopenDesigner: reopenDesigner ?? this.reopenDesigner,
      shortcuts: shortcuts ?? this.shortcuts,
      targetFps: targetFps ?? this.targetFps,
      rotationStep: rotationStep ?? this.rotationStep,
      scaleStep: scaleStep ?? this.scaleStep,
      nudgeDistance: nudgeDistance ?? this.nudgeDistance,
      moveStep: moveStep ?? this.moveStep,
      smartSnap: smartSnap ?? this.smartSnap,
      gridColour: gridColour ?? this.gridColour,
      gridOpacity: gridOpacity ?? this.gridOpacity,
      backdrop: clearBackdrop ? null : backdrop ?? this.backdrop,
      gizmoScale: gizmoScale ?? this.gizmoScale,
      selectionColour: clearSelectionColour
          ? null
          : selectionColour ?? this.selectionColour,
      pauseOnError: pauseOnError ?? this.pauseOnError,
      hideChromeWhilePlaying:
          hideChromeWhilePlaying ?? this.hideChromeWhilePlaying,
      undoLimit: undoLimit ?? this.undoLimit,
      confirmDelete: confirmDelete ?? this.confirmDelete,
      closePrompt: closePrompt ?? this.closePrompt,
      consoleMaxEntries: consoleMaxEntries ?? this.consoleMaxEntries,
      consoleHiddenLevels: consoleHiddenLevels ?? this.consoleHiddenLevels,
      consoleTimestamps: consoleTimestamps ?? this.consoleTimestamps,
      messageLevel: messageLevel ?? this.messageLevel,
    );
  }

  static bool _sameShortcuts(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final other = b[e.key];
      if (other == null || !listEquals(other, e.value)) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is OverlayUiSettings &&
      other.textScale == textScale &&
      other.cornerRadius == cornerRadius &&
      other.themeId == themeId &&
      other.accent == accent &&
      other.compactness == compactness &&
      other.animationSpeed == animationSpeed &&
      other.metricRefreshMs == metricRefreshMs &&
      other.showGrid == showGrid &&
      other.gridSnappingEnabled == gridSnappingEnabled &&
      other.gridSize == gridSize &&
      other.boldText == boldText &&
      other.highContrast == highContrast &&
      other.colourBlindSafe == colourBlindSafe &&
      other.reduceMotion == reduceMotion &&
      other.longerTimings == longerTimings &&
      other.alwaysShowFocus == alwaysShowFocus &&
      other.largeTargets == largeTargets &&
      other.autosaveMinutes == autosaveMinutes &&
      other.autosaveMode == autosaveMode &&
      other.backupsToKeep == backupsToKeep &&
      other.reopenLastScene == reopenLastScene &&
      other.reopenDesigner == reopenDesigner &&
      _sameShortcuts(other.shortcuts, shortcuts) &&
      other.targetFps == targetFps &&
      other.rotationStep == rotationStep &&
      other.scaleStep == scaleStep &&
      other.nudgeDistance == nudgeDistance &&
      other.moveStep == moveStep &&
      other.smartSnap == smartSnap &&
      other.gridColour == gridColour &&
      other.gridOpacity == gridOpacity &&
      other.backdrop == backdrop &&
      other.gizmoScale == gizmoScale &&
      other.selectionColour == selectionColour &&
      other.pauseOnError == pauseOnError &&
      other.hideChromeWhilePlaying == hideChromeWhilePlaying &&
      other.undoLimit == undoLimit &&
      other.confirmDelete == confirmDelete &&
      other.closePrompt == closePrompt &&
      other.consoleMaxEntries == consoleMaxEntries &&
      listEquals(other.consoleHiddenLevels, consoleHiddenLevels) &&
      other.consoleTimestamps == consoleTimestamps &&
      other.messageLevel == messageLevel;

  @override
  int get hashCode => Object.hash(
    textScale,
    cornerRadius,
    themeId,
    accent,
    compactness,
    animationSpeed,
    metricRefreshMs,
    showGrid,
    gridSnappingEnabled,
    gridSize,
    Object.hash(
      boldText,
      highContrast,
      colourBlindSafe,
      reduceMotion,
      longerTimings,
      alwaysShowFocus,
      largeTargets,
    ),
    Object.hash(
      autosaveMinutes,
      autosaveMode,
      backupsToKeep,
      reopenLastScene,
      reopenDesigner,
      Object.hashAllUnordered(shortcuts.keys),
      targetFps,
    ),
    Object.hash(
      rotationStep,
      scaleStep,
      nudgeDistance,
      moveStep,
      smartSnap,
      undoLimit,
      confirmDelete,
      closePrompt,
    ),
    Object.hash(gridColour, gridOpacity, backdrop, gizmoScale, selectionColour),
    Object.hash(
      pauseOnError,
      hideChromeWhilePlaying,
      consoleMaxEntries,
      Object.hashAll(consoleHiddenLevels),
      consoleTimestamps,
      messageLevel,
    ),
  );
}
