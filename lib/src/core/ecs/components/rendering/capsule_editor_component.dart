import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class CapsuleEditorComponent extends EditorComponent {
  CapsuleEditorComponent()
    : super(
      id: 'capsule_2de9600b',
      name: 'Capsule',
      type: 'CapsuleComponent',
      group: 'Rendering',
      description: 'Filled or stroked capsule.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.crop_portrait,
      accentColor: const Color(0xFF42A5F5),
      factory: () => CapsuleComponent(width: 32, height: 64),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Size', fields: [
          EditorComponentField(
            name: 'w',
            label: 'W',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as CapsuleComponent).width,
            write: (c, v) =>
                (c as CapsuleComponent).width = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'h',
            label: 'H',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as CapsuleComponent).height,
            write: (c, v) =>
                (c as CapsuleComponent).height = (v as num).toDouble(),
          ),
        ]),
        EditorFieldGroup(name: 'Appearance', fields: [
          EditorComponentField(
            name: 'filled',
            label: 'Filled',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as CapsuleComponent).filled,
            write: (c, v) => (c as CapsuleComponent).filled = v as bool,
          ),
          EditorComponentField(
            name: 'fillColor',
            label: 'Fill',
            kind: EditorFieldKind.shapePaintStyle,
            read: (c) => (c as CapsuleComponent).fillStyle,
            write: (c, v) =>
                (c as CapsuleComponent).fillStyle = v as ShapePaintStyle,
          ),
          EditorComponentField(
            name: 'strokeColor',
            label: 'Stroke',
            kind: EditorFieldKind.shapePaintStyle,
            read: (c) => (c as CapsuleComponent).strokeStyle,
            write: (c, v) =>
                (c as CapsuleComponent).strokeStyle = v as ShapePaintStyle,
          ),
        ]),
      ],
      );
}
