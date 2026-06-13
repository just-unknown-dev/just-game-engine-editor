// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'distance_joint_component.dart';

final CustomComponentDescriptor
_$customComponentDescriptor0 = CustomComponentDescriptor(
  id: 'distancejointcomponent_2f7c3741',
  name: 'DistanceJointComponent',
  type: 'DistanceJointComponent',
  group: 'Physics',
  description:
      'Distance/spring joint descriptor linking this entity to targetEntityName.',
  allowMultiple: false,
  factory: () => DistanceJointComponent(),
  fields: <EditorComponentField>[
    EditorComponentField(
      name: 'collideConnected',
      label: 'Collide Connected',
      kind: EditorFieldKind.boolean,
      visible: true,
      editable: true,
      includeInJson: true,
      read: (component) =>
          (component as DistanceJointComponent).collideConnected,
      write: (component, value) {
        (component as DistanceJointComponent).collideConnected = value as bool;
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
      read: (component) => (component as DistanceJointComponent).damping,
      write: (component, value) {
        (component as DistanceJointComponent).damping = (value as num)
            .toDouble();
      },
      enumValues: null,
      enumParser: null,
    ),
    EditorComponentField(
      name: 'length',
      label: 'Length',
      kind: EditorFieldKind.decimal,
      visible: true,
      editable: true,
      includeInJson: true,
      read: (component) => (component as DistanceJointComponent).length,
      write: (component, value) {
        (component as DistanceJointComponent).length = (value as num)
            .toDouble();
      },
      enumValues: null,
      enumParser: null,
    ),
    EditorComponentField(
      name: 'localAnchorA',
      label: 'Local Anchor A',
      kind: EditorFieldKind.offset,
      visible: true,
      editable: true,
      includeInJson: true,
      read: (component) => (component as DistanceJointComponent).localAnchorA,
      write: (component, value) {
        (component as DistanceJointComponent).localAnchorA = value as Offset;
      },
      enumValues: null,
      enumParser: null,
    ),
    EditorComponentField(
      name: 'localAnchorB',
      label: 'Local Anchor B',
      kind: EditorFieldKind.offset,
      visible: true,
      editable: true,
      includeInJson: true,
      read: (component) => (component as DistanceJointComponent).localAnchorB,
      write: (component, value) {
        (component as DistanceJointComponent).localAnchorB = value as Offset;
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
      read: (component) => (component as DistanceJointComponent).stiffness,
      write: (component, value) {
        (component as DistanceJointComponent).stiffness = (value as num)
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
          (component as DistanceJointComponent).targetEntityName,
      write: (component, value) {
        (component as DistanceJointComponent).targetEntityName =
            value as String;
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
