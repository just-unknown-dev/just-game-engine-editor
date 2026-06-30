// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'line_5a69b8e2',
      name: 'Line',
      type: 'LineComponent',
      group: 'Rendering',
      description: 'A stroked line between two points.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => LineComponent(end: const Offset(100, 0)),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'endX',
          label: 'End X',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
          read: (component) => (component as LineComponent).end.dx,
          write: (component, value) {
            (component as LineComponent).end = Offset(((value as num).toDouble()), (component as LineComponent).end.dy);
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
          read: (component) => (component as LineComponent).end.dy,
          write: (component, value) {
            (component as LineComponent).end = Offset((component as LineComponent).end.dx, ((value as num).toDouble()));
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
          read: (component) => (component as LineComponent).roundCaps,
          write: (component, value) {
            (component as LineComponent).roundCaps = (value as bool);
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
          read: (component) => (component as LineComponent).start.dx,
          write: (component, value) {
            (component as LineComponent).start = Offset(((value as num).toDouble()), (component as LineComponent).start.dy);
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
          read: (component) => (component as LineComponent).start.dy,
          write: (component, value) {
            (component as LineComponent).start = Offset((component as LineComponent).start.dx, ((value as num).toDouble()));
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
          read: (component) => (component as LineComponent).strokeStyle.color,
          write: (component, value) {
            (component as LineComponent).strokeStyle = ShapePaintStyle(color: (value as Color));
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
          read: (component) => (component as LineComponent).strokeWidth,
          write: (component, value) {
            (component as LineComponent).strokeWidth = ((value as num).toDouble());
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
