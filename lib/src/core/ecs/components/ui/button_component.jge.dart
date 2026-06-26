// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'button_388d5c40',
      name: 'Button',
      type: 'ButtonComponent',
      group: 'UI',
      description: 'Interactive button widget.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => ButtonComponent(text: 'Button', size: const Size(120, 40)),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'h',
          label: 'H',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as ButtonComponent).size.height,
          write: (component, value) {
            (component as ButtonComponent).size = Size((component as ButtonComponent).size.width, ((value as num).toDouble()));
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'label',
          label: 'Label',
          kind: EditorFieldKind.text,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as ButtonComponent).text,
          write: (component, value) {
            (component as ButtonComponent).text = (value as String);
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
          read: (component) => (component as ButtonComponent).size.width,
          write: (component, value) {
            (component as ButtonComponent).size = Size(((value as num).toDouble()), (component as ButtonComponent).size.height);
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
