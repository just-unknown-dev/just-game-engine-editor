// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'physics_sensor_rect_fc75383b',
      name: 'Physics Sensor (Rect)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Static rectangle sensor body (overlap detection only).',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => PhysicsBodyComponent(shape: RectangleShape(50, 50), isSensor: true),
      fields: <EditorComponentField>[
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
