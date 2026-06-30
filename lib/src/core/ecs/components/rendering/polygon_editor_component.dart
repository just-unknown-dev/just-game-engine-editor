import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class PolygonEditorComponent extends EditorComponent {
  PolygonEditorComponent()
    : super(
      id: 'polygon_671a97e0',
      name: 'Polygon',
      type: 'PolygonComponent',
      group: 'Rendering',
      description: 'Filled or stroked polygon.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.pentagon_outlined,
      accentColor: const Color(0xFF42A5F5),
      factory: () => PolygonComponent(
        vertices: const [Offset(-32, -32), Offset(32, -32), Offset(32, 32), Offset(-32, 32)],
      ),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Info', fields: [
          EditorComponentField(
            name: 'vertCount',
            label: 'Verts',
            kind: EditorFieldKind.integer,
            editable: false,
            read: (c) => (c as PolygonComponent).vertices.length,
          ),
        ]),
        EditorFieldGroup(name: 'Appearance', fields: [
          EditorComponentField(
            name: 'filled',
            label: 'Filled',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as PolygonComponent).filled,
            write: (c, v) => (c as PolygonComponent).filled = v as bool,
          ),
          EditorComponentField(
            name: 'fillColor',
            label: 'Fill',
            kind: EditorFieldKind.shapePaintStyle,
            read: (c) => (c as PolygonComponent).fillStyle,
            write: (c, v) => (c as PolygonComponent).fillStyle =
                ShapePaintStyle(color: v as Color),
          ),
          EditorComponentField(
            name: 'strokeColor',
            label: 'Stroke Color',
            kind: EditorFieldKind.shapePaintStyle,
            read: (c) => (c as PolygonComponent).strokeStyle,
            write: (c, v) => (c as PolygonComponent).strokeStyle =
                ShapePaintStyle(color: v as Color),
          ),
          EditorComponentField(
            name: 'strokeW',
            label: 'Stroke',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
            read: (c) => (c as PolygonComponent).strokeWidth,
            write: (c, v) =>
                (c as PolygonComponent).strokeWidth = (v as num).toDouble(),
          ),
        ]),
      ],
      );
}
