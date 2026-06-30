import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class PhysicsBodyCircleEditorComponent extends EditorComponent {
  PhysicsBodyCircleEditorComponent()
    : super(
      id: 'physics_body_circle_526076f8',
      name: 'Physics Body (Circle)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Dynamic rigid body with a circular collision shape.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.radio_button_unchecked,
      accentColor: const Color(0xFFFF7043),
      factory: () => PhysicsBodyComponent(
        shape: CircleShape(24),
        mass: 1.0,
        isStatic: false,
        restitution: 0.6,
        drag: 0.98,
      ),
      fields: const [],
      );
}
