// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'velocity_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'velocity_88533db4',
      name: 'Velocity',
      type: 'VelocityEditorComponent',
      group: 'Core',
      description: 'Linear velocity with an optional max-speed cap.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => VelocityEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'maxSpeed',
          label: 'Max Speed',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as VelocityEditorComponent).maxSpeed,
          write: (component, value) {
            (component as VelocityEditorComponent).maxSpeed = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'velocityX',
          label: 'VX',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
          read: (component) => (component as VelocityEditorComponent).velocityX,
          write: (component, value) {
            (component as VelocityEditorComponent).velocityX = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'velocityY',
          label: 'VY',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
          read: (component) => (component as VelocityEditorComponent).velocityY,
          write: (component, value) {
            (component as VelocityEditorComponent).velocityY = (value as num).toDouble();
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
