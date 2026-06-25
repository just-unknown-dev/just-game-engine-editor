import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Physics Body (Polygon)',
  group: 'Physics',
  description: 'Dynamic rigid body with a convex polygon collision shape.',
  componentType: ECSComponentType.core,
)
class PhysicsBodyPolygonEditorComponent extends PhysicsBodyComponent {
  PhysicsBodyPolygonEditorComponent()
      : super(
          shape: PolygonShape(
            const [Offset(-25, -25), Offset(25, -25), Offset(0, 25)],
          ),
        );
}
