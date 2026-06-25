// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'animation_state_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'animation_state_40e001f0',
      name: 'Animation State',
      type: 'AnimationStateEditorComponent',
      group: 'Animation',
      description: 'Drives sprite sheet animation.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => AnimationStateEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'animName',
          label: 'Name',
          kind: EditorFieldKind.text,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as AnimationStateEditorComponent).animName,
          write: (component, value) {
            (component as AnimationStateEditorComponent).animName = value as String;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'frameCount',
          label: 'Frames',
          kind: EditorFieldKind.integer,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, min: 1.0, integer: true),
          read: (component) => (component as AnimationStateEditorComponent).frameCount,
          write: (component, value) {
            (component as AnimationStateEditorComponent).frameCount = (value as num).toInt();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'frameDuration',
          label: 'Dur(s)',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.01, fractionDigits: 3, min: 0.0),
          read: (component) => (component as AnimationStateEditorComponent).frameDuration,
          write: (component, value) {
            (component as AnimationStateEditorComponent).frameDuration = (value as num).toDouble();
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'loop',
          label: 'Loop',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as AnimationStateEditorComponent).loop,
          write: (component, value) {
            (component as AnimationStateEditorComponent).loop = value as bool;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'playing',
          label: 'Playing',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as AnimationStateEditorComponent).playing,
          write: (component, value) {
            (component as AnimationStateEditorComponent).playing = value as bool;
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
