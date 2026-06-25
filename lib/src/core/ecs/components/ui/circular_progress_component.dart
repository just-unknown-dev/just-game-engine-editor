import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Circular Progress',
  group: 'UI',
  description: 'Radial progress indicator.',
  componentType: ECSComponentType.core,
)
class CircularProgressEditorComponent extends CircularProgressComponent {
  CircularProgressEditorComponent() : super(radius: 30);

  @EditorField(label: 'Progress', scrubStep: 0.02, scrubFractionDigits: 2, scrubMin: 0, scrubMax: 1)
  double get progressValue => super.progress;
  set progressValue(double v) => setProgress(v);

  @override
  @EditorField(label: 'Radius', scrubStep: 0.5, scrubFractionDigits: 1, scrubMin: 0)
  double get radius => super.size.width / 2;
  set radius(double v) {
    if (v > 0) super.size = Size(v * 2, v * 2);
  }
}
