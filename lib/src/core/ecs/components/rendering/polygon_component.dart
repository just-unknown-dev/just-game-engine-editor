import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'PolygonComponent',
  group: 'Rendering',
  description: 'Convex polygon (default: square outline).',
)
class PolygonCatalogComponent extends Component {
  PolygonCatalogComponent();
}
