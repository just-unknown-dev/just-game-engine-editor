// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'polygon_671a97e0',
      name: 'Polygon',
      type: 'PolygonComponent',
      group: 'Rendering',
      description: 'Filled or stroked polygon.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => PolygonComponent(vertices: const [Offset(-32, -32), Offset(32, -32), Offset(0, 32)]),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'fillColor',
          label: 'Fill',
          kind: EditorFieldKind.color,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as PolygonComponent).fillStyle.color,
          write: (component, value) {
            (component as PolygonComponent).fillStyle = ShapePaintStyle(color: (value as Color));
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
          read: (component) => (component as PolygonComponent).filled,
          write: (component, value) {
            (component as PolygonComponent).filled = (value as bool);
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
          read: (component) => (component as PolygonComponent).strokeStyle.color,
          write: (component, value) {
            (component as PolygonComponent).strokeStyle = ShapePaintStyle(color: (value as Color));
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'strokeW',
          label: 'Stroke',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
          read: (component) => (component as PolygonComponent).strokeWidth,
          write: (component, value) {
            (component as PolygonComponent).strokeWidth = ((value as num).toDouble());
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
          read: (component) => (component as PolygonComponent).vertices.length,
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

// Registers all descriptors on first import of this file.
// ignore: unused_element
final bool _$registered = () {
  CustomComponentRegistry.instance.registerAll(
    _generatedEditorComponentDescriptors,
  );
  return true;
}();

// Legacy named function kept for backward compatibility.
void registerGeneratedCustomComponents([CustomComponentRegistry? registry]) {
  final target = registry ?? CustomComponentRegistry.instance;
  target.registerAll(_generatedEditorComponentDescriptors);
}
