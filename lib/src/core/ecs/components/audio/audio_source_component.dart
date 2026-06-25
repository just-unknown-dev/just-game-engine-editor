import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Audio Source',
  group: 'Audio',
  description: 'One-shot audio clip playback.',
  componentType: ECSComponentType.core,
)
class AudioSourceEditorComponent extends AudioSourceComponent {
  AudioSourceEditorComponent() : super(clipPath: '');

  @EditorField(label: 'Path', readOnly: true)
  String get path => super.clipPath;

  @override
  @EditorField(label: 'Volume', scrubStep: 0.05, scrubFractionDigits: 2, scrubMin: 0, scrubMax: 1)
  double get volume => super.volume;
  @override
  set volume(double v) => super.volume = v.clamp(0.0, 1.0);

  @override
  @EditorField(label: 'Pitch', scrubStep: 0.05, scrubFractionDigits: 2, scrubMin: 0)
  double get pitch => super.pitch;
  @override
  set pitch(double v) => super.pitch = v;

  @override
  @EditorField(label: 'Loop')
  bool get loop => super.loop;
  @override
  set loop(bool v) => super.loop = v;

  @override
  @EditorField(label: 'Play on Add')
  bool get playOnAdd => super.playOnAdd;
  @override
  set playOnAdd(bool v) => super.playOnAdd = v;
}
