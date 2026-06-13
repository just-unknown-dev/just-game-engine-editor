import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'PhysicsSensorCapsule',
  group: 'Physics',
  description: 'Static capsule sensor body (overlap detection only).',
)
class PhysicsSensorCapsuleCatalogComponent extends Component {
  PhysicsSensorCapsuleCatalogComponent();
}
