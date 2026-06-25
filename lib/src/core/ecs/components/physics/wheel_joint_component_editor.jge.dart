// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'wheel_joint_component_editor.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'wheel_joint_a8fea139',
      name: 'Wheel Joint',
      type: 'WheelJointEditorComponent',
      group: 'Physics',
      description: 'Wheel suspension and motor joint.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.editor,
      factory: () => WheelJointEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'collideConnected',
          label: 'Collide Connected',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as WheelJointEditorComponent).collideConnected,
          write: (component, value) {
            (component as WheelJointEditorComponent).collideConnected = value as bool;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'damping',
          label: 'Damping',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0.0),
          read: (component) => (component as WheelJointEditorComponent).damping,
          write: (component, value) {
            (component as WheelJointEditorComponent).damping = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'enableMotor',
          label: 'Enable Motor',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as WheelJointEditorComponent).enableMotor,
          write: (component, value) {
            (component as WheelJointEditorComponent).enableMotor = value as bool;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'maxMotorTorque',
          label: 'Max Torque',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 5.0, fractionDigits: 2, min: 0.0),
          read: (component) => (component as WheelJointEditorComponent).maxMotorTorque,
          write: (component, value) {
            (component as WheelJointEditorComponent).maxMotorTorque = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'motorSpeed',
          label: 'Motor Speed',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 2),
          read: (component) => (component as WheelJointEditorComponent).motorSpeed,
          write: (component, value) {
            (component as WheelJointEditorComponent).motorSpeed = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'stiffness',
          label: 'Stiffness',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 2, min: 0.0),
          read: (component) => (component as WheelJointEditorComponent).stiffness,
          write: (component, value) {
            (component as WheelJointEditorComponent).stiffness = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'suspensionAxis',
          label: 'Suspension Axis',
          kind: EditorFieldKind.offset,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as WheelJointEditorComponent).suspensionAxis,
          write: (component, value) {
            (component as WheelJointEditorComponent).suspensionAxis = value as Offset;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'targetEntityName',
          label: 'Target Name',
          kind: EditorFieldKind.text,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as WheelJointEditorComponent).targetEntityName,
          write: (component, value) {
            (component as WheelJointEditorComponent).targetEntityName = value as String;
          },
          enumValues: null,
          enumParser: null,
        ),
      ],
    );

final List<EditorComponentDescriptor> _generatedEditorComponentDescriptors =
    <EditorComponentDescriptor>[
      _$editorComponentDescriptor0,
    ];

void registerGeneratedCustomComponents([CustomComponentRegistry? registry]) {
  final target = registry ?? CustomComponentRegistry.instance;
  target.registerAll(_generatedEditorComponentDescriptors);
}
