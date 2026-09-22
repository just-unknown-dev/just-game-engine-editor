/// The screens a piece of interface is checked against.
library;

/// One screen to preview a canvas at.
class UiDevice {
  const UiDevice(this.name, this.size, {this.safeArea = 0});

  final String name;

  /// Its size in logical pixels, the long side down.
  final ({double width, double height}) size;

  /// How much of the top is taken by a notch or a status bar.
  final double safeArea;

  double get width => size.width;
  double get height => size.height;

  @override
  String toString() => '$name (${width.toInt()}×${height.toInt()})';
}

/// The screens the picker offers.
///
/// Three shapes that actually differ — a tall phone, a tablet and a
/// desktop window — rather than a catalogue nobody reads to the end.
abstract final class UiDevices {
  static const phone = UiDevice('Phone', (
    width: 393,
    height: 852,
  ), safeArea: 47);
  static const phoneSmall = UiDevice('Small phone', (
    width: 360,
    height: 640,
  ), safeArea: 24);
  static const tablet = UiDevice('Tablet', (width: 834, height: 1194));
  static const desktop = UiDevice('Desktop', (width: 1600, height: 900));

  static const List<UiDevice> all = [phone, phoneSmall, tablet, desktop];

  /// The device closest to [width] × [height], for showing a canvas at the
  /// size it was drawn for.
  static UiDevice nearest(double width, double height) {
    var best = all.first;
    var bestGap = double.infinity;
    for (final device in all) {
      final gap = (device.width - width).abs() + (device.height - height).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = device;
      }
    }
    return best;
  }
}
