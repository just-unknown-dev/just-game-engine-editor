import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'PhysicsBodyPolygon',
  group: 'Physics',
  description: 'Dynamic rigid body with a convex polygon collision shape.',
)
class PhysicsBodyPolygonCatalogComponent extends Component {
  PhysicsBodyPolygonCatalogComponent();
}
