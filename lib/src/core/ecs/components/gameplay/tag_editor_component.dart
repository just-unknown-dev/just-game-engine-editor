import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kTagEditorComponent =
    EditorComponentDescriptor(
      id: 'tag_8a41b7f8',
      name: 'Tag',
      type: 'TagComponent',
      group: 'Gameplay',
      description: 'String tag for filtering entities.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.label,
      accentColor: const Color(0xFF66BB6A),
      factory: () => TagComponent('entity'),
      fields: [
        EditorComponentField(
          name: 'tagValue',
          label: 'Tag',
          kind: EditorFieldKind.text,
          editable: false,
          read: (c) => (c as TagComponent).tag,
        ),
      ],
    );
