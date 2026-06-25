import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Camera Follow',
  group: 'Camera',
  description: 'Locks the camera onto this entity.',
  componentType: ECSComponentType.core,
)
class CameraFollowEditorComponent extends CameraFollowComponent {
  CameraFollowEditorComponent() : super();

  @EditorField(label: 'Lookahead', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get lookahead => super.lookaheadDistance;
  set lookahead(double v) => super.lookaheadDistance = v;

  @override
  @EditorField(label: 'Enabled')
  bool get enabled => super.enabled;
  @override
  set enabled(bool v) => super.enabled = v;
}
