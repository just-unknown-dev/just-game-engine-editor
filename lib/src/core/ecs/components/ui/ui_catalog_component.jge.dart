// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'ui_6018ae16',
      name: 'UI',
      type: 'UIComponent',
      group: 'UI',
      description: 'Base UI layout container.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => UIComponent(size: const Size(100, 40)),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'enabled',
          label: 'Enabled',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as UIComponent).enabled,
          write: (component, value) {
            (component as UIComponent).enabled = (value as bool);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'h',
          label: 'H',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as UIComponent).size.height,
          write: (component, value) {
            (component as UIComponent).size = Size((component as UIComponent).size.width, ((value as num).toDouble()));
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'visible',
          label: 'Visible',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as UIComponent).visible,
          write: (component, value) {
            (component as UIComponent).visible = (value as bool);
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
          read: (component) => (component as UIComponent).size.width,
          write: (component, value) {
            (component as UIComponent).size = Size(((value as num).toDouble()), (component as UIComponent).size.height);
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
