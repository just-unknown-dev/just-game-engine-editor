// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'package:just_game_engine_editor/src/core/ecs/components/physics/wheel_joint_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'wheel_joint_a8fea139',
      name: 'Wheel Joint',
      type: 'WheelJointComponent',
      group: 'Physics',
      description: 'Wheel suspension and motor joint.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.editor,
      factory: () => WheelJointComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'collideConnected',
          label: 'Collide Connected',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as WheelJointComponent).collideConnected,
          write: (component, value) {
            (component as WheelJointComponent).collideConnected = (value as bool);
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
          read: (component) => (component as WheelJointComponent).damping,
          write: (component, value) {
            (component as WheelJointComponent).damping = ((value as num).toDouble());
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
          read: (component) => (component as WheelJointComponent).enableMotor,
          write: (component, value) {
            (component as WheelJointComponent).enableMotor = (value as bool);
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
          read: (component) => (component as WheelJointComponent).maxMotorTorque,
          write: (component, value) {
            (component as WheelJointComponent).maxMotorTorque = ((value as num).toDouble());
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
          read: (component) => (component as WheelJointComponent).motorSpeed,
          write: (component, value) {
            (component as WheelJointComponent).motorSpeed = ((value as num).toDouble());
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
          read: (component) => (component as WheelJointComponent).stiffness,
          write: (component, value) {
            (component as WheelJointComponent).stiffness = ((value as num).toDouble());
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
          read: (component) => (component as WheelJointComponent).suspensionAxis,
          write: (component, value) {
            (component as WheelJointComponent).suspensionAxis = (value as Offset);
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
          read: (component) => (component as WheelJointComponent).targetEntityName,
          write: (component, value) {
            (component as WheelJointComponent).targetEntityName = (value as String).trim();
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

// Registers all descriptors on first import of this file.
// ignore: unused_element
final bool _$registered = () {
  CustomComponentRegistry.instance.registerAll(
    _generatedEditorComponentDescriptors,
  );
  return true;
}();

// Legacy named function kept for backward compatibility.
void registerGeneratedCustomComponents([CustomComponentRegistry? registry]) {
  final target = registry ?? CustomComponentRegistry.instance;
  target.registerAll(_generatedEditorComponentDescriptors);
}
