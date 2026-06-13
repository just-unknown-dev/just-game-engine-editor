// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'physics_sensor_circle_component.dart';

final CustomComponentDescriptor _$customComponentDescriptor0 =
    CustomComponentDescriptor(
      id: 'physicssensorcircle_e9a23cf2',
      name: 'PhysicsSensorCircle',
      type: 'PhysicsSensorCircleCatalogComponent',
      group: 'Physics',
      description: 'Static circular sensor body (overlap detection only).',
      allowMultiple: false,
      factory: () => PhysicsSensorCircleCatalogComponent(),
      fields: <EditorComponentField>[],
    );

final List<CustomComponentDescriptor> _generatedCustomComponentDescriptors =
    <CustomComponentDescriptor>[_$customComponentDescriptor0];

void registerGeneratedCustomComponents([CustomComponentRegistry? registry]) {
  final target = registry ?? CustomComponentRegistry.instance;
  target.registerAll(_generatedCustomComponentDescriptors);
}
