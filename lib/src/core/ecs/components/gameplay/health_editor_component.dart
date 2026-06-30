import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kHealthEditorComponent =
    EditorComponentDescriptor(
      id: 'health_cf522cfc',
      name: 'Health',
      type: 'HealthComponent',
      group: 'Gameplay',
      description: 'Hit-point pool with optional invulnerability.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.favorite,
      accentColor: const Color(0xFF66BB6A),
      factory: () => HealthComponent(maxHealth: 100),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Health', fields: [
          EditorComponentField(
            name: 'hp',
            label: 'HP',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as HealthComponent).health,
            write: (c, v) =>
                (c as HealthComponent).health = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'maxHp',
            label: 'Max',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as HealthComponent).maxHealth,
            write: (c, v) =>
                (c as HealthComponent).maxHealth = (v as num).toDouble(),
          ),
        ]),
        EditorFieldGroup(name: 'State', fields: [
          EditorComponentField(
            name: 'invulnerable',
            label: 'Invulnerable',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as HealthComponent).isInvulnerable,
            write: (c, v) =>
                (c as HealthComponent).isInvulnerable = v as bool,
          ),
        ]),
      ],
    );
