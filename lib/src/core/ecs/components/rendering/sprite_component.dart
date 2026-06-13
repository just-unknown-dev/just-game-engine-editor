import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'SpriteComponent',
  group: 'Rendering',
  description: 'Single sprite / texture frame. Set spritePath in inspector.',
)
class SpriteCatalogComponent extends Component {
  SpriteCatalogComponent();
}
