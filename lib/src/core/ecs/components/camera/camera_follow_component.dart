import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'CameraFollowComponent',
  group: 'Camera',
  description: 'Camera smoothly follows this entity.',
)
class CameraFollowCatalogComponent extends Component {
  CameraFollowCatalogComponent();
}
