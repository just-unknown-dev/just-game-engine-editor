import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'PhysicsBodyRectangle',
  group: 'Physics',
  description: 'Dynamic rigid body with a rectangle collision shape.',
)
class PhysicsBodyRectangleCatalogComponent extends Component {
  PhysicsBodyRectangleCatalogComponent();
}
