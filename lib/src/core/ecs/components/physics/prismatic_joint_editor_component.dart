import 'package:flutter/material.dart';

import '../../generator/component_registry.dart';
import 'prismatic_joint_component.dart';

final EditorComponentDescriptor kPrismaticJointEditorComponent =
    EditorComponentDescriptor(
      id: 'prismatic_joint_12030a86',
      name: 'Prismatic Joint',
      type: 'PrismaticJointComponent',
      group: 'Physics',
      description: 'Slider joint with optional limits and motor.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.editor,
      icon: Icons.sync_alt,
      accentColor: const Color(0xFFFF7043),
      factory: () => PrismaticJointComponent(),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Joint', fields: [
          EditorComponentField(
            name: 'targetEntityName',
            label: 'Target Name',
            kind: EditorFieldKind.text,
            read: (c) => (c as PrismaticJointComponent).targetEntityName,
            write: (c, v) =>
                (c as PrismaticJointComponent).targetEntityName =
                    (v as String).trim(),
          ),
          EditorComponentField(
            name: 'axis',
            label: 'Axis',
            kind: EditorFieldKind.offset,
            read: (c) => (c as PrismaticJointComponent).axis,
            write: (c, v) =>
                (c as PrismaticJointComponent).axis = v as Offset,
          ),
          EditorComponentField(
            name: 'collideConnected',
            label: 'Collide Connected',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as PrismaticJointComponent).collideConnected,
            write: (c, v) =>
                (c as PrismaticJointComponent).collideConnected = v as bool,
          ),
        ]),
        EditorFieldGroup(name: 'Motor', fields: [
          EditorComponentField(
            name: 'enableMotor',
            label: 'Enable Motor',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as PrismaticJointComponent).enableMotor,
            write: (c, v) =>
                (c as PrismaticJointComponent).enableMotor = v as bool,
          ),
          EditorComponentField(
            name: 'motorSpeed',
            label: 'Motor Speed',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 2),
            read: (c) => (c as PrismaticJointComponent).motorSpeed,
            write: (c, v) =>
                (c as PrismaticJointComponent).motorSpeed = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'maxMotorForce',
            label: 'Max Force',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 5.0, fractionDigits: 2, min: 0.0),
            read: (c) => (c as PrismaticJointComponent).maxMotorForce,
            write: (c, v) =>
                (c as PrismaticJointComponent).maxMotorForce = (v as num).toDouble(),
          ),
        ]),
        EditorFieldGroup(name: 'Limits', fields: [
          EditorComponentField(
            name: 'enableLimit',
            label: 'Enable Limit',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as PrismaticJointComponent).enableLimit,
            write: (c, v) =>
                (c as PrismaticJointComponent).enableLimit = v as bool,
          ),
          EditorComponentField(
            name: 'lowerTranslation',
            label: 'Lower',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 2),
            read: (c) => (c as PrismaticJointComponent).lowerTranslation,
            write: (c, v) =>
                (c as PrismaticJointComponent).lowerTranslation =
                    (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'upperTranslation',
            label: 'Upper',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 2),
            read: (c) => (c as PrismaticJointComponent).upperTranslation,
            write: (c, v) =>
                (c as PrismaticJointComponent).upperTranslation =
                    (v as num).toDouble(),
          ),
        ]),
      ],
    );
