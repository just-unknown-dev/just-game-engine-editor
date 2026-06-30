// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'physics_body_segment_03c88561',
      name: 'Physics Body (Segment)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Static line segment collider, useful for ramps/platforms.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => PhysicsBodyComponent(shape: SegmentShape(const Offset(-50, 0), const Offset(50, 0)), isStatic: true),
      fields: <EditorComponentField>[
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
