import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kPhysicsBodyCapsuleEditorComponent =
    EditorComponentDescriptor(
      id: 'physics_body_capsule_a8e1b7e3',
      name: 'Physics Body (Capsule)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Dynamic rigid body with a capsule collision shape.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.crop_portrait,
      accentColor: const Color(0xFFFF7043),
      factory: () => PhysicsBodyComponent(
        shape: CapsuleShape(
          center1: const Offset(0, -16),
          center2: const Offset(0, 16),
          radius: 10,
        ),
        mass: 1.2,
        isStatic: false,
        restitution: 0.5,
        drag: 0.98,
      ),
      fields: const [],
    );
