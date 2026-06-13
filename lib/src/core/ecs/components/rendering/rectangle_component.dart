import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'RectangleComponent',
  group: 'Rendering',
  description: 'Filled or stroked rectangle.',
)
class RectangleCatalogComponent extends Component {
  RectangleCatalogComponent();
}
