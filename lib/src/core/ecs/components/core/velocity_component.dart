import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'VelocityComponent',
  group: 'Core',
  description: 'Linear velocity with an optional max-speed cap.',
)
class VelocityCatalogComponent extends Component {
  VelocityCatalogComponent();
}
