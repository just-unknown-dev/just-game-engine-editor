import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kPhysicsSensorCircleEditorComponent =
    EditorComponentDescriptor(
      id: 'physics_sensor_circle_e9a23cf2',
      name: 'Physics Sensor (Circle)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Static circular sensor body (overlap detection only).',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.adjust,
      accentColor: const Color(0xFFFF7043),
      factory: () => PhysicsBodyComponent(
        shape: CircleShape(48),
        mass: 0,
        isStatic: true,
        isSensor: true,
        restitution: 0.0,
        drag: 0.98,
      ),
      fields: const [],
    );
