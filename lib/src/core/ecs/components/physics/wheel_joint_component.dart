import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

/// Editor-side data component describing a wheel joint.

@ECSComponent(
  name: 'WheelJointComponent',
  group: 'Physics',
  description: 'Wheel suspension + motor joint descriptor.',
)
class WheelJointComponent extends Component {
  WheelJointComponent({
    this.targetEntityName = '',
    this.suspensionAxis = const Offset(0, 1),
    this.stiffness = 45.0,
    this.damping = 0.65,
    this.enableMotor = true,
    this.motorSpeed = 12.0,
    this.maxMotorTorque = 250.0,
    this.collideConnected = false,
  });

  String targetEntityName;
  Offset suspensionAxis;
  double stiffness;
  double damping;
  bool enableMotor;
  double motorSpeed;
  double maxMotorTorque;
  bool collideConnected;
}
