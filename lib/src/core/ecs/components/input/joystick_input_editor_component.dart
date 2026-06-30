import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kJoystickInputEditorComponent =
    EditorComponentDescriptor(
      id: 'joystick_input_ae2e7fcb',
      name: 'Joystick Input',
      type: 'JoystickInputComponent',
      group: 'Input',
      description: 'Virtual joystick input source.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.gamepad,
      accentColor: const Color(0xFFEF5350),
      factory: () => JoystickInputComponent(),
      fields: const [],
    );
