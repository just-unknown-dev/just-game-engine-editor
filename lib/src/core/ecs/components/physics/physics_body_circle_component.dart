import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'PhysicsBodyCircle',
  group: 'Physics',
  description: 'Dynamic rigid body with a circular collision shape.',
)
class PhysicsBodyCircleCatalogComponent extends Component {
  PhysicsBodyCircleCatalogComponent();
}
