// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'distance_joint_component_editor.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'distance_joint_ed004dd9',
      name: 'Distance Joint',
      type: 'DistanceJointEditorComponent',
      group: 'Physics',
      description: 'Distance/spring joint linking this entity to targetEntityName.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.editor,
      factory: () => DistanceJointEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'collideConnected',
          label: 'Collide Connected',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as DistanceJointEditorComponent).collideConnected,
          write: (component, value) {
            (component as DistanceJointEditorComponent).collideConnected = value as bool;
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
          read: (component) => (component as DistanceJointEditorComponent).damping,
          write: (component, value) {
            (component as DistanceJointEditorComponent).damping = (value as num).toDouble();
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
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 2, min: 0.0),
          read: (component) => (component as DistanceJointEditorComponent).length,
          write: (component, value) {
            (component as DistanceJointEditorComponent).length = (value as num).toDouble();
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
          read: (component) => (component as DistanceJointEditorComponent).stiffness,
          write: (component, value) {
            (component as DistanceJointEditorComponent).stiffness = (value as num).toDouble();
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
          read: (component) => (component as DistanceJointEditorComponent).targetEntityName,
          write: (component, value) {
            (component as DistanceJointEditorComponent).targetEntityName = value as String;
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
