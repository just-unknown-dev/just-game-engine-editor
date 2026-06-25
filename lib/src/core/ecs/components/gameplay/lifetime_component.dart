import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Lifetime',
  group: 'Gameplay',
  description: 'Destroys the entity after a fixed duration.',
  componentType: ECSComponentType.core,
)
class LifetimeEditorComponent extends LifetimeComponent {
  LifetimeEditorComponent() : super(1.0);

  @EditorField(label: 'Duration (s)', readOnly: true, scrubStep: 0.1, scrubFractionDigits: 2, scrubMin: 0)
  double get duration => super.initialLifetime;
}
