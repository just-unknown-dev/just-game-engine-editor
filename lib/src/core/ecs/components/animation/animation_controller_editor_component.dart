import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class AnimationControllerEditorComponent extends EditorComponent {
  AnimationControllerEditorComponent()
    : super(
        id: 'animation_controller_8c3f2e91',
        name: 'Animation Controller',
        type: 'AnimationControllerComponent',
        group: 'Animation',
        description: 'Keyframe-based transform animation on a flat timeline.',
        allowMultiple: false,
        deletable: true,
        componentType: ComponentType.core,
        icon: Icons.timeline_rounded,
        accentColor: const Color(0xFF7DD8E0),
        factory: () => AnimationControllerComponent(),
        fields: const [],
        fieldGroups: [
          EditorFieldGroup(name: 'Playback', fields: [
            EditorComponentField(
              name: 'duration',
              label: 'Duration (s)',
              kind: EditorFieldKind.decimal,
              scrubConfig: const NumberScrubConfig(
                step: 0.1,
                min: 0.1,
                max: 600,
                fractionDigits: 2,
              ),
              read: (c) => (c as AnimationControllerComponent).duration,
              write: (c, v) =>
                  (c as AnimationControllerComponent).duration =
                      (v as num).toDouble(),
            ),
            EditorComponentField(
              name: 'loop',
              label: 'Loop',
              kind: EditorFieldKind.boolean,
              read: (c) => (c as AnimationControllerComponent).loop,
              write: (c, v) =>
                  (c as AnimationControllerComponent).loop = v as bool,
            ),
            EditorComponentField(
              name: 'playOnStart',
              label: 'Play on Start',
              kind: EditorFieldKind.boolean,
              read: (c) => (c as AnimationControllerComponent).playOnStart,
              write: (c, v) =>
                  (c as AnimationControllerComponent).playOnStart = v as bool,
            ),
          ]),
          EditorFieldGroup(name: '_internal', fields: [
            EditorComponentField(
              name: 'keyframes',
              label: 'Keyframes',
              kind: EditorFieldKind.list,
              visible: false,
              editable: false,
              includeInJson: true,
              read: (c) => (c as AnimationControllerComponent)
                  .keyframes
                  .map((k) => k.toJson())
                  .toList(),
              write: (c, v) {
                final acc = c as AnimationControllerComponent;
                acc.keyframes.clear();
                if (v is List) {
                  for (final item in v) {
                    if (item is Map) {
                      acc.keyframes.add(
                        TransformKeyframe.fromJson(
                          item.cast<String, dynamic>(),
                        ),
                      );
                    }
                  }
                }
              },
            ),
            EditorComponentField(
              name: 'events',
              label: 'Events',
              kind: EditorFieldKind.list,
              visible: false,
              editable: false,
              includeInJson: true,
              read: (c) => (c as AnimationControllerComponent)
                  .events
                  .map((e) => e.toJson())
                  .toList(),
              write: (c, v) {
                final acc = c as AnimationControllerComponent;
                acc.events.clear();
                if (v is List) {
                  for (final item in v) {
                    if (item is Map) {
                      acc.events.add(
                        AnimationEvent.fromJson(item.cast<String, dynamic>()),
                      );
                    }
                  }
                }
              },
            ),
          ]),
        ],
      );
}
