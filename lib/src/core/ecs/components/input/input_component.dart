import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'InputComponent',
  group: 'Input',
  description: 'Marks entity as the keyboard/gamepad input receiver.',
)
class InputCatalogComponent extends Component {
  InputCatalogComponent();
}
