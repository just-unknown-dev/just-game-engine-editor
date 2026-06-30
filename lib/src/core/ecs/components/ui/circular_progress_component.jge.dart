// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'circular_progress_d287c579',
      name: 'Circular Progress',
      type: 'CircularProgressComponent',
      group: 'UI',
      description: 'Radial progress indicator.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => CircularProgressComponent(radius: 30),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'progressValue',
          label: 'Progress',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.02, fractionDigits: 2, min: 0.0, max: 1.0),
          read: (component) => (component as CircularProgressComponent).progress,
          write: (component, value) {
            (component as CircularProgressComponent).setProgress(((value as num).toDouble()));
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
          read: (component) => (component as CircularProgressComponent).size.width / 2,
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
