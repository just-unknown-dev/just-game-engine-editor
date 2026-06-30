import 'package:flutter/material.dart';

import '../../generator/component_registry.dart';
import 'simple_movement_component.dart';

final EditorComponentDescriptor kSimpleMovementEditorComponent =
    EditorComponentDescriptor(
      id: 'simple_movement_78b8f78a',
      name: 'Simple Movement',
      type: 'SimpleMovementComponent',
      group: 'Input',
      description:
          'Moves Transform from keyboard/joystick direction with a speed scalar.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.editor,
      icon: Icons.directions_run,
      accentColor: const Color(0xFFEF5350),
      factory: () => SimpleMovementComponent(),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Movement', fields: [
          EditorComponentField(
            name: 'speed',
            label: 'Speed',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 5.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as SimpleMovementComponent).speed,
            write: (c, v) =>
                (c as SimpleMovementComponent).speed = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'deadZone',
            label: 'Dead Zone',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.01, fractionDigits: 2),
            read: (c) => (c as SimpleMovementComponent).deadZone,
            write: (c, v) =>
                (c as SimpleMovementComponent).deadZone = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'normalizeDiagonal',
            label: 'Normalize Diagonal',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as SimpleMovementComponent).normalizeDiagonal,
            write: (c, v) =>
                (c as SimpleMovementComponent).normalizeDiagonal = v as bool,
          ),
        ]),
        EditorFieldGroup(name: 'Input', fields: [
          EditorComponentField(
            name: 'useKeyboard',
            label: 'Use Keyboard',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as SimpleMovementComponent).useKeyboard,
            write: (c, v) =>
                (c as SimpleMovementComponent).useKeyboard = v as bool,
          ),
          EditorComponentField(
            name: 'useJoystick',
            label: 'Use Joystick',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as SimpleMovementComponent).useJoystick,
            write: (c, v) =>
                (c as SimpleMovementComponent).useJoystick = v as bool,
          ),
        ]),
      ],
    );
