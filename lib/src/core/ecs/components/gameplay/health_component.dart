import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_annotations.dart';

@ECSComponent(
  name: 'Health',
  group: 'Gameplay',
  description: 'Hit-point pool with optional invulnerability.',
  componentType: ECSComponentType.core,
)
class HealthEditorComponent extends HealthComponent {
  HealthEditorComponent() : super(maxHealth: 100);

  @EditorField(label: 'HP', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get hp => super.health;
  set hp(double v) => super.health = v;

  @EditorField(label: 'Max', scrubStep: 1.0, scrubFractionDigits: 1, scrubMin: 0)
  double get maxHp => super.maxHealth;
  set maxHp(double v) => super.maxHealth = v;

  @EditorField(label: 'Invulnerable')
  bool get invulnerable => super.isInvulnerable;
  set invulnerable(bool v) => super.isInvulnerable = v;
}
