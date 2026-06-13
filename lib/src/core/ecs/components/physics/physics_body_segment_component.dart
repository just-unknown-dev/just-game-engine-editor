import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'PhysicsBodySegment',
  group: 'Physics',
  description: 'Static line segment collider, useful for ramps/platforms.',
)
class PhysicsBodySegmentCatalogComponent extends Component {
  PhysicsBodySegmentCatalogComponent();
}
