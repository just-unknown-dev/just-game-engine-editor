import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class PhysicsBodySegmentEditorComponent extends EditorComponent {
  PhysicsBodySegmentEditorComponent()
    : super(
      id: 'physics_body_segment_03c88561',
      name: 'Physics Body (Segment)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Static line segment collider, useful for ramps/platforms.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.horizontal_rule,
      accentColor: const Color(0xFFFF7043),
      factory: () => PhysicsBodyComponent(
        shape: SegmentShape(
          const Offset(-48, 0),
          const Offset(48, -20),
          thickness: 3,
        ),
        mass: 0,
        isStatic: true,
        restitution: 0.3,
        drag: 0.98,
      ),
      fields: const [],
      );
}
