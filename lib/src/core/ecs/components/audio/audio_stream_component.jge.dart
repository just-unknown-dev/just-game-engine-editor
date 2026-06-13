// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'audio_stream_component.dart';

final CustomComponentDescriptor _$customComponentDescriptor0 =
    CustomComponentDescriptor(
      id: 'audiostreamcomponent_91f6500b',
      name: 'AudioStreamComponent',
      type: 'AudioStreamCatalogComponent',
      group: 'Audio',
      description: 'Streaming music track. Set path in inspector.',
      allowMultiple: false,
      factory: () => AudioStreamCatalogComponent(),
      fields: <EditorComponentField>[],
    );

final List<CustomComponentDescriptor> _generatedCustomComponentDescriptors =
    <CustomComponentDescriptor>[_$customComponentDescriptor0];

void registerGeneratedCustomComponents([CustomComponentRegistry? registry]) {
  final target = registry ?? CustomComponentRegistry.instance;
  target.registerAll(_generatedCustomComponentDescriptors);
}
