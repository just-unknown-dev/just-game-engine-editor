import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Text',
  group: 'UI',
  description: 'Renders a text label.',
  componentType: ECSComponentType.core,
)
class TextEditorComponent extends TextComponent {
  TextEditorComponent() : super(text: '');

  @EditorField(label: 'Text')
  String get textValue => super.text;
  set textValue(String v) => super.text = v;

  @EditorField(label: 'W', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get w => super.size.width;
  set w(double v) => super.size = Size(v, super.size.height);

  @EditorField(label: 'H', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get h => super.size.height;
  set h(double v) => super.size = Size(super.size.width, v);
}
