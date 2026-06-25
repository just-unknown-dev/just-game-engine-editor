import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Sprite',
  group: 'Rendering',
  description: 'Sprite sheet renderer.',
  componentType: ECSComponentType.core,
)
class SpriteEditorComponent extends SpriteComponent {
  SpriteEditorComponent() : super(spritePath: '');

  @EditorField(label: 'Path')
  String get path => super.spritePath;
  set path(String v) => super.spritePath = v;

  @override
  @EditorField(label: 'Frame', scrubStep: 1.0, scrubInteger: true, scrubMin: 0)
  int get frame => super.frame;
  @override
  set frame(int v) => super.frame = v;

  @override
  @EditorField(label: 'Flip X')
  bool get flipX => super.flipX;
  @override
  set flipX(bool v) => super.flipX = v;

  @override
  @EditorField(label: 'Flip Y')
  bool get flipY => super.flipY;
  @override
  set flipY(bool v) => super.flipY = v;
}
