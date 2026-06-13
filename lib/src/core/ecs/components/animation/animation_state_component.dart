import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'AnimationStateComponent',
  group: 'Animation',
  description: 'Sprite-sheet animation state (idle, 4 frames).',
)
class AnimationStateCatalogComponent extends Component {
  AnimationStateCatalogComponent();
}
