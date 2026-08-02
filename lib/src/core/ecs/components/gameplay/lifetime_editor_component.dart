import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class LifetimeEditorComponent extends EditorComponent {
  LifetimeEditorComponent()
    : super(
      id: 'lifetime_0ec055c7',
      name: 'Lifetime',
      type: 'LifetimeComponent',
      group: 'Gameplay',
      description: 'Destroys the entity after a fixed duration.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.timer,
      accentColor: const Color(0xFF66BB6A),
      factory: () => LifetimeComponent(3.0),
      fields: [
        EditorComponentField(
          name: 'duration',
          label: 'Duration (s)',
          kind: EditorFieldKind.decimal,
          scrubConfig: const NumberScrubConfig(step: 0.1, fractionDigits: 2, min: 0.0),
          read: (c) => (c as LifetimeComponent).initialLifetime,
          write: (c, v) {
            final lifetime = c as LifetimeComponent;
            final next = (v as num).toDouble();
            lifetime.initialLifetime = next;
            // Authoring-time edit — restart the countdown from the new
            // duration rather than leaving timeRemaining stale.
            lifetime.timeRemaining = next;
          },
        ),
      ],
      );
}
