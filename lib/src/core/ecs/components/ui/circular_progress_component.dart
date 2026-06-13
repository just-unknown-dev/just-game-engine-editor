import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'CircularProgressComponent',
  group: 'UI',
  description: 'Circular progress indicator (radius 30).',
)
class CircularProgressCatalogComponent extends Component {
  CircularProgressCatalogComponent();
}
