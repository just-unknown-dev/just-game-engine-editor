import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'PhysicsSensorCircle',
  group: 'Physics',
  description: 'Static circular sensor body (overlap detection only).',
)
class PhysicsSensorCircleCatalogComponent extends Component {
  PhysicsSensorCircleCatalogComponent();
}
