// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'circular_progress_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'circular_progress_d287c579',
      name: 'Circular Progress',
      type: 'CircularProgressEditorComponent',
      group: 'UI',
      description: 'Radial progress indicator.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => CircularProgressEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'progressValue',
          label: 'Progress',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.02, fractionDigits: 2, min: 0.0, max: 1.0),
          read: (component) => (component as CircularProgressEditorComponent).progressValue,
          write: (component, value) {
            (component as CircularProgressEditorComponent).progressValue = (value as num).toDouble();
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
          read: (component) => (component as CircularProgressEditorComponent).radius,
          write: (component, value) {
            (component as CircularProgressEditorComponent).radius = (value as num).toDouble();
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
