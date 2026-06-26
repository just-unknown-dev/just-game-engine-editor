// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'transform_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'transform_5b740729',
      name: 'Transform',
      type: 'TransformComponent',
      group: 'Core',
      description: 'Position, rotation, and scale.',
      allowMultiple: false,
      deletable: false,
      componentType: ComponentType.core,
      factory: () => TransformComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'posX',
          label: 'X',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
          read: (component) => (component as TransformComponent).position.x,
          write: (component, value) {
            (component as TransformComponent).position = Vector3(((value as num).toDouble()), (component as TransformComponent).position.y, (component as TransformComponent).position.z);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'posY',
          label: 'Y',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
          read: (component) => (component as TransformComponent).position.y,
          write: (component, value) {
            (component as TransformComponent).position = Vector3((component as TransformComponent).position.x, ((value as num).toDouble()), (component as TransformComponent).position.z);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'rotation',
          label: 'Rotation°',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
          read: (component) => (component as TransformComponent).rotation * 180 / 3.14159265,
          write: (component, value) {
            (component as TransformComponent).rotation = ((value as num).toDouble()) * 3.14159265 / 180;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'scaleX',
          label: 'SX',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 3),
          read: (component) => (component as TransformComponent).scale.x,
          write: (component, value) {
            (component as TransformComponent).scale = Vector3(((value as num).toDouble()), (component as TransformComponent).scale.y, (component as TransformComponent).scale.z);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'scaleY',
          label: 'SY',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 3),
          read: (component) => (component as TransformComponent).scale.y,
          write: (component, value) {
            (component as TransformComponent).scale = Vector3((component as TransformComponent).scale.x, ((value as num).toDouble()), (component as TransformComponent).scale.z);
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
