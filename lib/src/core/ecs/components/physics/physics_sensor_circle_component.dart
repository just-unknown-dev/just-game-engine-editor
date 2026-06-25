import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Physics Sensor (Circle)',
  group: 'Physics',
  description: 'Static circular sensor body (overlap detection only).',
  componentType: ECSComponentType.core,
)
class PhysicsSensorCircleEditorComponent extends PhysicsBodyComponent {
  PhysicsSensorCircleEditorComponent()
      : super(shape: CircleShape(25), isSensor: true);
}
