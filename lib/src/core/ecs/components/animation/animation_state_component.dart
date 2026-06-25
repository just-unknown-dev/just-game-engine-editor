import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Animation State',
  group: 'Animation',
  description: 'Drives sprite sheet animation.',
  componentType: ECSComponentType.core,
)
class AnimationStateEditorComponent extends AnimationStateComponent {
  AnimationStateEditorComponent() : super(currentAnimation: 'idle');

  @EditorField(label: 'Name')
  String get animName => super.currentAnimation;
  set animName(String v) {
    if (v.isNotEmpty) super.currentAnimation = v;
  }

  @override
  @EditorField(label: 'Frames', scrubStep: 1.0, scrubInteger: true, scrubMin: 1)
  int get frameCount => super.frameCount;
  @override
  set frameCount(int v) {
    if (v > 0) super.frameCount = v;
  }

  @override
  @EditorField(label: 'Dur(s)', scrubStep: 0.01, scrubFractionDigits: 3, scrubMin: 0)
  double get frameDuration => super.frameDuration;
  @override
  set frameDuration(double v) {
    if (v > 0) super.frameDuration = v;
  }

  @override
  @EditorField(label: 'Loop')
  bool get loop => super.loop;
  @override
  set loop(bool v) => super.loop = v;

  @EditorField(label: 'Playing')
  bool get playing => super.isPlaying;
  set playing(bool v) => super.isPlaying = v;
}
