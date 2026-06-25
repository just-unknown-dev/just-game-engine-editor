import 'package:flutter/painting.dart';

import '../../generator/component_annotations.dart';
import 'prismatic_joint_component.dart';

@ECSComponent(
  name: 'Prismatic Joint',
  group: 'Physics',
  description: 'Slider joint with optional limits and motor.',
  componentType: ECSComponentType.editor,
)
class PrismaticJointEditorComponent extends PrismaticJointComponent {
  PrismaticJointEditorComponent() : super();

  @EditorField(label: 'Target Name')
  @override
  String get targetEntityName => super.targetEntityName;
  @override
  set targetEntityName(String v) => super.targetEntityName = v.trim();

  @EditorField(label: 'Axis')
  @override
  Offset get axis => super.axis;
  @override
  set axis(Offset v) => super.axis = v;

  @EditorField(label: 'Enable Limit')
  @override
  bool get enableLimit => super.enableLimit;
  @override
  set enableLimit(bool v) => super.enableLimit = v;

  @EditorField(label: 'Lower', scrubStep: 1.0, scrubFractionDigits: 2)
  @override
  double get lowerTranslation => super.lowerTranslation;
  @override
  set lowerTranslation(double v) => super.lowerTranslation = v;

  @EditorField(label: 'Upper', scrubStep: 1.0, scrubFractionDigits: 2)
  @override
  double get upperTranslation => super.upperTranslation;
  @override
  set upperTranslation(double v) => super.upperTranslation = v;

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

  @EditorField(label: 'Max Force', scrubStep: 5.0, scrubFractionDigits: 2, scrubMin: 0)
  @override
  double get maxMotorForce => super.maxMotorForce;
  @override
  set maxMotorForce(double v) => super.maxMotorForce = v;

  @EditorField(label: 'Collide Connected')
  @override
  bool get collideConnected => super.collideConnected;
  @override
  set collideConnected(bool v) => super.collideConnected = v;
}
