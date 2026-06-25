import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Physics Sensor (Rect)',
  group: 'Physics',
  description: 'Static rectangle sensor body (overlap detection only).',
  componentType: ECSComponentType.core,
)
class PhysicsSensorRectangleEditorComponent extends PhysicsBodyComponent {
  PhysicsSensorRectangleEditorComponent()
      : super(shape: RectangleShape(50, 50), isSensor: true);
}
