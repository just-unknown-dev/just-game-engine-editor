import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'PhysicsBodyCapsule',
  group: 'Physics',
  description: 'Dynamic rigid body with a capsule collision shape.',
)
class PhysicsBodyCapsuleCatalogComponent extends Component {
  PhysicsBodyCapsuleCatalogComponent();
}
