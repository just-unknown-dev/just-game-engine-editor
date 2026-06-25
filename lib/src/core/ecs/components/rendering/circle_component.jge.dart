// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'circle_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'circle_1d72ae60',
      name: 'Circle',
      type: 'CircleEditorComponent',
      group: 'Rendering',
      description: 'Filled or stroked circle.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => CircleEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'fillColor',
          label: 'Fill',
          kind: EditorFieldKind.color,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as CircleEditorComponent).fillColor,
          write: (component, value) {
            (component as CircleEditorComponent).fillColor = value as Color;
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
          read: (component) => (component as CircleEditorComponent).filled,
          write: (component, value) {
            (component as CircleEditorComponent).filled = value as bool;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'radius',
          label: 'Radius',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
          read: (component) => (component as CircleEditorComponent).radius,
          write: (component, value) {
            (component as CircleEditorComponent).radius = (value as num).toDouble();
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
          read: (component) => (component as CircleEditorComponent).strokeColor,
          write: (component, value) {
            (component as CircleEditorComponent).strokeColor = value as Color;
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
          read: (component) => (component as CircleEditorComponent).strokeWidth,
          write: (component, value) {
            (component as CircleEditorComponent).strokeWidth = (value as num).toDouble();
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
