// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'velocity_88533db4',
      name: 'Velocity',
      type: 'VelocityComponent',
      group: 'Core',
      description: 'Linear velocity with an optional max-speed cap.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => VelocityComponent(maxSpeed: 500),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'maxSpeed',
          label: 'Max Speed',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as VelocityComponent).maxSpeed,
          write: (component, value) {
            (component as VelocityComponent).maxSpeed = ((value as num).toDouble());
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
          read: (component) => (component as VelocityComponent).velocity.x,
          write: (component, value) {
            (component as VelocityComponent).setVelocityXY(((value as num).toDouble()), (component as VelocityComponent).velocity.y);
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
          read: (component) => (component as VelocityComponent).velocity.y,
          write: (component, value) {
            (component as VelocityComponent).setVelocityXY((component as VelocityComponent).velocity.x, ((value as num).toDouble()));
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
