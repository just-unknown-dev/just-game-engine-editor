// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'physics_body_polygon_804a6518',
      name: 'Physics Body (Polygon)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Dynamic rigid body with a convex polygon collision shape.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => PhysicsBodyComponent(shape: PolygonShape(const [Offset(-25, -25), Offset(25, -25), Offset(0, 25)])),
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
