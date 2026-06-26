// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'capsule_2de9600b',
      name: 'Capsule',
      type: 'CapsuleComponent',
      group: 'Rendering',
      description: 'Filled or stroked capsule.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => CapsuleComponent(width: 32, height: 64),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'fillColor',
          label: 'Fill',
          kind: EditorFieldKind.color,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as CapsuleComponent).fillStyle.color,
          write: (component, value) {
            (component as CapsuleComponent).fillStyle = ShapePaintStyle(color: (value as Color));
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
          read: (component) => (component as CapsuleComponent).filled,
          write: (component, value) {
            (component as CapsuleComponent).filled = (value as bool);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'h',
          label: 'H',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as CapsuleComponent).height,
          write: (component, value) {
            (component as CapsuleComponent).height = ((value as num).toDouble());
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
          read: (component) => (component as CapsuleComponent).strokeStyle.color,
          write: (component, value) {
            (component as CapsuleComponent).strokeStyle = ShapePaintStyle(color: (value as Color));
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'w',
          label: 'W',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as CapsuleComponent).width,
          write: (component, value) {
            (component as CapsuleComponent).width = ((value as num).toDouble());
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
