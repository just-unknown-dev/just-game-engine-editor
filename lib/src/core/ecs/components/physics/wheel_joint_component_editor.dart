import 'package:flutter/painting.dart';

import '../../generator/component_annotations.dart';
import 'wheel_joint_component.dart';

@ECSComponent(
  name: 'Wheel Joint',
  group: 'Physics',
  description: 'Wheel suspension and motor joint.',
  componentType: ECSComponentType.editor,
)
class WheelJointEditorComponent extends WheelJointComponent {
  WheelJointEditorComponent() : super();

  @EditorField(label: 'Target Name')
  @override
  String get targetEntityName => super.targetEntityName;
  @override
  set targetEntityName(String v) => super.targetEntityName = v.trim();

  @EditorField(label: 'Suspension Axis')
  @override
  Offset get suspensionAxis => super.suspensionAxis;
  @override
  set suspensionAxis(Offset v) => super.suspensionAxis = v;

  @EditorField(label: 'Stiffness', scrubStep: 1.0, scrubFractionDigits: 2, scrubMin: 0)
  @override
  double get stiffness => super.stiffness;
  @override
  set stiffness(double v) => super.stiffness = v;

  @EditorField(label: 'Damping', scrubStep: 0.05, scrubFractionDigits: 2, scrubMin: 0)
  @override
  double get damping => super.damping;
  @override
  set damping(double v) => super.damping = v;

  @EditorField(label: 'Enable Motor')
  @override
  bool get enableMotor => super.enableMotor;
  @override
  set enableMotor(bool v) => super.enableMotor = v;

  @EditorField(label: 'Motor Speed', scrubStep: 0.5, scrubFractionDigits: 2)
  @override
  double get motorSpeed => super.motorSpeed;
  @override
  set motorSpeed(double v) => super.motorSpeed = v;

  @EditorField(label: 'Max Torque', scrubStep: 5.0, scrubFractionDigits: 2, scrubMin: 0)
  @override
  double get maxMotorTorque => super.maxMotorTorque;
  @override
  set maxMotorTorque(double v) => super.maxMotorTorque = v;

  @EditorField(label: 'Collide Connected')
  @override
  bool get collideConnected => super.collideConnected;
  @override
  set collideConnected(bool v) => super.collideConnected = v;
}
