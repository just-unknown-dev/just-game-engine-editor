// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'simple_movement_component.dart';

final CustomComponentDescriptor
_$customComponentDescriptor0 = CustomComponentDescriptor(
  id: 'simplemovementcomponent_1d5c76e4',
  name: 'SimpleMovementComponent',
  type: 'SimpleMovementComponent',
  group: 'Input',
  description:
      'Moves Transform from keyboard/joystick direction with a speed scalar.',
  allowMultiple: false,
  factory: () => SimpleMovementComponent(),
  fields: <EditorComponentField>[
    EditorComponentField(
      name: 'deadZone',
      label: 'Dead Zone',
      kind: EditorFieldKind.decimal,
      visible: true,
      editable: true,
      includeInJson: true,
      read: (component) => (component as SimpleMovementComponent).deadZone,
      write: (component, value) {
        (component as SimpleMovementComponent).deadZone = (value as num)
            .toDouble();
      },
      enumValues: null,
      enumParser: null,
    ),
    EditorComponentField(
      name: 'lastDirection',
      label: 'Last Direction',
      kind: EditorFieldKind.offset,
      visible: true,
      editable: true,
      includeInJson: true,
      read: (component) => (component as SimpleMovementComponent).lastDirection,
      write: (component, value) {
        (component as SimpleMovementComponent).lastDirection = value as Offset;
      },
      enumValues: null,
      enumParser: null,
    ),
    EditorComponentField(
      name: 'normalizeDiagonal',
      label: 'Normalize Diagonal',
      kind: EditorFieldKind.boolean,
      visible: true,
      editable: true,
      includeInJson: true,
      read: (component) =>
          (component as SimpleMovementComponent).normalizeDiagonal,
      write: (component, value) {
        (component as SimpleMovementComponent).normalizeDiagonal =
            value as bool;
      },
      enumValues: null,
      enumParser: null,
    ),
    EditorComponentField(
      name: 'speed',
      label: 'Speed',
      kind: EditorFieldKind.decimal,
      visible: true,
      editable: true,
      includeInJson: true,
      read: (component) => (component as SimpleMovementComponent).speed,
      write: (component, value) {
        (component as SimpleMovementComponent).speed = (value as num)
            .toDouble();
      },
      enumValues: null,
      enumParser: null,
    ),
    EditorComponentField(
      name: 'useJoystick',
      label: 'Use Joystick',
      kind: EditorFieldKind.boolean,
      visible: true,
      editable: true,
      includeInJson: true,
      read: (component) => (component as SimpleMovementComponent).useJoystick,
      write: (component, value) {
        (component as SimpleMovementComponent).useJoystick = value as bool;
      },
      enumValues: null,
      enumParser: null,
    ),
    EditorComponentField(
      name: 'useKeyboard',
      label: 'Use Keyboard',
      kind: EditorFieldKind.boolean,
      visible: true,
      editable: true,
      includeInJson: true,
      read: (component) => (component as SimpleMovementComponent).useKeyboard,
      write: (component, value) {
        (component as SimpleMovementComponent).useKeyboard = value as bool;
      },
      enumValues: null,
      enumParser: null,
    ),
  ],
);

final List<CustomComponentDescriptor> _generatedCustomComponentDescriptors =
    <CustomComponentDescriptor>[_$customComponentDescriptor0];

void registerGeneratedCustomComponents([CustomComponentRegistry? registry]) {
  final target = registry ?? CustomComponentRegistry.instance;
  target.registerAll(_generatedCustomComponentDescriptors);
}
