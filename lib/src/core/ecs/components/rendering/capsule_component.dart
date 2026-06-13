import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'CapsuleComponent',
  group: 'Rendering',
  description: 'Filled or stroked capsule (rounded rectangle).',
)
class CapsuleCatalogComponent extends Component {
  CapsuleCatalogComponent();
}
