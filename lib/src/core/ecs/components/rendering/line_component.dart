import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'LineComponent',
  group: 'Rendering',
  description: 'A line segment between two points.',
)
class LineCatalogComponent extends Component {
  LineCatalogComponent();
}
