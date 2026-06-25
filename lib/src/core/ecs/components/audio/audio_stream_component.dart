import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Audio Stream',
  group: 'Audio',
  description: 'Streaming audio playback.',
  componentType: ECSComponentType.core,
)
class AudioStreamEditorComponent extends AudioStreamComponent {
  AudioStreamEditorComponent() : super(path: '');

  @EditorField(label: 'Path', readOnly: true)
  String get streamPath => super.path;

  @override
  @EditorField(label: 'Volume', scrubStep: 0.05, scrubFractionDigits: 2, scrubMin: 0, scrubMax: 1)
  double get volume => super.volume;
  @override
  set volume(double v) => super.volume = v.clamp(0.0, 1.0);

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
