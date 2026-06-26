import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Circle',
  group: 'Rendering',
  description: 'Filled or stroked circle.',
  componentType: ECSComponentType.core,
)
class CircleEditorComponent extends CircleComponent {
  // ignore: invalid_factory_annotation
  factory CircleEditorComponent() =>
      CircleComponent(radius: 32) as CircleEditorComponent;

  @EditorField(label: 'Radius', scrubStep: 0.5, scrubFractionDigits: 1, scrubMin: 0)
  double get radius => super.radius;
  set radius(double v) => super.radius = v;

  @EditorField(label: 'SW', scrubStep: 0.5, scrubFractionDigits: 1, scrubMin: 0)
  double get sw => strokeWidth;
  set sw(double v) => super.strokeWidth = v;

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
