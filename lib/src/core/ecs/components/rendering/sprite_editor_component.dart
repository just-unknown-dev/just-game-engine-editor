import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kSpriteEditorComponent =
    EditorComponentDescriptor(
      id: 'sprite_1cc5c09b',
      name: 'Sprite',
      type: 'SpriteComponent',
      group: 'Rendering',
      description: 'Sprite sheet renderer.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.image,
      accentColor: const Color(0xFF42A5F5),
      factory: () => SpriteComponent(spritePath: ''),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Sprite', fields: [
          EditorComponentField(
            name: 'path',
            label: 'Path',
            kind: EditorFieldKind.text,
            read: (c) => (c as SpriteComponent).spritePath,
            write: (c, v) =>
                (c as SpriteComponent).spritePath = v as String,
          ),
          EditorComponentField(
            name: 'frame',
            label: 'Frame',
            kind: EditorFieldKind.integer,
            scrubConfig: const NumberScrubConfig(step: 1.0, min: 0.0, integer: true),
            read: (c) => (c as SpriteComponent).frame,
            write: (c, v) =>
                (c as SpriteComponent).frame = (v as num).toInt(),
          ),
        ]),
        EditorFieldGroup(name: 'Options', fields: [
          EditorComponentField(
            name: 'flipX',
            label: 'Flip X',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as SpriteComponent).flipX,
            write: (c, v) => (c as SpriteComponent).flipX = v as bool,
          ),
          EditorComponentField(
            name: 'flipY',
            label: 'Flip Y',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as SpriteComponent).flipY,
            write: (c, v) => (c as SpriteComponent).flipY = v as bool,
          ),
        ]),
      ],
    );
