import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'ParentComponent',
  group: 'Hierarchy',
  description: 'Attaches entity to a parent entity.',
)
class ParentCatalogComponent extends Component {
  ParentCatalogComponent();
}
