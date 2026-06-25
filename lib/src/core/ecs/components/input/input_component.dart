import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Input',
  group: 'Input',
  description: 'Enables keyboard/mouse input on this entity.',
  componentType: ECSComponentType.core,
)
class InputEditorComponent extends InputComponent {
  InputEditorComponent() : super();
}
