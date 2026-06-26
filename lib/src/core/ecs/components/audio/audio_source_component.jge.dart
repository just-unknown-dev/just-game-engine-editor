// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'audio_source_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'audio_source_111e2e48',
      name: 'Audio Source',
      type: 'AudioSourceComponent',
      group: 'Audio',
      description: 'One-shot audio clip playback.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => AudioSourceComponent(clipPath: ''),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'loop',
          label: 'Loop',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as AudioSourceComponent).loop,
          write: (component, value) {
            (component as AudioSourceComponent).loop = (value as bool);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'path',
          label: 'Path',
          kind: EditorFieldKind.text,
          visible: true,
          editable: false,
          includeInJson: true,
          read: (component) => (component as AudioSourceComponent).clipPath,
          write: null,
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'pitch',
          label: 'Pitch',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0.0),
          read: (component) => (component as AudioSourceComponent).pitch,
          write: (component, value) {
            (component as AudioSourceComponent).pitch = ((value as num).toDouble());
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'playOnAdd',
          label: 'Play on Add',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as AudioSourceComponent).playOnAdd,
          write: (component, value) {
            (component as AudioSourceComponent).playOnAdd = (value as bool);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'volume',
          label: 'Volume',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0.0, max: 1.0),
          read: (component) => (component as AudioSourceComponent).volume,
          write: (component, value) {
            (component as AudioSourceComponent).volume = ((value as num).toDouble()).clamp(0.0, 1.0);
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
