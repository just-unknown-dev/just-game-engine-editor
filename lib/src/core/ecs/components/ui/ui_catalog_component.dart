import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'UI',
  group: 'UI',
  description: 'Base UI layout container.',
  componentType: ECSComponentType.core,
)
class UIEditorComponent extends UIComponent {
  UIEditorComponent() : super(size: const Size(100, 40));

  @EditorField(label: 'W', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get w => super.size.width;
  set w(double v) => super.size = Size(v, super.size.height);

  @EditorField(label: 'H', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get h => super.size.height;
  set h(double v) => super.size = Size(super.size.width, v);

  @override
  @EditorField(label: 'Visible')
  bool get visible => super.visible;
  @override
  set visible(bool v) => super.visible = v;

  @override
  @EditorField(label: 'Enabled')
  bool get enabled => super.enabled;
  @override
  set enabled(bool v) => super.enabled = v;
}
