import 'package:flutter/painting.dart';

/// The frame of the game camera preview: what makes it the same kind of panel
/// as the play toolbar above it.
class GamePreviewStyle {
  const GamePreviewStyle({
    this.cornerRadius = 12,
    this.borderColor,
    this.padding = 5,
  });

  /// Corner radius of the panel — the toolbar's.
  final double cornerRadius;

  /// Border colour — the overlay's theme colour, as on the toolbar.
  final Color? borderColor;

  /// Space between the panel's edge and what is in it.
  final double padding;
}
