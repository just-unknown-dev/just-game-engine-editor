import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'EffectComponent',
  group: 'Effects',
  description: 'Marker for deterministic tween effects.',
)
class EffectCatalogComponent extends Component {
  EffectCatalogComponent();
}
