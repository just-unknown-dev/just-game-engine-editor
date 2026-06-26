// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'weld_joint_component_editor.dart';
import 'weld_joint_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'weld_joint_8369677a',
      name: 'Weld Joint',
      type: 'WeldJointComponent',
      group: 'Physics',
      description: 'Rigid weld joint linking this entity to targetEntityName.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.editor,
      factory: () => WeldJointEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'collideConnected',
          label: 'Collide Connected',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as WeldJointComponent).collideConnected,
          write: (component, value) {
            (component as WeldJointComponent).collideConnected = (value as bool);
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
          read: (component) => (component as WeldJointComponent).targetEntityName,
          write: (component, value) {
            (component as WeldJointComponent).targetEntityName = (value as String).trim();
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
