import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Polygon',
  group: 'Rendering',
  description: 'Filled or stroked polygon.',
  componentType: ECSComponentType.core,
)
class PolygonEditorComponent extends PolygonComponent {
  // ignore: invalid_factory_annotation
  factory PolygonEditorComponent() => PolygonComponent(
    vertices: const [Offset(-32, -32), Offset(32, -32), Offset(0, 32)],
  ) as PolygonEditorComponent;

  @EditorField(label: 'Verts', readOnly: true)
  int get vertCount => vertices.length;

  @EditorField(label: 'Stroke', scrubStep: 0.5, scrubFractionDigits: 1, scrubMin: 0)
  double get strokeW => strokeWidth;
  set strokeW(double v) => super.strokeWidth = v;

  @EditorField(label: 'Fill')
  Color get fillColor => fillStyle.color;
  set fillColor(Color v) => fillStyle = ShapePaintStyle(color: v);

  @EditorField(label: 'Stroke Color')
  Color get strokeColor => strokeStyle.color;
  set strokeColor(Color v) => strokeStyle = ShapePaintStyle(color: v);

  @EditorField(label: 'Filled')
  bool get filled => super.filled;
  set filled(bool v) => super.filled = v;
}
