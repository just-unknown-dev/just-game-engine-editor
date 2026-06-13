import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'JoystickInputComponent',
  group: 'Input',
  description: 'Virtual joystick input state.',
)
class JoystickInputCatalogComponent extends Component {
  JoystickInputCatalogComponent();
}
