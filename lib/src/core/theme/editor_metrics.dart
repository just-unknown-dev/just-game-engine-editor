import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../ui/overlay/settings/overlay_ui_settings.dart';

/// The editor's sizes as the settings make them: radii from the corner
/// radius, gaps from the density, durations from the animation speed — and
/// the accessibility settings over all of them: bigger targets, no motion,
/// longer timings.
///
/// Like `EditorTheme`'s colours, these read what the overlay last applied,
/// and the overlay rebuilds what it draws when they change. Text needs
/// nothing here: the overlay scales it with a [TextScaler], so a font size
/// is written as it reads at 100%.
abstract final class EditorMetrics {
  static OverlayUiSettings _s = const OverlayUiSettings.defaults();

  /// The settings these were last worked out from.
  static OverlayUiSettings get settings => _s;

  /// Takes the sizes from [s]. True when any of them changed.
  static bool apply(OverlayUiSettings s) {
    final changed =
        s.cornerRadius != _s.cornerRadius ||
        s.compactness != _s.compactness ||
        s.animationSpeed != _s.animationSpeed ||
        s.textScale != _s.textScale ||
        s.boldText != _s.boldText ||
        s.reduceMotion != _s.reduceMotion ||
        s.longerTimings != _s.longerTimings ||
        s.alwaysShowFocus != _s.alwaysShowFocus ||
        s.largeTargets != _s.largeTargets;
    _s = s;
    return changed;
  }

  // ── Radius ─────────────────────────────────────────────────────────────

  /// A chip inside something else, a keycap.
  static double get radiusXs => math.max(0, _s.cornerRadius - 1);

  /// Fields and buttons: the corner radius the user picked.
  static double get radiusSm => _s.cornerRadius;

  /// Cards and menus.
  static double get radiusMd => _s.cornerRadius + 2;

  /// What floats over the level — toolbars, the settings, dialogs.
  static double get radiusLg => _s.cornerRadius + 6;

  static const double radiusPill = 999;

  // ── Spacing ────────────────────────────────────────────────────────────

  /// [base] as the density has it: tighter when compact.
  static double space(double base) => base * _s.compactness;

  static double get gapXs => space(2);
  static double get gapSm => space(4);
  static double get gapMd => space(6);
  static double get gapLg => space(8);
  static double get gapXl => space(12);
  static double get gapXxl => space(16);

  // ── Controls ───────────────────────────────────────────────────────────

  /// Never smaller than a comfortable target, however compact: 24 px, or
  /// 32 with bigger targets.
  static double get minTarget => _s.largeTargets ? 32 : 24;

  /// An icon button, a chip, a row's control.
  static double get controlSm => math.max(minTarget, 24 * _s.compactness);

  /// A toolbar button.
  static double get controlMd => math.max(minTarget + 4, 28 * _s.compactness);

  /// A field's height, as the inspector draws them.
  static double get fieldHeight => math.max(minTarget, 28 * _s.compactness);

  static const double iconSm = 12;
  static const double iconMd = 14;
  static const double iconLg = 16;

  // ── Type, at 100% ──────────────────────────────────────────────────────

  /// An uppercase caption over a group: `LAYERS`.
  static const double fontCaption = 9;

  /// A field's label, a hint.
  static const double fontLabel = 10;

  /// What most of the editor says.
  static const double fontBody = 11;

  /// A section's or a dialog's title.
  static const double fontTitle = 13;

  /// A page's title.
  static const double fontHeading = 16;

  // ── Motion ─────────────────────────────────────────────────────────────

  /// Nothing at all with reduced motion: every change is at once.
  static Duration _ms(double ms) => _s.reduceMotion
      ? Duration.zero
      : Duration(milliseconds: (ms / _s.animationSpeed).round());

  /// A hover, a toggle.
  static Duration get motionFast => _ms(120);

  /// A panel sliding open.
  static Duration get motionMedium => _ms(220);

  /// Something large moving.
  static Duration get motionSlow => _ms(400);

  // ── Timings ────────────────────────────────────────────────────────────

  /// How long the pointer rests before a tooltip shows: sooner with longer
  /// timings.
  static Duration get tooltipWait =>
      Duration(milliseconds: _s.longerTimings ? 100 : 400);

  /// How long a tooltip stays after the pointer has left it.
  static Duration get tooltipLinger =>
      Duration(milliseconds: _s.longerTimings ? 1500 : 100);

  /// How much longer a message stays before it goes by itself.
  static double get messageTimeScale => _s.longerTimings ? 2.5 : 1;

  // ── Focus ──────────────────────────────────────────────────────────────

  /// Whether what has the keyboard is outlined however it got it, rather
  /// than only while the keyboard is being used.
  static bool get alwaysShowFocus => _s.alwaysShowFocus;
}
