import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kTransformEditorComponent =
    EditorComponentDescriptor(
      id: 'transform_5b740729',
      name: 'Transform',
      type: 'TransformComponent',
      group: 'Core',
      description: 'Position, rotation, and scale.',
      allowMultiple: false,
      deletable: false,
      componentType: ComponentType.core,
      icon: Icons.open_with,
      accentColor: const Color(0xFF607D8B),
      factory: () => TransformComponent(),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Position', fields: [
          EditorComponentField(
            name: 'posX',
            label: 'X',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
            read: (c) => (c as TransformComponent).position.x,
            write: (c, v) {
              final t = c as TransformComponent;
              t.position = Vector3((v as num).toDouble(), t.position.y, t.position.z);
            },
          ),
          EditorComponentField(
            name: 'posY',
            label: 'Y',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
            read: (c) => (c as TransformComponent).position.y,
            write: (c, v) {
              final t = c as TransformComponent;
              t.position = Vector3(t.position.x, (v as num).toDouble(), t.position.z);
            },
          ),
        ]),
        EditorFieldGroup(name: 'Rotation', fields: [
          EditorComponentField(
            name: 'rotation',
            label: 'Angle°',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1),
            read: (c) => (c as TransformComponent).rotation * 180 / math.pi,
            write: (c, v) =>
                (c as TransformComponent).rotation = (v as num).toDouble() * math.pi / 180,
          ),
        ]),
        EditorFieldGroup(name: 'Scale', fields: [
          EditorComponentField(
            name: 'scaleX',
            label: 'SX',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 3),
            read: (c) => (c as TransformComponent).scale.x,
            write: (c, v) {
              final t = c as TransformComponent;
              t.scale = Vector3((v as num).toDouble(), t.scale.y, t.scale.z);
            },
          ),
          EditorComponentField(
            name: 'scaleY',
            label: 'SY',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 3),
            read: (c) => (c as TransformComponent).scale.y,
            write: (c, v) {
              final t = c as TransformComponent;
              t.scale = Vector3(t.scale.x, (v as num).toDouble(), t.scale.z);
            },
          ),
        ]),
      ],
    );
