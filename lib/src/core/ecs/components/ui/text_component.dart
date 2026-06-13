import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'TextComponent',
  group: 'UI',
  description: 'Text label (200x40).',
)
class TextCatalogComponent extends Component {
  TextCatalogComponent();
}
