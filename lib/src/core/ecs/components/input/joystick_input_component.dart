import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Joystick Input',
  group: 'Input',
  description: 'Virtual joystick input source.',
  componentType: ECSComponentType.core,
)
class JoystickInputEditorComponent extends JoystickInputComponent {
  JoystickInputEditorComponent() : super();
}
