import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class EffectEditorComponent extends EditorComponent {
  EffectEditorComponent()
    : super(
      id: 'effects_79525c29',
      name: 'Effects',
      type: 'EffectComponent',
      group: 'Effects',
      description: 'Enables the effects system on this entity.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.auto_awesome,
      accentColor: const Color(0xFFFF4081),
      factory: () => EffectComponent(),
      fields: const [],
      );
}
