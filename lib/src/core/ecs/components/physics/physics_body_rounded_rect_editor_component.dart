import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kPhysicsBodyRoundedRectEditorComponent =
    EditorComponentDescriptor(
      id: 'physics_body_rounded_rect_e4a568a0',
      name: 'Physics Body (Rounded Rect)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Dynamic rigid body with rounded rectangle collision.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.rounded_corner,
      accentColor: const Color(0xFFFF7043),
      factory: () => PhysicsBodyComponent(
        shape: RoundedPolygonShape.rect(width: 56, height: 36, cornerRadius: 8),
        mass: 1.3,
        isStatic: false,
        restitution: 0.5,
        drag: 0.98,
      ),
      fields: const [],
    );
