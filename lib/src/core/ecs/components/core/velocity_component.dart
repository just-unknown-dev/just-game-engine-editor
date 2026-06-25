import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Velocity',
  group: 'Core',
  description: 'Linear velocity with an optional max-speed cap.',
  componentType: ECSComponentType.core,
)
class VelocityEditorComponent extends VelocityComponent {
  VelocityEditorComponent() : super(maxSpeed: 500);

  @EditorField(label: 'VX', scrubStep: 1.0, scrubFractionDigits: 1)
  double get velocityX => velocity.x;
  set velocityX(double v) => setVelocityXY(v, velocity.y);

  @EditorField(label: 'VY', scrubStep: 1.0, scrubFractionDigits: 1)
  double get velocityY => velocity.y;
  set velocityY(double v) => setVelocityXY(velocity.x, v);

  @override
  @EditorField(label: 'Max Speed', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get maxSpeed => super.maxSpeed;
  @override
  set maxSpeed(double v) => super.maxSpeed = v;
}
