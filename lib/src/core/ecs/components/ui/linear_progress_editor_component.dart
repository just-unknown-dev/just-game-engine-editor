import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class LinearProgressEditorComponent extends EditorComponent {
  LinearProgressEditorComponent()
    : super(
      id: 'linear_progress_006125a9',
      name: 'Linear Progress',
      type: 'LinearProgressComponent',
      group: 'UI',
      description: 'Horizontal progress bar.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.linear_scale,
      accentColor: const Color(0xFF5C6BC0),
      factory: () => LinearProgressComponent(size: const Size(200, 20)),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Size', fields: [
          EditorComponentField(
            name: 'w',
            label: 'W',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as LinearProgressComponent).size.width,
            write: (c, v) {
              final p = c as LinearProgressComponent;
              p.size = Size((v as num).toDouble(), p.size.height);
            },
          ),
          EditorComponentField(
            name: 'h',
            label: 'H',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 1.0, fractionDigits: 1, min: 0.0),
            read: (c) => (c as LinearProgressComponent).size.height,
            write: (c, v) {
              final p = c as LinearProgressComponent;
              p.size = Size(p.size.width, (v as num).toDouble());
            },
          ),
        ]),
        EditorFieldGroup(name: 'Value', fields: [
          EditorComponentField(
            name: 'progressValue',
            label: 'Progress',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.02, fractionDigits: 2, min: 0.0, max: 1.0),
            read: (c) => (c as LinearProgressComponent).progress,
            write: (c, v) =>
                (c as LinearProgressComponent).setProgress((v as num).toDouble()),
          ),
        ]),
      ],
      );
}
