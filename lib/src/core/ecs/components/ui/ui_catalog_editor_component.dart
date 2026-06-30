import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kUICatalogEditorComponent =
    EditorComponentDescriptor(
      id: 'ui_6018ae16',
      name: 'UI',
      type: 'UIComponent',
      group: 'UI',
      description: 'Base UI layout container.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.dashboard_outlined,
      accentColor: const Color(0xFF5C6BC0),
      factory: () => UIComponent(size: const Size(100, 40)),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Size', fields: [
          EditorComponentField(
            name: 'w',
            label: 'W',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as UIComponent).size.width,
            write: (c, v) {
              final ui = c as UIComponent;
              ui.size = Size((v as num).toDouble(), ui.size.height);
            },
          ),
          EditorComponentField(
            name: 'h',
            label: 'H',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as UIComponent).size.height,
            write: (c, v) {
              final ui = c as UIComponent;
              ui.size = Size(ui.size.width, (v as num).toDouble());
            },
          ),
        ]),
        EditorFieldGroup(name: 'State', fields: [
          EditorComponentField(
            name: 'visible',
            label: 'Visible',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as UIComponent).visible,
            write: (c, v) => (c as UIComponent).visible = v as bool,
          ),
          EditorComponentField(
            name: 'enabled',
            label: 'Enabled',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as UIComponent).enabled,
            write: (c, v) => (c as UIComponent).enabled = v as bool,
          ),
        ]),
      ],
    );
