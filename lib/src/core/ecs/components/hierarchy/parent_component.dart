import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Parent',
  group: 'Hierarchy',
  description: 'Attaches this entity to a parent.',
  componentType: ECSComponentType.core,
)
class ParentEditorComponent extends ParentComponent {
  ParentEditorComponent() : super();
}
