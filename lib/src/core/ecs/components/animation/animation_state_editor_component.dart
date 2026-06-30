import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class AnimationStateEditorComponent extends EditorComponent {
  AnimationStateEditorComponent()
    : super(
        id: 'animation_state_40e001f0',
        name: 'Animation State',
        type: 'AnimationStateComponent',
        group: 'Animation',
        description: 'Drives sprite sheet animation.',
        allowMultiple: false,
        deletable: true,
        componentType: ComponentType.core,
        icon: Icons.animation,
        accentColor: const Color(0xFFFFCA28),
        factory: () => AnimationStateComponent(
          currentAnimation: 'idle',
          frameCount: 4,
          frameDuration: 0.1,
        ),
        fields: const [],
        fieldGroups: [
          EditorFieldGroup(
            name: 'Animation',
            fields: [
              EditorComponentField(
                name: 'animName',
                label: 'Name',
                kind: EditorFieldKind.text,
                read: (c) => (c as AnimationStateComponent).currentAnimation,
                write: (c, v) =>
                    (c as AnimationStateComponent).currentAnimation =
                        v as String,
              ),
              EditorComponentField(
                name: 'frameCount',
                label: 'Frames',
                kind: EditorFieldKind.integer,
                scrubConfig: const NumberScrubConfig(
                  step: 1.0,
                  min: 1.0,
                  integer: true,
                ),
                read: (c) => (c as AnimationStateComponent).frameCount,
                write: (c, v) => (c as AnimationStateComponent).frameCount =
                    (v as num).toInt(),
              ),
              EditorComponentField(
                name: 'frameDuration',
                label: 'Dur(s)',
                kind: EditorFieldKind.decimal,
                scrubConfig: const NumberScrubConfig(
                  step: 0.01,
                  fractionDigits: 3,
                  min: 0.0,
                ),
                read: (c) => (c as AnimationStateComponent).frameDuration,
                write: (c, v) => (c as AnimationStateComponent).frameDuration =
                    (v as num).toDouble(),
              ),
            ],
          ),
          EditorFieldGroup(
            name: 'State',
            fields: [
              EditorComponentField(
                name: 'loop',
                label: 'Loop',
                kind: EditorFieldKind.boolean,
                read: (c) => (c as AnimationStateComponent).loop,
                write: (c, v) =>
                    (c as AnimationStateComponent).loop = v as bool,
              ),
              EditorComponentField(
                name: 'playing',
                label: 'Playing',
                kind: EditorFieldKind.boolean,
                read: (c) => (c as AnimationStateComponent).isPlaying,
                write: (c, v) =>
                    (c as AnimationStateComponent).isPlaying = v as bool,
              ),
            ],
          ),
        ],
      );
}
