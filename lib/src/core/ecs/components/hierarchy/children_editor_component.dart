import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kChildrenEditorComponent =
    EditorComponentDescriptor(
      id: 'children_b35c783e',
      name: 'Children',
      type: 'ChildrenComponent',
      group: 'Hierarchy',
      description: 'Groups child entities.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.account_tree,
      accentColor: const Color(0xFF26A69A),
      factory: () => ChildrenComponent(),
      fields: const [],
    );
