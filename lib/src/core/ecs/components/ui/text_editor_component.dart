import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kTextEditorComponent =
    EditorComponentDescriptor(
      id: 'text_effcff19',
      name: 'Text',
      type: 'TextComponent',
      group: 'UI',
      description: 'Renders a text label.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.text_fields,
      accentColor: const Color(0xFF5C6BC0),
      factory: () => TextComponent(text: 'Text', size: const Size(200, 40)),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Size', fields: [
          EditorComponentField(
            name: 'w',
            label: 'W',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as TextComponent).size.width,
            write: (c, v) {
              final t = c as TextComponent;
              t.size = Size((v as num).toDouble(), t.size.height);
            },
          ),
          EditorComponentField(
            name: 'h',
            label: 'H',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as TextComponent).size.height,
            write: (c, v) {
              final t = c as TextComponent;
              t.size = Size(t.size.width, (v as num).toDouble());
            },
          ),
        ]),
        EditorFieldGroup(name: 'Content', fields: [
          EditorComponentField(
            name: 'textValue',
            label: 'Text',
            kind: EditorFieldKind.text,
            read: (c) => (c as TextComponent).text,
            write: (c, v) => (c as TextComponent).text = v as String,
          ),
        ]),
      ],
    );
