import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'LinearProgressComponent',
  group: 'UI',
  description: 'Horizontal progress bar (200x20).',
)
class LinearProgressCatalogComponent extends Component {
  LinearProgressCatalogComponent();
}
