import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class CircleEditorComponent extends EditorComponent {
  CircleEditorComponent()
    : super(
      id: 'circle_1d72ae60',
      name: 'Circle',
      type: 'CircleComponent',
      group: 'Rendering',
      description: 'Filled or stroked circle.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.circle_outlined,
      accentColor: const Color(0xFF42A5F5),
      factory: () => CircleComponent(radius: 32),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Size', fields: [
          EditorComponentField(
            name: 'radius',
            label: 'Radius',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
            read: (c) => (c as CircleComponent).radius,
            write: (c, v) =>
                (c as CircleComponent).radius = (v as num).toDouble(),
          ),
        ]),
        EditorFieldGroup(name: 'Appearance', fields: [
          EditorComponentField(
            name: 'filled',
            label: 'Filled',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as CircleComponent).filled,
            write: (c, v) => (c as CircleComponent).filled = v as bool,
          ),
          EditorComponentField(
            name: 'fillColor',
            label: 'Fill',
            kind: EditorFieldKind.shapePaintStyle,
            read: (c) => (c as CircleComponent).fillStyle,
            write: (c, v) => (c as CircleComponent).fillStyle =
                ShapePaintStyle(color: v as Color),
          ),
          EditorComponentField(
            name: 'strokeColor',
            label: 'Stroke',
            kind: EditorFieldKind.shapePaintStyle,
            read: (c) => (c as CircleComponent).strokeStyle,
            write: (c, v) => (c as CircleComponent).strokeStyle =
                ShapePaintStyle(color: v as Color),
          ),
          EditorComponentField(
            name: 'sw',
            label: 'SW',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
            read: (c) => (c as CircleComponent).strokeWidth,
            write: (c, v) =>
                (c as CircleComponent).strokeWidth = (v as num).toDouble(),
          ),
        ]),
      ],
      );
}
