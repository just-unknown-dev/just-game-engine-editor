import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Editor-side data component describing a distance/spring joint.
class DistanceJointComponent extends Component {
  DistanceJointComponent({
    this.targetEntityName = '',
    this.localAnchorA = Offset.zero,
    this.localAnchorB = Offset.zero,
    this.length = 48.0,
    this.stiffness = 80.0,
    this.damping = 0.25,
    this.collideConnected = false,
  });

  String targetEntityName;
  Offset localAnchorA;
  Offset localAnchorB;
  double length;
  double stiffness;
  double damping;
  bool collideConnected;
}

/// Editor-side data component describing a weld joint.
class WeldJointComponent extends Component {
  WeldJointComponent({
    this.targetEntityName = '',
    this.localAnchorA = Offset.zero,
    this.localAnchorB = Offset.zero,
    this.collideConnected = false,
  });

  String targetEntityName;
  Offset localAnchorA;
  Offset localAnchorB;
  bool collideConnected;
}

/// Editor-side data component describing a prismatic/slider joint.
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

/// Editor-side data component describing a wheel joint.
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
