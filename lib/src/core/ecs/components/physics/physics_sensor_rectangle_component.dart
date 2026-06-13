import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'PhysicsSensorRectangle',
  group: 'Physics',
  description: 'Static rectangle sensor body (overlap detection only).',
)
class PhysicsSensorRectangleCatalogComponent extends Component {
  PhysicsSensorRectangleCatalogComponent();
}
