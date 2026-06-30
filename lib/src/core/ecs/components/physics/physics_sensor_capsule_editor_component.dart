import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kPhysicsSensorCapsuleEditorComponent =
    EditorComponentDescriptor(
      id: 'physics_sensor_capsule_2dedb6e5',
      name: 'Physics Sensor (Capsule)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Static capsule sensor body (overlap detection only).',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.record_voice_over_outlined,
      accentColor: const Color(0xFFFF7043),
      factory: () => PhysicsBodyComponent(
        shape: CapsuleShape(
          center1: const Offset(0, -20),
          center2: const Offset(0, 20),
          radius: 14,
        ),
        mass: 0,
        isStatic: true,
        isSensor: true,
        restitution: 0.0,
        drag: 0.98,
      ),
      fields: const [],
    );
