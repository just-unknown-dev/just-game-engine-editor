import 'package:flutter/painting.dart';

import '../../generator/component_annotations.dart';
import 'simple_movement_component.dart';

@ECSComponent(
  name: 'Simple Movement',
  group: 'Input',
  description: 'Moves Transform from keyboard/joystick direction with a speed scalar.',
  componentType: ECSComponentType.editor,
)
class SimpleMovementEditorComponent extends SimpleMovementComponent {
  SimpleMovementEditorComponent() : super();

  @EditorField(label: 'Speed', scrubStep: 5.0, scrubFractionDigits: 1, scrubMin: 0.0)
  @override
  double get speed => super.speed;
  @override
  set speed(double v) => super.speed = v;

  @EditorField(label: 'Dead Zone', scrubStep: 0.01, scrubFractionDigits: 2)
  @override
  double get deadZone => super.deadZone;
  @override
  set deadZone(double v) => super.deadZone = v;

  @EditorField(label: 'Normalize Diagonal')
  @override
  bool get normalizeDiagonal => super.normalizeDiagonal;
  @override
  set normalizeDiagonal(bool v) => super.normalizeDiagonal = v;

  @EditorField(label: 'Use Keyboard')
  @override
  bool get useKeyboard => super.useKeyboard;
  @override
  set useKeyboard(bool v) => super.useKeyboard = v;

  @EditorField(label: 'Use Joystick')
  @override
  bool get useJoystick => super.useJoystick;
  @override
  set useJoystick(bool v) => super.useJoystick = v;

  @EditorField(visible: false, readOnly: true, includeInJson: false)
  @override
  Offset get lastDirection => super.lastDirection;
}
