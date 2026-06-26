// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'rectangle_c9214e61',
      name: 'Rectangle',
      type: 'RectangleComponent',
      group: 'Rendering',
      description: 'Filled or stroked rectangle.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => RectangleComponent(width: 64, height: 64),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'cr',
          label: 'CR',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
          read: (component) => (component as RectangleComponent).cornerRadius,
          write: (component, value) {
            (component as RectangleComponent).cornerRadius = ((value as num).toDouble());
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'fillColor',
          label: 'Fill',
          kind: EditorFieldKind.color,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as RectangleComponent).fillStyle.color,
          write: (component, value) {
            (component as RectangleComponent).fillStyle = ShapePaintStyle(color: (value as Color));
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
          read: (component) => (component as RectangleComponent).filled,
          write: (component, value) {
            (component as RectangleComponent).filled = (value as bool);
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
          read: (component) => (component as RectangleComponent).height,
          write: (component, value) {
            (component as RectangleComponent).height = ((value as num).toDouble());
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
          read: (component) => (component as RectangleComponent).strokeStyle.color,
          write: (component, value) {
            (component as RectangleComponent).strokeStyle = ShapePaintStyle(color: (value as Color));
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'sw',
          label: 'SW',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
          read: (component) => (component as RectangleComponent).strokeWidth,
          write: (component, value) {
            (component as RectangleComponent).strokeWidth = ((value as num).toDouble());
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
          read: (component) => (component as RectangleComponent).width,
          write: (component, value) {
            (component as RectangleComponent).width = ((value as num).toDouble());
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
