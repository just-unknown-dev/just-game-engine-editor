import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Button',
  group: 'UI',
  description: 'Interactive button widget.',
  componentType: ECSComponentType.core,
)
class ButtonEditorComponent extends ButtonComponent {
  ButtonEditorComponent() : super(text: 'Button', size: const Size(120, 40));

  @EditorField(label: 'Label')
  String get label => super.text;
  set label(String v) => super.text = v;

  @EditorField(label: 'W', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get w => super.size.width;
  set w(double v) => super.size = Size(v, super.size.height);

  @EditorField(label: 'H', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get h => super.size.height;
  set h(double v) => super.size = Size(super.size.width, v);
}
