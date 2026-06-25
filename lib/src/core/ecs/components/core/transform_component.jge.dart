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
      type: 'TransformEditorComponent',
      group: 'Core',
      description: 'Position, rotation, and scale.',
      allowMultiple: false,
      deletable: false,
      componentType: ComponentType.core,
      factory: () => TransformEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'posX',
          label: 'X',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
          read: (component) => (component as TransformEditorComponent).posX,
          write: (component, value) {
            (component as TransformEditorComponent).posX = (value as num).toDouble();
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
          read: (component) => (component as TransformEditorComponent).posY,
          write: (component, value) {
            (component as TransformEditorComponent).posY = (value as num).toDouble();
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
          read: (component) => (component as TransformEditorComponent).rotation,
          write: (component, value) {
            (component as TransformEditorComponent).rotation = (value as num).toDouble();
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
          read: (component) => (component as TransformEditorComponent).scaleX,
          write: (component, value) {
            (component as TransformEditorComponent).scaleX = (value as num).toDouble();
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
          read: (component) => (component as TransformEditorComponent).scaleY,
          write: (component, value) {
            (component as TransformEditorComponent).scaleY = (value as num).toDouble();
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
