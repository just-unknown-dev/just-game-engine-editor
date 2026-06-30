import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class RectangleEditorComponent extends EditorComponent {
  RectangleEditorComponent()
    : super(
      id: 'rectangle_c9214e61',
      name: 'Rectangle',
      type: 'RectangleComponent',
      group: 'Rendering',
      description: 'Filled or stroked rectangle.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.rectangle_outlined,
      accentColor: const Color(0xFF42A5F5),
      factory: () => RectangleComponent(width: 64, height: 64),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Size', fields: [
          EditorComponentField(
            name: 'w',
            label: 'W',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as RectangleComponent).width,
            write: (c, v) =>
                (c as RectangleComponent).width = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'h',
            label: 'H',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as RectangleComponent).height,
            write: (c, v) =>
                (c as RectangleComponent).height = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'cr',
            label: 'CR',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
            read: (c) => (c as RectangleComponent).cornerRadius,
            write: (c, v) =>
                (c as RectangleComponent).cornerRadius = (v as num).toDouble(),
          ),
        ]),
        EditorFieldGroup(name: 'Appearance', fields: [
          EditorComponentField(
            name: 'filled',
            label: 'Filled',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as RectangleComponent).filled,
            write: (c, v) =>
                (c as RectangleComponent).filled = v as bool,
          ),
          EditorComponentField(
            name: 'fillColor',
            label: 'Fill',
            kind: EditorFieldKind.color,
            read: (c) => (c as RectangleComponent).fillStyle.color,
            write: (c, v) => (c as RectangleComponent).fillStyle =
                ShapePaintStyle(color: v as Color),
          ),
          EditorComponentField(
            name: 'strokeColor',
            label: 'Stroke',
            kind: EditorFieldKind.color,
            read: (c) => (c as RectangleComponent).strokeStyle.color,
            write: (c, v) => (c as RectangleComponent).strokeStyle =
                ShapePaintStyle(color: v as Color),
          ),
          EditorComponentField(
            name: 'sw',
            label: 'SW',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
            read: (c) => (c as RectangleComponent).strokeWidth,
            write: (c, v) =>
                (c as RectangleComponent).strokeWidth = (v as num).toDouble(),
          ),
        ]),
      ],
      );
}
