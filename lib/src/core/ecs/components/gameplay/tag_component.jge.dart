// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'tag_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'tag_8a41b7f8',
      name: 'Tag',
      type: 'TagEditorComponent',
      group: 'Gameplay',
      description: 'String tag for filtering entities.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => TagEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'tagValue',
          label: 'Tag',
          kind: EditorFieldKind.text,
          visible: true,
          editable: false,
          includeInJson: true,
          read: (component) => (component as TagEditorComponent).tagValue,
          write: null,
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
