import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'AudioStreamComponent',
  group: 'Audio',
  description: 'Streaming music track. Set path in inspector.',
)
class AudioStreamCatalogComponent extends Component {
  AudioStreamCatalogComponent();
}
