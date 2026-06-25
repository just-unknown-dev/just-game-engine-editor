import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Physics Body (Circle)',
  group: 'Physics',
  description: 'Dynamic rigid body with a circular collision shape.',
  componentType: ECSComponentType.core,
)
class PhysicsBodyCircleEditorComponent extends PhysicsBodyComponent {
  PhysicsBodyCircleEditorComponent() : super(shape: CircleShape(25));
}
