import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Physics Body (Rounded Rect)',
  group: 'Physics',
  description: 'Dynamic rigid body with rounded rectangle collision.',
  componentType: ECSComponentType.core,
)
class PhysicsBodyRoundedRectEditorComponent extends PhysicsBodyComponent {
  PhysicsBodyRoundedRectEditorComponent()
      : super(shape: RectangleShape(50, 50));
}
