import 'package:flutter/material.dart';

import '../../generator/component_registry.dart';
import 'wheel_joint_component.dart';

final EditorComponentDescriptor kWheelJointEditorComponent =
    EditorComponentDescriptor(
      id: 'wheel_joint_a8fea139',
      name: 'Wheel Joint',
      type: 'WheelJointComponent',
      group: 'Physics',
      description: 'Wheel suspension and motor joint.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.editor,
      icon: Icons.trip_origin,
      accentColor: const Color(0xFFFF7043),
      factory: () => WheelJointComponent(),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Joint', fields: [
          EditorComponentField(
            name: 'targetEntityName',
            label: 'Target Name',
            kind: EditorFieldKind.text,
            read: (c) => (c as WheelJointComponent).targetEntityName,
            write: (c, v) =>
                (c as WheelJointComponent).targetEntityName =
                    (v as String).trim(),
          ),
          EditorComponentField(
            name: 'suspensionAxis',
            label: 'Suspension Axis',
            kind: EditorFieldKind.offset,
            read: (c) => (c as WheelJointComponent).suspensionAxis,
            write: (c, v) =>
                (c as WheelJointComponent).suspensionAxis = v as Offset,
          ),
          EditorComponentField(
            name: 'collideConnected',
            label: 'Collide Connected',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as WheelJointComponent).collideConnected,
            write: (c, v) =>
                (c as WheelJointComponent).collideConnected = v as bool,
          ),
        ]),
        EditorFieldGroup(name: 'Motor', fields: [
          EditorComponentField(
            name: 'enableMotor',
            label: 'Enable Motor',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as WheelJointComponent).enableMotor,
            write: (c, v) =>
                (c as WheelJointComponent).enableMotor = v as bool,
          ),
          EditorComponentField(
            name: 'motorSpeed',
            label: 'Motor Speed',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 2),
            read: (c) => (c as WheelJointComponent).motorSpeed,
            write: (c, v) =>
                (c as WheelJointComponent).motorSpeed = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'maxMotorTorque',
            label: 'Max Torque',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 5.0, fractionDigits: 2, min: 0.0),
            read: (c) => (c as WheelJointComponent).maxMotorTorque,
            write: (c, v) =>
                (c as WheelJointComponent).maxMotorTorque = (v as num).toDouble(),
          ),
        ]),
        EditorFieldGroup(name: 'Spring', fields: [
          EditorComponentField(
            name: 'stiffness',
            label: 'Stiffness',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 2, min: 0.0),
            read: (c) => (c as WheelJointComponent).stiffness,
            write: (c, v) =>
                (c as WheelJointComponent).stiffness = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'damping',
            label: 'Damping',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0.0),
            read: (c) => (c as WheelJointComponent).damping,
            write: (c, v) =>
                (c as WheelJointComponent).damping = (v as num).toDouble(),
          ),
        ]),
      ],
    );
