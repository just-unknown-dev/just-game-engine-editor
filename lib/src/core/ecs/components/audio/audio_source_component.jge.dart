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
      type: 'AudioSourceEditorComponent',
      group: 'Audio',
      description: 'One-shot audio clip playback.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => AudioSourceEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'loop',
          label: 'Loop',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as AudioSourceEditorComponent).loop,
          write: (component, value) {
            (component as AudioSourceEditorComponent).loop = value as bool;
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
          read: (component) => (component as AudioSourceEditorComponent).path,
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
          read: (component) => (component as AudioSourceEditorComponent).pitch,
          write: (component, value) {
            (component as AudioSourceEditorComponent).pitch = (value as num).toDouble();
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
          read: (component) => (component as AudioSourceEditorComponent).playOnAdd,
          write: (component, value) {
            (component as AudioSourceEditorComponent).playOnAdd = value as bool;
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
          read: (component) => (component as AudioSourceEditorComponent).volume,
          write: (component, value) {
            (component as AudioSourceEditorComponent).volume = (value as num).toDouble();
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
