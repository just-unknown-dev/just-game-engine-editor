// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'effect_component.dart';

final CustomComponentDescriptor _$customComponentDescriptor0 =
    CustomComponentDescriptor(
      id: 'effectcomponent_79525c29',
      name: 'EffectComponent',
      type: 'EffectCatalogComponent',
      group: 'Effects',
      description: 'Marker for deterministic tween effects.',
      allowMultiple: false,
      factory: () => EffectCatalogComponent(),
      fields: <EditorComponentField>[],
    );

final List<CustomComponentDescriptor> _generatedCustomComponentDescriptors =
    <CustomComponentDescriptor>[_$customComponentDescriptor0];

void registerGeneratedCustomComponents([CustomComponentRegistry? registry]) {
  final target = registry ?? CustomComponentRegistry.instance;
  target.registerAll(_generatedCustomComponentDescriptors);
}
