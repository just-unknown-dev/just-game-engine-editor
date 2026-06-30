import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kInputEditorComponent =
    EditorComponentDescriptor(
      id: 'input_e2d1c96e',
      name: 'Input',
      type: 'InputComponent',
      group: 'Input',
      description: 'Enables keyboard/mouse input on this entity.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.keyboard,
      accentColor: const Color(0xFFEF5350),
      factory: () => InputComponent(),
      fields: const [],
    );
