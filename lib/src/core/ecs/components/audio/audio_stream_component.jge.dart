// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'audio_stream_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'audio_stream_91f6500b',
      name: 'Audio Stream',
      type: 'AudioStreamEditorComponent',
      group: 'Audio',
      description: 'Streaming audio playback.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => AudioStreamEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'loop',
          label: 'Loop',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as AudioStreamEditorComponent).loop,
          write: (component, value) {
            (component as AudioStreamEditorComponent).loop = value as bool;
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
          read: (component) => (component as AudioStreamEditorComponent).playOnAdd,
          write: (component, value) {
            (component as AudioStreamEditorComponent).playOnAdd = value as bool;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'streamPath',
          label: 'Path',
          kind: EditorFieldKind.text,
          visible: true,
          editable: false,
          includeInJson: true,
          read: (component) => (component as AudioStreamEditorComponent).streamPath,
          write: null,
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
          read: (component) => (component as AudioStreamEditorComponent).volume,
          write: (component, value) {
            (component as AudioStreamEditorComponent).volume = (value as num).toDouble();
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
