// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'health_cf522cfc',
      name: 'Health',
      type: 'HealthComponent',
      group: 'Gameplay',
      description: 'Hit-point pool with optional invulnerability.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => HealthComponent(maxHealth: 100),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'hp',
          label: 'HP',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as HealthComponent).health,
          write: (component, value) {
            (component as HealthComponent).health = ((value as num).toDouble());
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'invulnerable',
          label: 'Invulnerable',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as HealthComponent).isInvulnerable,
          write: (component, value) {
            (component as HealthComponent).isInvulnerable = (value as bool);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'maxHp',
          label: 'Max',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
          read: (component) => (component as HealthComponent).maxHealth,
          write: (component, value) {
            (component as HealthComponent).maxHealth = ((value as num).toDouble());
          },
          enumValues: null,
          enumParser: null,
        ),
      ],
    );

final List<EditorComponentDescriptor> _generatedEditorComponentDescriptors =
    <EditorComponentDescriptor>[
      _$editorComponentDescriptor0,
    ];

void registerGeneratedCustomComponents([CustomComponentRegistry? registry]) {
  final target = registry ?? CustomComponentRegistry.instance;
  target.registerAll(_generatedEditorComponentDescriptors);
}
