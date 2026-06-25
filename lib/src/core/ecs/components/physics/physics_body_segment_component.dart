import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Physics Body (Segment)',
  group: 'Physics',
  description: 'Static line segment collider, useful for ramps/platforms.',
  componentType: ECSComponentType.core,
)
class PhysicsBodySegmentEditorComponent extends PhysicsBodyComponent {
  PhysicsBodySegmentEditorComponent()
      : super(
          shape: SegmentShape(
            const Offset(-50, 0),
            const Offset(50, 0),
          ),
          isStatic: true,
        );
}
