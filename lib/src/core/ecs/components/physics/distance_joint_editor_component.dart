import 'package:flutter/material.dart';

import '../../generator/component_registry.dart';
import 'distance_joint_component.dart';

final EditorComponentDescriptor kDistanceJointEditorComponent =
    EditorComponentDescriptor(
      id: 'distance_joint_ed004dd9',
      name: 'Distance Joint',
      type: 'DistanceJointComponent',
      group: 'Physics',
      description:
          'Distance/spring joint linking this entity to targetEntityName.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.editor,
      icon: Icons.hub_outlined,
      accentColor: const Color(0xFFFF7043),
      factory: () => DistanceJointComponent(),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Joint', fields: [
          EditorComponentField(
            name: 'targetEntityName',
            label: 'Target Name',
            kind: EditorFieldKind.text,
            read: (c) => (c as DistanceJointComponent).targetEntityName,
            write: (c, v) => (c as DistanceJointComponent).targetEntityName =
                (v as String).trim(),
          ),
          EditorComponentField(
            name: 'length',
            label: 'Length',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 2, min: 0.0),
            read: (c) => (c as DistanceJointComponent).length,
            write: (c, v) =>
                (c as DistanceJointComponent).length = (v as num).toDouble(),
          ),
        ]),
        EditorFieldGroup(name: 'Spring', fields: [
          EditorComponentField(
            name: 'stiffness',
            label: 'Stiffness',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 2, min: 0.0),
            read: (c) => (c as DistanceJointComponent).stiffness,
            write: (c, v) =>
                (c as DistanceJointComponent).stiffness = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'damping',
            label: 'Damping',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0.0),
            read: (c) => (c as DistanceJointComponent).damping,
            write: (c, v) =>
                (c as DistanceJointComponent).damping = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'collideConnected',
            label: 'Collide Connected',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as DistanceJointComponent).collideConnected,
            write: (c, v) =>
                (c as DistanceJointComponent).collideConnected = v as bool,
          ),
        ]),
      ],
    );
