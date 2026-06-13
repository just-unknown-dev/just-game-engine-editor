import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

/// Editor-side data component describing a prismatic/slider joint.

@ECSComponent(
  name: 'PrismaticJointComponent',
  group: 'Physics',
  description: 'Slider joint descriptor with optional limits/motor.',
)
class PrismaticJointComponent extends Component {
  PrismaticJointComponent({
    this.targetEntityName = '',
    this.axis = const Offset(1, 0),
    this.enableLimit = false,
    this.lowerTranslation = -20.0,
    this.upperTranslation = 20.0,
    this.enableMotor = false,
    this.motorSpeed = 0.0,
    this.maxMotorForce = 200.0,
    this.collideConnected = false,
  });

  String targetEntityName;
  Offset axis;
  bool enableLimit;
  double lowerTranslation;
  double upperTranslation;
  bool enableMotor;
  double motorSpeed;
  double maxMotorForce;
  bool collideConnected;
}
