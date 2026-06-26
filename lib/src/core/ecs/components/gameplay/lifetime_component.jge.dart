// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'lifetime_0ec055c7',
      name: 'Lifetime',
      type: 'LifetimeComponent',
      group: 'Gameplay',
      description: 'Destroys the entity after a fixed duration.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => LifetimeComponent(1.0),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'duration',
          label: 'Duration (s)',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: false,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.1, fractionDigits: 2, min: 0.0),
          read: (component) => (component as LifetimeComponent).initialLifetime,
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
