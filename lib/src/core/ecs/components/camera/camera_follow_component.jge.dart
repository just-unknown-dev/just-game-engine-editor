// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'camera_follow_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'camera_follow_168e2c1e',
      name: 'Camera Follow',
      type: 'CameraFollowEditorComponent',
      group: 'Camera',
      description: 'Locks the camera onto this entity.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => CameraFollowEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'enabled',
          label: 'Enabled',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as CameraFollowEditorComponent).enabled,
          write: (component, value) {
            (component as CameraFollowEditorComponent).enabled = value as bool;
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'lookahead',
          label: 'Lookahead',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as CameraFollowEditorComponent).lookahead,
          write: (component, value) {
            (component as CameraFollowEditorComponent).lookahead = (value as num).toDouble();
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
