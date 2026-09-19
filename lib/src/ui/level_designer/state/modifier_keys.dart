import 'package:flutter/services.dart';

/// The modifier keys held during a pointer gesture.
class ModifierKeys {
  const ModifierKeys({
    this.shift = false,
    this.alt = false,
    this.control = false,
  });

  /// Reads the live keyboard state.
  ///
  /// Falls back to no modifiers when no Flutter binding exists, so a headless
  /// caller degrades to plain unmodified gestures rather than throwing.
  factory ModifierKeys.fromHardwareKeyboard() {
    try {
      final keys = HardwareKeyboard.instance;
      return ModifierKeys(
        shift: keys.isShiftPressed,
        alt: keys.isAltPressed,
        control: keys.isControlPressed,
      );
    } catch (_) {
      return const ModifierKeys();
    }
  }

  /// Shift: constrains a drag to its dominant axis.
  final bool shift;

  /// Alt: temporarily suspends snapping.
  final bool alt;

  /// Control: adds to the selection rather than replacing it.
  final bool control;
}
