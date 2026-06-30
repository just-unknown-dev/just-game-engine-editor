import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kPhysicsBodyChainEditorComponent =
    EditorComponentDescriptor(
      id: 'physics_body_chain_02eccc81',
      name: 'Physics Body (Chain)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Static chain collider for terrain-like collision paths.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.link,
      accentColor: const Color(0xFFFF7043),
      factory: () => PhysicsBodyComponent(
        shape: ChainShape(const [
          Offset(-60, 8),
          Offset(-30, -14),
          Offset(0, 8),
          Offset(30, -14),
          Offset(60, 8),
        ], thickness: 3),
        mass: 0,
        isStatic: true,
        restitution: 0.3,
        drag: 0.98,
      ),
      fields: const [],
    );
