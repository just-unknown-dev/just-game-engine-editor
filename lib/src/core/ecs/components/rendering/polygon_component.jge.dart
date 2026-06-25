// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'polygon_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'polygon_671a97e0',
      name: 'Polygon',
      type: 'PolygonEditorComponent',
      group: 'Rendering',
      description: 'Filled or stroked polygon.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => PolygonEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'fillColor',
          label: 'Fill',
          kind: EditorFieldKind.color,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as PolygonEditorComponent).fillColor,
          write: (component, value) {
            (component as PolygonEditorComponent).fillColor = value as Color;
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
          read: (component) => (component as PolygonEditorComponent).filled,
          write: (component, value) {
            (component as PolygonEditorComponent).filled = value as bool;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'strokeColor',
          label: 'Stroke Color',
          kind: EditorFieldKind.color,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as PolygonEditorComponent).strokeColor,
          write: (component, value) {
            (component as PolygonEditorComponent).strokeColor = value as Color;
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
          read: (component) => (component as PolygonEditorComponent).strokeWidth,
          write: (component, value) {
            (component as PolygonEditorComponent).strokeWidth = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'vertCount',
          label: 'Verts',
          kind: EditorFieldKind.integer,
          visible: true,
          editable: false,
          includeInJson: true,
          read: (component) => (component as PolygonEditorComponent).vertCount,
          write: null,
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
