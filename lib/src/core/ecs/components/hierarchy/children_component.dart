import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Children',
  group: 'Hierarchy',
  description: 'Groups child entities.',
  componentType: ECSComponentType.core,
)
class ChildrenEditorComponent extends ChildrenComponent {
  ChildrenEditorComponent() : super();
}
