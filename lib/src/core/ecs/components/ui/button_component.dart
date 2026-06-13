import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'ButtonComponent',
  group: 'UI',
  description: 'Clickable button (120x40).',
)
class ButtonCatalogComponent extends Component {
  ButtonCatalogComponent();
}
