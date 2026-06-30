import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kButtonEditorComponent =
    EditorComponentDescriptor(
      id: 'button_388d5c40',
      name: 'Button',
      type: 'ButtonComponent',
      group: 'UI',
      description: 'Interactive button widget.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.smart_button,
      accentColor: const Color(0xFF5C6BC0),
      factory: () => ButtonComponent(text: 'Button', size: const Size(120, 40)),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Size', fields: [
          EditorComponentField(
            name: 'w',
            label: 'W',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as ButtonComponent).size.width,
            write: (c, v) {
              final b = c as ButtonComponent;
              b.size = Size((v as num).toDouble(), b.size.height);
            },
          ),
          EditorComponentField(
            name: 'h',
            label: 'H',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as ButtonComponent).size.height,
            write: (c, v) {
              final b = c as ButtonComponent;
              b.size = Size(b.size.width, (v as num).toDouble());
            },
          ),
        ]),
        EditorFieldGroup(name: 'Text', fields: [
          EditorComponentField(
            name: 'label',
            label: 'Label',
            kind: EditorFieldKind.text,
            read: (c) => (c as ButtonComponent).text,
            write: (c, v) => (c as ButtonComponent).text = v as String,
          ),
        ]),
      ],
    );
