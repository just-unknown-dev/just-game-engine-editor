import 'dart:math' as math;
import 'dart:ui';

/// Where the select tool's handles sit and how they feel, in screen pixels.
///
/// One per scope, so the select tool, the overlay that draws the handles and
/// anything a module adds all agree on where a knob is. A module that
/// replaces the select tool supplies its own.
class SelectionHandleLayout {
  const SelectionHandleLayout({
    this.handlePixels = 7,
    this.rotateKnobPixels = 28,
    this.ringPadPixels = 16,
    this.ringMinPixels = 40,
    this.snapPixels = 6,
    this.rotationStep = math.pi / 12,
  });

  /// Resize handle hit radius.
  final double handlePixels;

  /// How far above the bounds the rotate knob sits.
  final double rotateKnobPixels;

  /// How close an edge has to come to another before it snaps.
  final double snapPixels;

  /// Rotation step while snapping, in radians.
  final double rotationStep;

  /// How far the rotate ring stands clear of the selection's corners.
  final double ringPadPixels;

  /// The smallest the rotate ring gets, around a point or a small thing.
  final double ringMinPixels;

  /// The rotate ring's radius about [bounds]' centre, in world units, given
  /// [unitsPerPixel]: clear of the corners, so it never sits where a resize
  /// handle would.
  double ringRadius(Rect bounds, double unitsPerPixel) => math.max(
    math.sqrt(bounds.width * bounds.width + bounds.height * bounds.height) / 2 +
        ringPadPixels * unitsPerPixel,
    ringMinPixels * unitsPerPixel,
  );

  /// Where the rotate knob sits for [bounds], given [unitsPerPixel].
  Offset rotateKnobAt(Rect bounds, double unitsPerPixel) =>
      Offset(bounds.center.dx, bounds.top - rotateKnobPixels * unitsPerPixel);
}
