// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'physics_body_rect_552c5849',
      name: 'Physics Body (Rect)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Rigid body with rectangle shape.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => PhysicsBodyComponent(shape: RectangleShape(50, 50)),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'categoryBits',
          label: 'Category',
          kind: EditorFieldKind.integer,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
          read: (component) => (component as PhysicsBodyComponent).categoryBits,
          write: (component, value) {
            (component as PhysicsBodyComponent).categoryBits = ((value as num).toInt());
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'collisionMask',
          label: 'Coll. Mask',
          kind: EditorFieldKind.integer,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
          read: (component) => (component as PhysicsBodyComponent).collisionMask,
          write: (component, value) {
            (component as PhysicsBodyComponent).collisionMask = ((value as num).toInt());
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'drag',
          label: 'Drag',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0.0),
          read: (component) => (component as PhysicsBodyComponent).drag,
          write: (component, value) {
            (component as PhysicsBodyComponent).drag = ((value as num).toDouble());
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'groupIndex',
          label: 'Group Index',
          kind: EditorFieldKind.integer,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
          read: (component) => (component as PhysicsBodyComponent).groupIndex,
          write: (component, value) {
            (component as PhysicsBodyComponent).groupIndex = ((value as num).toInt());
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'isOneWay',
          label: 'One-way',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as PhysicsBodyComponent).isOneWay,
          write: (component, value) {
            (component as PhysicsBodyComponent).isOneWay = (value as bool);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'isSensor',
          label: 'Sensor',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as PhysicsBodyComponent).isSensor,
          write: (component, value) {
            (component as PhysicsBodyComponent).isSensor = (value as bool);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'isStatic',
          label: 'Static',
          kind: EditorFieldKind.boolean,
          visible: true,
          editable: true,
          includeInJson: true,
          read: (component) => (component as PhysicsBodyComponent).isStatic,
          write: (component, value) {
            (component as PhysicsBodyComponent).isStatic = (value as bool);
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'layer',
          label: 'Layer',
          kind: EditorFieldKind.integer,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
          read: (component) => (component as PhysicsBodyComponent).layer,
          write: (component, value) {
            (component as PhysicsBodyComponent).layer = ((value as num).toInt());
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'maskBits',
          label: 'Mask Bits',
          kind: EditorFieldKind.integer,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
          read: (component) => (component as PhysicsBodyComponent).maskBits,
          write: (component, value) {
            (component as PhysicsBodyComponent).maskBits = ((value as num).toInt());
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'massValue',
          label: 'Mass',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.1, fractionDigits: 2, min: 0.0),
          read: (component) => (component as PhysicsBodyComponent).mass,
          write: (component, value) {
            (component as PhysicsBodyComponent).mass = ((value as num).toDouble());
          },
          enumValues: null,
          enumParser: null,
        ),
        EditorComponentField(
          name: 'restitution',
          label: 'Rest.',
          kind: EditorFieldKind.decimal,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0.0),
          read: (component) => (component as PhysicsBodyComponent).restitution,
          write: (component, value) {
            (component as PhysicsBodyComponent).restitution = ((value as num).toDouble());
          },
          enumValues: null,
          enumParser: null,
        ),
      ],
    );

final List<EditorComponentDescriptor> _generatedEditorComponentDescriptors =
    <EditorComponentDescriptor>[
      _$editorComponentDescriptor0,
    ];

// Registers all descriptors on first import of this file.
// ignore: unused_element
final bool _$registered = () {
  CustomComponentRegistry.instance.registerAll(
    _generatedEditorComponentDescriptors,
  );
  return true;
}();

// Legacy named function kept for backward compatibility.
void registerGeneratedCustomComponents([CustomComponentRegistry? registry]) {
  final target = registry ?? CustomComponentRegistry.instance;
  target.registerAll(_generatedEditorComponentDescriptors);
}
