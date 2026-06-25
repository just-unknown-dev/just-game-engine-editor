import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Linear Progress',
  group: 'UI',
  description: 'Horizontal progress bar.',
  componentType: ECSComponentType.core,
)
class LinearProgressEditorComponent extends LinearProgressComponent {
  LinearProgressEditorComponent() : super(size: const Size(200, 20));

  @EditorField(label: 'Progress', scrubStep: 0.02, scrubFractionDigits: 2, scrubMin: 0, scrubMax: 1)
  double get progressValue => super.progress;
  set progressValue(double v) => setProgress(v);

  @EditorField(label: 'W', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get w => super.size.width;
  set w(double v) => super.size = Size(v, super.size.height);

  @EditorField(label: 'H', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get h => super.size.height;
  set h(double v) => super.size = Size(super.size.width, v);
}
