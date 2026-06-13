import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'CircleComponent',
  group: 'Rendering',
  description: 'Filled or stroked circle.',
)
class CircleCatalogComponent extends Component {
  CircleCatalogComponent();
}
