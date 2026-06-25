import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Tag',
  group: 'Gameplay',
  description: 'String tag for filtering entities.',
  componentType: ECSComponentType.core,
)
class TagEditorComponent extends TagComponent {
  TagEditorComponent() : super('');

  @EditorField(label: 'Tag', readOnly: true)
  String get tagValue => super.tag;
}
