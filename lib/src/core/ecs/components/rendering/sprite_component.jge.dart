// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'sprite_1cc5c09b',
      name: 'Sprite',
      type: 'SpriteComponent',
      group: 'Rendering',
      description: 'Sprite sheet renderer.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => SpriteComponent(spritePath: ''),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'flipX',
          label: 'Flip X',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as SpriteComponent).flipX,
          write: (component, value) {
            (component as SpriteComponent).flipX = (value as bool);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'flipY',
          label: 'Flip Y',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as SpriteComponent).flipY,
          write: (component, value) {
            (component as SpriteComponent).flipY = (value as bool);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'frame',
          label: 'Frame',
          kind: EditorFieldKind.integer,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, min: 0.0, integer: true),
          read: (component) => (component as SpriteComponent).frame,
          write: (component, value) {
            (component as SpriteComponent).frame = ((value as num).toInt());
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'path',
          label: 'Path',
          kind: EditorFieldKind.text,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as SpriteComponent).spritePath,
          write: (component, value) {
            (component as SpriteComponent).spritePath = (value as String);
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
