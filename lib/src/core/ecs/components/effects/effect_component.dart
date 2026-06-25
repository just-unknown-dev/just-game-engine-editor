import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Effects',
  group: 'Effects',
  description: 'Enables the effects system on this entity.',
  componentType: ECSComponentType.core,
)
class EffectEditorComponent extends EffectComponent {
  EffectEditorComponent() : super();
}
