import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'PhysicsBodyChain',
  group: 'Physics',
  description: 'Static chain collider for terrain-like collision paths.',
)
class PhysicsBodyChainCatalogComponent extends Component {
  PhysicsBodyChainCatalogComponent();
}
