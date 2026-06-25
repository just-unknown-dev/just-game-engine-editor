// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'prismatic_joint_component_editor.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'prismatic_joint_12030a86',
      name: 'Prismatic Joint',
      type: 'PrismaticJointEditorComponent',
      group: 'Physics',
      description: 'Slider joint with optional limits and motor.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.editor,
      factory: () => PrismaticJointEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'axis',
          label: 'Axis',
          kind: EditorFieldKind.offset,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as PrismaticJointEditorComponent).axis,
          write: (component, value) {
            (component as PrismaticJointEditorComponent).axis = value as Offset;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'collideConnected',
          label: 'Collide Connected',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as PrismaticJointEditorComponent).collideConnected,
          write: (component, value) {
            (component as PrismaticJointEditorComponent).collideConnected = value as bool;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'enableLimit',
          label: 'Enable Limit',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as PrismaticJointEditorComponent).enableLimit,
          write: (component, value) {
            (component as PrismaticJointEditorComponent).enableLimit = value as bool;
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
          read: (component) => (component as PrismaticJointEditorComponent).enableMotor,
          write: (component, value) {
            (component as PrismaticJointEditorComponent).enableMotor = value as bool;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'lowerTranslation',
          label: 'Lower',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 2),
          read: (component) => (component as PrismaticJointEditorComponent).lowerTranslation,
          write: (component, value) {
            (component as PrismaticJointEditorComponent).lowerTranslation = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'maxMotorForce',
          label: 'Max Force',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 5.0, fractionDigits: 2, min: 0.0),
          read: (component) => (component as PrismaticJointEditorComponent).maxMotorForce,
          write: (component, value) {
            (component as PrismaticJointEditorComponent).maxMotorForce = (value as num).toDouble();
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
          read: (component) => (component as PrismaticJointEditorComponent).motorSpeed,
          write: (component, value) {
            (component as PrismaticJointEditorComponent).motorSpeed = (value as num).toDouble();
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
          read: (component) => (component as PrismaticJointEditorComponent).targetEntityName,
          write: (component, value) {
            (component as PrismaticJointEditorComponent).targetEntityName = value as String;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'upperTranslation',
          label: 'Upper',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 2),
          read: (component) => (component as PrismaticJointEditorComponent).upperTranslation,
          write: (component, value) {
            (component as PrismaticJointEditorComponent).upperTranslation = (value as num).toDouble();
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
