import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'AudioSourceComponent',
  group: 'Audio',
  description: 'Looping audio source. Set clipPath in inspector.',
)
class AudioSourceCatalogComponent extends Component {
  AudioSourceCatalogComponent();
}
