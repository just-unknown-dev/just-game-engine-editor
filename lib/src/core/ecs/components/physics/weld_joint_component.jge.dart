// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'weld_joint_component.dart';

final CustomComponentDescriptor _$customComponentDescriptor0 =
    CustomComponentDescriptor(
      id: 'weldjointcomponent_daf32794',
      name: 'WeldJointComponent',
      type: 'WeldJointComponent',
      group: 'Physics',
      description: 'Rigid weld joint descriptor linking to targetEntityName.',
      allowMultiple: false,
      factory: () => WeldJointComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'collideConnected',
          label: 'Collide Connected',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) =>
              (component as WeldJointComponent).collideConnected,
          write: (component, value) {
            (component as WeldJointComponent).collideConnected = value as bool;
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
          read: (component) => (component as WeldJointComponent).localAnchorA,
          write: (component, value) {
            (component as WeldJointComponent).localAnchorA = value as Offset;
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
          read: (component) => (component as WeldJointComponent).localAnchorB,
          write: (component, value) {
            (component as WeldJointComponent).localAnchorB = value as Offset;
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
              (component as WeldJointComponent).targetEntityName,
          write: (component, value) {
            (component as WeldJointComponent).targetEntityName =
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
