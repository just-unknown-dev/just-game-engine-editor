import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'TransformComponent',
  group: 'Core',
  description: 'Position, rotation, and scale.',
)
class TransformCatalogComponent extends Component {
  TransformCatalogComponent();
}
