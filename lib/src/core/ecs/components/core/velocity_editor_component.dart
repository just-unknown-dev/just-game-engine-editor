import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class VelocityEditorComponent extends EditorComponent {
  VelocityEditorComponent()
    : super(
      id: 'velocity_88533db4',
      name: 'Velocity',
      type: 'VelocityComponent',
      group: 'Core',
      description: 'Linear velocity with an optional max-speed cap.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.speed,
      accentColor: const Color(0xFF607D8B),
      factory: () => VelocityComponent(maxSpeed: 500),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Settings', fields: [
          EditorComponentField(
            name: 'maxSpeed',
            label: 'Max Speed',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as VelocityComponent).maxSpeed,
            write: (c, v) =>
                (c as VelocityComponent).maxSpeed = (v as num).toDouble(),
          ),
        ]),
        EditorFieldGroup(name: 'Velocity', fields: [
          EditorComponentField(
            name: 'velocityX',
            label: 'VX',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
            read: (c) => (c as VelocityComponent).velocity.x,
            write: (c, v) {
              final vel = c as VelocityComponent;
              vel.setVelocityXY((v as num).toDouble(), vel.velocity.y);
            },
          ),
          EditorComponentField(
            name: 'velocityY',
            label: 'VY',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
            read: (c) => (c as VelocityComponent).velocity.y,
            write: (c, v) {
              final vel = c as VelocityComponent;
              vel.setVelocityXY(vel.velocity.x, (v as num).toDouble());
            },
          ),
        ]),
      ],
      );
}
