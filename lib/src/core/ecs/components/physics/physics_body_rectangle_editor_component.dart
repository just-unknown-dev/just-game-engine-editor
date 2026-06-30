import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

// Shared fields used by all PhysicsBodyComponent variants.
// Register this descriptor LAST among physics bodies so the inspector
// uses it for all runtime PhysicsBodyComponent instances.
class PhysicsBodyRectEditorComponent extends EditorComponent {
  PhysicsBodyRectEditorComponent()
    : super(
      id: 'physics_body_rect_552c5849',
      name: 'Physics Body (Rect)',
      type: 'PhysicsBodyComponent',
      group: 'Physics',
      description: 'Rigid body with rectangle shape.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.square_outlined,
      accentColor: const Color(0xFFFF7043),
      factory: () => PhysicsBodyComponent(
        shape: RectangleShape(64, 40),
        mass: 1.2,
        isStatic: false,
        restitution: 0.4,
        drag: 0.98,
      ),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Body', fields: [
          EditorComponentField(
            name: 'isStatic',
            label: 'Static',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as PhysicsBodyComponent).isStatic,
            write: (c, v) =>
                (c as PhysicsBodyComponent).isStatic = v as bool,
          ),
          EditorComponentField(
            name: 'isSensor',
            label: 'Sensor',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as PhysicsBodyComponent).isSensor,
            write: (c, v) =>
                (c as PhysicsBodyComponent).isSensor = v as bool,
          ),
          EditorComponentField(
            name: 'isOneWay',
            label: 'One-way',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as PhysicsBodyComponent).isOneWay,
            write: (c, v) =>
                (c as PhysicsBodyComponent).isOneWay = v as bool,
          ),
          EditorComponentField(
            name: 'massValue',
            label: 'Mass',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.1, fractionDigits: 2, min: 0.0),
            read: (c) => (c as PhysicsBodyComponent).mass,
            write: (c, v) =>
                (c as PhysicsBodyComponent).mass = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'drag',
            label: 'Drag',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0.0),
            read: (c) => (c as PhysicsBodyComponent).drag,
            write: (c, v) =>
                (c as PhysicsBodyComponent).drag = (v as num).toDouble(),
          ),
          EditorComponentField(
            name: 'restitution',
            label: 'Rest.',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0.0),
            read: (c) => (c as PhysicsBodyComponent).restitution,
            write: (c, v) =>
                (c as PhysicsBodyComponent).restitution = (v as num).toDouble(),
          ),
        ]),
        EditorFieldGroup(name: 'Collision', fields: [
          EditorComponentField(
            name: 'categoryBits',
            label: 'Category',
            kind: EditorFieldKind.integer,
            scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
            read: (c) => (c as PhysicsBodyComponent).categoryBits,
            write: (c, v) =>
                (c as PhysicsBodyComponent).categoryBits = (v as num).toInt(),
          ),
          EditorComponentField(
            name: 'maskBits',
            label: 'Mask Bits',
            kind: EditorFieldKind.integer,
            scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
            read: (c) => (c as PhysicsBodyComponent).maskBits,
            write: (c, v) =>
                (c as PhysicsBodyComponent).maskBits = (v as num).toInt(),
          ),
          EditorComponentField(
            name: 'collisionMask',
            label: 'Coll. Mask',
            kind: EditorFieldKind.integer,
            scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
            read: (c) => (c as PhysicsBodyComponent).collisionMask,
            write: (c, v) =>
                (c as PhysicsBodyComponent).collisionMask = (v as num).toInt(),
          ),
          EditorComponentField(
            name: 'groupIndex',
            label: 'Group Index',
            kind: EditorFieldKind.integer,
            scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
            read: (c) => (c as PhysicsBodyComponent).groupIndex,
            write: (c, v) =>
                (c as PhysicsBodyComponent).groupIndex = (v as num).toInt(),
          ),
          EditorComponentField(
            name: 'layer',
            label: 'Layer',
            kind: EditorFieldKind.integer,
            scrubConfig: const NumberScrubConfig(step: 1.0, integer: true),
            read: (c) => (c as PhysicsBodyComponent).layer,
            write: (c, v) =>
                (c as PhysicsBodyComponent).layer = (v as num).toInt(),
          ),
        ]),
      ],
      );
}
