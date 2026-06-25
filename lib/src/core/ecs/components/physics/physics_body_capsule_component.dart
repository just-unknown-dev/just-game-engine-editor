import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Physics Body (Capsule)',
  group: 'Physics',
  description: 'Dynamic rigid body with a capsule collision shape.',
  componentType: ECSComponentType.core,
)
class PhysicsBodyCapsuleEditorComponent extends PhysicsBodyComponent {
  PhysicsBodyCapsuleEditorComponent()
      : super(shape: CapsuleShape.vertical(height: 60, radius: 15));
}
