import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'ChildrenComponent',
  group: 'Hierarchy',
  description: 'Marks entity as a parent that can have child entities.',
)
class ChildrenCatalogComponent extends Component {
  ChildrenCatalogComponent();
}
