// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'physics_body_chain_02eccc81',
      name: 'Physics Body (Chain)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Static chain collider for terrain-like collision paths.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => PhysicsBodyComponent(shape: ChainShape(const [Offset(-50, 0), Offset(0, -30), Offset(50, 0)]), isStatic: true),
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
