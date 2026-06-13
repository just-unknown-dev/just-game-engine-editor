import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

/// Editor-friendly movement component for quick keyboard/joystick motion.

@ECSComponent(
  name: 'SimpleMovementComponent',
  group: 'Input',
  description:
      'Moves Transform from keyboard/joystick direction with a speed scalar.',
)
class SimpleMovementComponent extends Component {
  SimpleMovementComponent({
    this.speed = 220.0,
    this.useKeyboard = true,
    this.useJoystick = true,
    this.normalizeDiagonal = true,
    this.deadZone = 0.05,
  });

  /// Units per second.
  double speed;

  /// Read movement from keyboard axes (horizontal/vertical).
  bool useKeyboard;

  /// Read movement from an entity-local [JoystickInputComponent] if present.
  bool useJoystick;

  /// Keeps diagonal movement speed consistent.
  bool normalizeDiagonal;

  /// Ignore tiny joystick/key noise values near zero.
  double deadZone;

  /// Runtime-only resolved direction, useful for inspector readout.
  Offset lastDirection = Offset.zero;
}
