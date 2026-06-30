import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kPhysicsBodyPolygonEditorComponent =
    EditorComponentDescriptor(
      id: 'physics_body_polygon_804a6518',
      name: 'Physics Body (Polygon)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Dynamic rigid body with a convex polygon collision shape.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.pentagon_outlined,
      accentColor: const Color(0xFFFF7043),
      factory: () => PhysicsBodyComponent(
        shape: PolygonShape([
          const Offset(0, -30),
          const Offset(28, -8),
          const Offset(18, 28),
          const Offset(-18, 28),
          const Offset(-28, -8),
        ]),
        mass: 1.1,
        isStatic: false,
        restitution: 0.45,
        drag: 0.98,
      ),
      fields: const [],
    );
