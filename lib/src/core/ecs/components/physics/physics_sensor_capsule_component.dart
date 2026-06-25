import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Physics Sensor (Capsule)',
  group: 'Physics',
  description: 'Static capsule sensor body (overlap detection only).',
  componentType: ECSComponentType.core,
)
class PhysicsSensorCapsuleEditorComponent extends PhysicsBodyComponent {
  PhysicsSensorCapsuleEditorComponent()
      : super(
          shape: CapsuleShape.vertical(height: 60, radius: 15),
          isSensor: true,
        );
}
