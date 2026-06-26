import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Rectangle',
  group: 'Rendering',
  description: 'Filled or stroked rectangle.',
  componentType: ECSComponentType.core,
)
class RectangleEditorComponent extends RectangleComponent {
  // ignore: invalid_factory_annotation
  factory RectangleEditorComponent() =>
      RectangleComponent(width: 64, height: 64) as RectangleEditorComponent;

  @EditorField(label: 'W', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get w => width;
  set w(double v) => super.width = v;

  @EditorField(label: 'H', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get h => height;
  set h(double v) => super.height = v;

  @EditorField(label: 'SW', scrubStep: 0.5, scrubFractionDigits: 1, scrubMin: 0)
  double get sw => strokeWidth;
  set sw(double v) => super.strokeWidth = v;

  @EditorField(label: 'CR', scrubStep: 0.5, scrubFractionDigits: 1, scrubMin: 0)
  double get cr => cornerRadius;
  set cr(double v) => super.cornerRadius = v;

  @EditorField(label: 'Fill')
  Color get fillColor => fillStyle.color;
  set fillColor(Color v) => fillStyle = ShapePaintStyle(color: v);

  @EditorField(label: 'Stroke')
  Color get strokeColor => strokeStyle.color;
  set strokeColor(Color v) => strokeStyle = ShapePaintStyle(color: v);

  @EditorField(label: 'Filled')
  bool get filled => super.filled;
  set filled(bool v) => super.filled = v;
}
