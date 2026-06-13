import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'LifetimeComponent',
  group: 'Gameplay',
  description: 'Auto-destroys the entity after 3 seconds.',
)
class LifetimeCatalogComponent extends Component {
  LifetimeCatalogComponent();
}
