import 'package:just_editor_core/host.dart';

/// Sizes of the overlay's frame, in logical pixels.
abstract final class OverlayLayout {
  /// The status bar: one line of text.
  static double get compactDockPanelHeight =>
      EditorMetrics.settings.largeTargets ? 34 : 26;

  /// The narrowest the right panel can be dragged.
  static const double rightPanelMinWidth = 280;

  /// The widest the right panel can be dragged.
  static const double rightPanelMaxWidth = 640;
}
