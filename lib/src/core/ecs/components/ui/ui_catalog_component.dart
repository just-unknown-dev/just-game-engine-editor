import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'UIComponent',
  group: 'UI',
  description: 'Base UI element (100x40).',
)
class UICatalogComponent extends Component {
  UICatalogComponent();
}
