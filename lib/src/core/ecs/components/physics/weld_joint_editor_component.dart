import 'package:flutter/material.dart';

import '../../generator/component_registry.dart';
import 'weld_joint_component.dart';

class WeldJointEditorComponent extends EditorComponent {
  WeldJointEditorComponent()
    : super(
      id: 'weld_joint_8369677a',
      name: 'Weld Joint',
      type: 'WeldJointComponent',
      group: 'Physics',
      description: 'Rigid weld joint linking this entity to targetEntityName.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.editor,
      icon: Icons.hub_outlined,
      accentColor: const Color(0xFFFF7043),
      factory: () => WeldJointComponent(),
      fields: [
        EditorComponentField(
          name: 'targetEntityName',
          label: 'Target Name',
          kind: EditorFieldKind.text,
          read: (c) => (c as WeldJointComponent).targetEntityName,
          write: (c, v) =>
              (c as WeldJointComponent).targetEntityName = (v as String).trim(),
        ),
        EditorComponentField(
          name: 'collideConnected',
          label: 'Collide Connected',
          kind: EditorFieldKind.boolean,
          read: (c) => (c as WeldJointComponent).collideConnected,
          write: (c, v) =>
              (c as WeldJointComponent).collideConnected = v as bool,
        ),
      ],
      );
}
