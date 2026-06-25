// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'rectangle_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'rectangle_c9214e61',
      name: 'Rectangle',
      type: 'RectangleEditorComponent',
      group: 'Rendering',
      description: 'Filled or stroked rectangle.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => RectangleEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'cornerRadius',
          label: 'CR',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
          read: (component) => (component as RectangleEditorComponent).cornerRadius,
          write: (component, value) {
            (component as RectangleEditorComponent).cornerRadius = (value as num).toDouble();
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
          read: (component) => (component as RectangleEditorComponent).fillColor,
          write: (component, value) {
            (component as RectangleEditorComponent).fillColor = value as Color;
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
          read: (component) => (component as RectangleEditorComponent).filled,
          write: (component, value) {
            (component as RectangleEditorComponent).filled = value as bool;
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
          read: (component) => (component as RectangleEditorComponent).height,
          write: (component, value) {
            (component as RectangleEditorComponent).height = (value as num).toDouble();
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
          read: (component) => (component as RectangleEditorComponent).strokeColor,
          write: (component, value) {
            (component as RectangleEditorComponent).strokeColor = value as Color;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'strokeWidth',
          label: 'SW',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
          read: (component) => (component as RectangleEditorComponent).strokeWidth,
          write: (component, value) {
            (component as RectangleEditorComponent).strokeWidth = (value as num).toDouble();
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
          read: (component) => (component as RectangleEditorComponent).width,
          write: (component, value) {
            (component as RectangleEditorComponent).width = (value as num).toDouble();
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
