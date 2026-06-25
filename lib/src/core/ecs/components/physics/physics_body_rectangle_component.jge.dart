// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_import

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_annotations.dart';
import 'package:just_game_engine_editor/src/core/ecs/generator/component_registry.dart';
import 'physics_body_rectangle_component.dart';

final EditorComponentDescriptor _$editorComponentDescriptor0 =
    EditorComponentDescriptor(
      id: 'physics_body_rect_552c5849',
      name: 'Physics Body (Rect)',
      type: 'PhysicsBodyRectangleEditorComponent',
      group: 'Physics',
      description: 'Rigid body with rectangle shape.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      factory: () => PhysicsBodyRectangleEditorComponent(),
      fields: <EditorComponentField>[
        EditorComponentField(
          name: 'categoryBits',
          label: 'Category',
          kind: EditorFieldKind.integer,
          visible: true,
          editable: true,
          includeInJson: true,
          scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
          read: (component) => (component as PhysicsBodyRectangleEditorComponent).categoryBits,
          write: (component, value) {
            (component as PhysicsBodyRectangleEditorComponent).categoryBits = (value as num).toInt();
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
          read: (component) => (component as PhysicsBodyRectangleEditorComponent).collisionMask,
          write: (component, value) {
            (component as PhysicsBodyRectangleEditorComponent).collisionMask = (value as num).toInt();
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
          read: (component) => (component as PhysicsBodyRectangleEditorComponent).drag,
          write: (component, value) {
            (component as PhysicsBodyRectangleEditorComponent).drag = (value as num).toDouble();
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
          read: (component) => (component as PhysicsBodyRectangleEditorComponent).groupIndex,
          write: (component, value) {
            (component as PhysicsBodyRectangleEditorComponent).groupIndex = (value as num).toInt();
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
          read: (component) => (component as PhysicsBodyRectangleEditorComponent).isOneWay,
          write: (component, value) {
            (component as PhysicsBodyRectangleEditorComponent).isOneWay = value as bool;
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
          read: (component) => (component as PhysicsBodyRectangleEditorComponent).isSensor,
          write: (component, value) {
            (component as PhysicsBodyRectangleEditorComponent).isSensor = value as bool;
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
          read: (component) => (component as PhysicsBodyRectangleEditorComponent).isStatic,
          write: (component, value) {
            (component as PhysicsBodyRectangleEditorComponent).isStatic = value as bool;
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
          read: (component) => (component as PhysicsBodyRectangleEditorComponent).layer,
          write: (component, value) {
            (component as PhysicsBodyRectangleEditorComponent).layer = (value as num).toInt();
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
          read: (component) => (component as PhysicsBodyRectangleEditorComponent).maskBits,
          write: (component, value) {
            (component as PhysicsBodyRectangleEditorComponent).maskBits = (value as num).toInt();
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
          read: (component) => (component as PhysicsBodyRectangleEditorComponent).massValue,
          write: (component, value) {
            (component as PhysicsBodyRectangleEditorComponent).massValue = (value as num).toDouble();
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
          read: (component) => (component as PhysicsBodyRectangleEditorComponent).restitution,
          write: (component, value) {
            (component as PhysicsBodyRectangleEditorComponent).restitution = (value as num).toDouble();
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

void registerGeneratedCustomComponents([CustomComponentRegistry? registry]) {
  final target = registry ?? CustomComponentRegistry.instance;
  target.registerAll(_generatedEditorComponentDescriptors);
}
