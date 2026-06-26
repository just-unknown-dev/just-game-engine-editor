// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'text_effcff19',
      name: 'Text',
      type: 'TextComponent',
      group: 'UI',
      description: 'Renders a text label.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => TextComponent(text: ''),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'h',
          label: 'H',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as TextComponent).size.height,
          write: (component, value) {
            (component as TextComponent).size = Size((component as TextComponent).size.width, ((value as num).toDouble()));
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'textValue',
          label: 'Text',
          kind: EditorFieldKind.text,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as TextComponent).text,
          write: (component, value) {
            (component as TextComponent).text = (value as String);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'w',
          label: 'W',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as TextComponent).size.width,
          write: (component, value) {
            (component as TextComponent).size = Size(((value as num).toDouble()), (component as TextComponent).size.height);
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
