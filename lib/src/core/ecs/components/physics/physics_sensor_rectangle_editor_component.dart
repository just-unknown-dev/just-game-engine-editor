import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kPhysicsSensorRectEditorComponent =
    EditorComponentDescriptor(
      id: 'physics_sensor_rect_fc75383b',
      name: 'Physics Sensor (Rect)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Static rectangle sensor body (overlap detection only).',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.crop_square,
      accentColor: const Color(0xFFFF7043),
      factory: () => PhysicsBodyComponent(
        shape: RectangleShape(96, 48),
        mass: 0,
        isStatic: true,
        isSensor: true,
        restitution: 0.0,
        drag: 0.98,
      ),
      fields: const [],
    );
