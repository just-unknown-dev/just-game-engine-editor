// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'animation_state_40e001f0',
      name: 'Animation State',
      type: 'AnimationStateComponent',
      group: 'Animation',
      description: 'Drives sprite sheet animation.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => AnimationStateComponent(currentAnimation: 'idle'),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'animName',
          label: 'Name',
          kind: EditorFieldKind.text,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as AnimationStateComponent).currentAnimation,
          write: (component, value) {
            (component as AnimationStateComponent).currentAnimation = value as String;
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
          read: (component) => (component as AnimationStateComponent).frameCount,
          write: (component, value) {
            (component as AnimationStateComponent).frameCount = (value as num).toInt();
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
          read: (component) => (component as AnimationStateComponent).frameDuration,
          write: (component, value) {
            (component as AnimationStateComponent).frameDuration = (value as num).toDouble();
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
          read: (component) => (component as AnimationStateComponent).loop,
          write: (component, value) {
            (component as AnimationStateComponent).loop = (value as bool);
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
          read: (component) => (component as AnimationStateComponent).isPlaying,
          write: (component, value) {
            (component as AnimationStateComponent).isPlaying = (value as bool);
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
