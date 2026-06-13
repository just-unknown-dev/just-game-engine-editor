// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'physics_body_segment_component.dart';

final CustomComponentDescriptor _$customComponentDescriptor0 =
    CustomComponentDescriptor(
      id: 'physicsbodysegment_03c88561',
      name: 'PhysicsBodySegment',
      type: 'PhysicsBodySegmentCatalogComponent',
      group: 'Physics',
      description: 'Static line segment collider, useful for ramps/platforms.',
      allowMultiple: false,
      factory: () => PhysicsBodySegmentCatalogComponent(),
      fields: <EditorComponentField>[],
    );

final List<CustomComponentDescriptor> _generatedCustomComponentDescriptors =
    <CustomComponentDescriptor>[_$customComponentDescriptor0];

void registerGeneratedCustomComponents([CustomComponentRegistry? registry]) {
  final target = registry ?? CustomComponentRegistry.instance;
  target.registerAll(_generatedCustomComponentDescriptors);
}
