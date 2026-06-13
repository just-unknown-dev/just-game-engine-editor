import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'PhysicsBodyRoundedRect',
  group: 'Physics',
  description: 'Dynamic rigid body with rounded rectangle collision.',
)
class PhysicsBodyRoundedRectCatalogComponent extends Component {
  PhysicsBodyRoundedRectCatalogComponent();
}
