import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kLineEditorComponent =
    EditorComponentDescriptor(
      id: 'line_5a69b8e2',
      name: 'Line',
      type: 'LineComponent',
      group: 'Rendering',
      description: 'A stroked line between two points.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.show_chart,
      accentColor: const Color(0xFF42A5F5),
      factory: () => LineComponent(end: const Offset(100, 0)),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Points', fields: [
          EditorComponentField(
            name: 'startX',
            label: 'Start X',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
            read: (c) => (c as LineComponent).start.dx,
            write: (c, v) {
              final l = c as LineComponent;
              l.start = Offset((v as num).toDouble(), l.start.dy);
            },
          ),
          EditorComponentField(
            name: 'startY',
            label: 'Start Y',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
            read: (c) => (c as LineComponent).start.dy,
            write: (c, v) {
              final l = c as LineComponent;
              l.start = Offset(l.start.dx, (v as num).toDouble());
            },
          ),
          EditorComponentField(
            name: 'endX',
            label: 'End X',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
            read: (c) => (c as LineComponent).end.dx,
            write: (c, v) {
              final l = c as LineComponent;
              l.end = Offset((v as num).toDouble(), l.end.dy);
            },
          ),
          EditorComponentField(
            name: 'endY',
            label: 'End Y',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
            read: (c) => (c as LineComponent).end.dy,
            write: (c, v) {
              final l = c as LineComponent;
              l.end = Offset(l.end.dx, (v as num).toDouble());
            },
          ),
        ]),
        EditorFieldGroup(name: 'Appearance', fields: [
          EditorComponentField(
            name: 'strokeColor',
            label: 'Paint',
            kind: EditorFieldKind.color,
            read: (c) => (c as LineComponent).strokeStyle.color,
            write: (c, v) => (c as LineComponent).strokeStyle =
                ShapePaintStyle(color: v as Color),
          ),
          EditorComponentField(
            name: 'strokeW',
            label: 'Stroke',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
            read: (c) => (c as LineComponent).strokeWidth,
            write: (c, v) =>
                (c as LineComponent).strokeWidth = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'roundCaps',
            label: 'Round',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as LineComponent).roundCaps,
            write: (c, v) => (c as LineComponent).roundCaps = v as bool,
          ),
        ]),
      ],
    );
