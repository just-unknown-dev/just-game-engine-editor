// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'prismatic_joint_component.dart';

final CustomComponentDescriptor _$customComponentDescriptor0 =
    CustomComponentDescriptor(
      id: 'prismaticjointcomponent_a344eac0',
      name: 'PrismaticJointComponent',
      type: 'PrismaticJointComponent',
      group: 'Physics',
      description: 'Slider joint descriptor with optional limits/motor.',
      allowMultiple: false,
      factory: () => PrismaticJointComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'axis',
          label: 'Axis',
          kind: EditorFieldKind.offset,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as PrismaticJointComponent).axis,
          write: (component, value) {
            (component as PrismaticJointComponent).axis = value as Offset;
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
          read: (component) =>
              (component as PrismaticJointComponent).collideConnected,
          write: (component, value) {
            (component as PrismaticJointComponent).collideConnected =
                value as bool;
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
          read: (component) =>
              (component as PrismaticJointComponent).enableLimit,
          write: (component, value) {
            (component as PrismaticJointComponent).enableLimit = value as bool;
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
          read: (component) =>
              (component as PrismaticJointComponent).enableMotor,
          write: (component, value) {
            (component as PrismaticJointComponent).enableMotor = value as bool;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'lowerTranslation',
          label: 'Lower Translation',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) =>
              (component as PrismaticJointComponent).lowerTranslation,
          write: (component, value) {
            (component as PrismaticJointComponent).lowerTranslation =
                (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'maxMotorForce',
          label: 'Max Motor Force',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) =>
              (component as PrismaticJointComponent).maxMotorForce,
          write: (component, value) {
            (component as PrismaticJointComponent).maxMotorForce =
                (value as num).toDouble();
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
          read: (component) =>
              (component as PrismaticJointComponent).motorSpeed,
          write: (component, value) {
            (component as PrismaticJointComponent).motorSpeed = (value as num)
                .toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'targetEntityName',
          label: 'Target Entity Name',
          kind: EditorFieldKind.text,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) =>
              (component as PrismaticJointComponent).targetEntityName,
          write: (component, value) {
            (component as PrismaticJointComponent).targetEntityName =
                value as String;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'upperTranslation',
          label: 'Upper Translation',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) =>
              (component as PrismaticJointComponent).upperTranslation,
          write: (component, value) {
            (component as PrismaticJointComponent).upperTranslation =
                (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
      ],
    );

final List<CustomComponentDescriptor> _generatedCustomComponentDescriptors =
    <CustomComponentDescriptor>[_$customComponentDescriptor0];

void registerGeneratedCustomComponents([CustomComponentRegistry? registry]) {
  final target = registry ?? CustomComponentRegistry.instance;
  target.registerAll(_generatedCustomComponentDescriptors);
}
