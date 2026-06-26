import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Line',
  group: 'Rendering',
  description: 'A stroked line between two points.',
  componentType: ECSComponentType.core,
)
class LineEditorComponent extends LineComponent {
  // ignore: invalid_factory_annotation
  factory LineEditorComponent() =>
      LineComponent(end: const Offset(100, 0)) as LineEditorComponent;

  @EditorField(label: 'Start X', scrubStep: 1.0, scrubFractionDigits: 1)
  double get startX => start.dx;
  set startX(double v) => start = Offset(v, start.dy);

  @EditorField(label: 'Start Y', scrubStep: 1.0, scrubFractionDigits: 1)
  double get startY => start.dy;
  set startY(double v) => start = Offset(start.dx, v);

  @EditorField(label: 'End X', scrubStep: 1.0, scrubFractionDigits: 1)
  double get endX => end.dx;
  set endX(double v) => end = Offset(v, end.dy);

  @EditorField(label: 'End Y', scrubStep: 1.0, scrubFractionDigits: 1)
  double get endY => end.dy;
  set endY(double v) => end = Offset(end.dx, v);

  @EditorField(label: 'Stroke', scrubStep: 0.5, scrubFractionDigits: 1, scrubMin: 0)
  double get strokeW => strokeWidth;
  set strokeW(double v) => super.strokeWidth = v;

  @EditorField(label: 'Paint')
  Color get strokeColor => strokeStyle.color;
  set strokeColor(Color v) => strokeStyle = ShapePaintStyle(color: v);

  @EditorField(label: 'Round')
  bool get roundCaps => super.roundCaps;
  set roundCaps(bool v) => super.roundCaps = v;
}
