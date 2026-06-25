// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'line_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'line_5a69b8e2',
      name: 'Line',
      type: 'LineEditorComponent',
      group: 'Rendering',
      description: 'A stroked line between two points.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => LineEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'endX',
          label: 'End X',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
          read: (component) => (component as LineEditorComponent).endX,
          write: (component, value) {
            (component as LineEditorComponent).endX = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'endY',
          label: 'End Y',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
          read: (component) => (component as LineEditorComponent).endY,
          write: (component, value) {
            (component as LineEditorComponent).endY = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'roundCaps',
          label: 'Round',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as LineEditorComponent).roundCaps,
          write: (component, value) {
            (component as LineEditorComponent).roundCaps = value as bool;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'startX',
          label: 'Start X',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
          read: (component) => (component as LineEditorComponent).startX,
          write: (component, value) {
            (component as LineEditorComponent).startX = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'startY',
          label: 'Start Y',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
          read: (component) => (component as LineEditorComponent).startY,
          write: (component, value) {
            (component as LineEditorComponent).startY = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'strokeColor',
          label: 'Paint',
          kind: EditorFieldKind.color,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as LineEditorComponent).strokeColor,
          write: (component, value) {
            (component as LineEditorComponent).strokeColor = value as Color;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'strokeWidth',
          label: 'Stroke',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
          read: (component) => (component as LineEditorComponent).strokeWidth,
          write: (component, value) {
            (component as LineEditorComponent).strokeWidth = (value as num).toDouble();
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
