import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class SpawnEditorComponent extends EditorComponent {
  SpawnEditorComponent()
    : super(
        id: 'spawn_point_a1c4e08f',
        name: 'Spawn Point',
        type: 'SpawnComponent',
        group: 'Gameplay',
        description:
            'Marks this entity as a spawn point. The editor\'s Play button '
            'looks up "tag" in the app\'s spawn registry and creates '
            'whatever that tag maps to here.',
        allowMultiple: false,
        componentType: ComponentType.core,
        icon: Icons.person_pin_circle_rounded,
        accentColor: const Color(0xFFFFB74D),
        factory: () => SpawnComponent(),
        fields: [
          EditorComponentField(
            name: 'tag',
            label: 'Tag',
            kind: EditorFieldKind.text,
            read: (c) => (c as SpawnComponent).tag,
            write: (c, v) => (c as SpawnComponent).tag = v as String,
          ),
        ],
      );
}
