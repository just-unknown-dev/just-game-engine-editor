import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class CameraFollowEditorComponent extends EditorComponent {
  CameraFollowEditorComponent()
    : super(
      id: 'camera_follow_168e2c1e',
      name: 'Camera Follow',
      type: 'CameraFollowComponent',
      group: 'Camera',
      description: 'Locks the camera onto this entity.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.videocam,
      accentColor: const Color(0xFF26C6DA),
      factory: () => CameraFollowComponent(),
      fields: [
        EditorComponentField(
          name: 'enabled',
          label: 'Enabled',
          kind: EditorFieldKind.boolean,
          read: (c) => (c as CameraFollowComponent).enabled,
          write: (c, v) => (c as CameraFollowComponent).enabled = v as bool,
        ),
        EditorComponentField(
          name: 'lookahead',
          label: 'Lookahead',
          kind: EditorFieldKind.decimal,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (c) => (c as CameraFollowComponent).lookaheadDistance,
          write: (c, v) =>
              (c as CameraFollowComponent).lookaheadDistance = (v as num).toDouble(),
        ),
      ],
      );
}
