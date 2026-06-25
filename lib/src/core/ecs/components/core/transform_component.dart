import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Transform',
  group: 'Core',
  description: 'Position, rotation, and scale.',
  deletable: false,
  componentType: ECSComponentType.core,
)
class TransformEditorComponent extends TransformComponent {
  TransformEditorComponent() : super();

  @EditorField(label: 'X', scrubStep: 1.0, scrubFractionDigits: 1)
  double get posX => position.x;
  set posX(double v) => position = Vector3(v, position.y, position.z);

  @EditorField(label: 'Y', scrubStep: 1.0, scrubFractionDigits: 1)
  double get posY => position.y;
  set posY(double v) => position = Vector3(position.x, v, position.z);

  @override
  @EditorField(label: 'Rotation°', scrubStep: 1.0, scrubFractionDigits: 1)
  double get rotation => super.rotation * 180 / 3.14159265;
  @override
  set rotation(double deg) => super.rotation = deg * 3.14159265 / 180;

  @EditorField(label: 'SX', scrubStep: 0.05, scrubFractionDigits: 3)
  double get scaleX => scale.x;
  set scaleX(double v) => scale = Vector3(v, scale.y, scale.z);

  @EditorField(label: 'SY', scrubStep: 0.05, scrubFractionDigits: 3)
  double get scaleY => scale.y;
  set scaleY(double v) => scale = Vector3(scale.x, v, scale.z);
}
