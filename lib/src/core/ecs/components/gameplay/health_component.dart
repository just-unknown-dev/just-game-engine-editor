import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'HealthComponent',
  group: 'Gameplay',
  description: 'Hit-points with max-health = 100.',
)
class HealthCatalogComponent extends Component {
  HealthCatalogComponent();
}
