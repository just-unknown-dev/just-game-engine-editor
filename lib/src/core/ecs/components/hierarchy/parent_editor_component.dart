import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class ParentEditorComponent extends EditorComponent {
  ParentEditorComponent()
    : super(
      id: 'parent_a33bbdfb',
      name: 'Parent',
      type: 'ParentComponent',
      group: 'Hierarchy',
      description: 'Attaches this entity to a parent.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.link,
      accentColor: const Color(0xFF26A69A),
      factory: () => ParentComponent(),
      fields: const [],
      );
}
