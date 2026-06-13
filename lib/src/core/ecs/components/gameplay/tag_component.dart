import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'TagComponent',
  group: 'Gameplay',
  description: 'String tag for entity categorisation.',
)
class TagCatalogComponent extends Component {
  TagCatalogComponent();
}
