// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'capsule_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'capsule_2de9600b',
      name: 'Capsule',
      type: 'CapsuleEditorComponent',
      group: 'Rendering',
      description: 'Filled or stroked capsule.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => CapsuleEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'fillColor',
          label: 'Fill',
          kind: EditorFieldKind.color,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as CapsuleEditorComponent).fillColor,
          write: (component, value) {
            (component as CapsuleEditorComponent).fillColor = value as Color;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'filled',
          label: 'Filled',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as CapsuleEditorComponent).filled,
          write: (component, value) {
            (component as CapsuleEditorComponent).filled = value as bool;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'height',
          label: 'H',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as CapsuleEditorComponent).height,
          write: (component, value) {
            (component as CapsuleEditorComponent).height = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'strokeColor',
          label: 'Stroke',
          kind: EditorFieldKind.color,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as CapsuleEditorComponent).strokeColor,
          write: (component, value) {
            (component as CapsuleEditorComponent).strokeColor = value as Color;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'width',
          label: 'W',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as CapsuleEditorComponent).width,
          write: (component, value) {
            (component as CapsuleEditorComponent).width = (value as num).toDouble();
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
