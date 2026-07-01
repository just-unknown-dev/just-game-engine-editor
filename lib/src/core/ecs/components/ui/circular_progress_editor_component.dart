import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class CircularProgressEditorComponent extends EditorComponent {
  CircularProgressEditorComponent()
    : super(
      id: 'circular_progress_d287c579',
      name: 'Circular Progress',
      type: 'CircularProgressComponent',
      group: 'UI',
      description: 'Radial progress indicator.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.donut_large,
      accentColor: const Color(0xFF5C6BC0),
      factory: () => CircularProgressComponent(radius: 30),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Size', fields: [
          EditorComponentField(
            name: 'radius',
            label: 'Radius',
            kind: EditorFieldKind.decimal,
            editable: false,
            scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1, min: 0.0),
            read: (c) => (c as CircularProgressComponent).size.width / 2,
          ),
        ]),
        EditorFieldGroup(name: 'Value', fields: [
          EditorComponentField(
            name: 'progressValue',
            label: 'Progress',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.02, fractionDigits: 2, min: 0.0, max: 1.0),
            read: (c) => (c as CircularProgressComponent).progress,
            write: (c, v) =>
                (c as CircularProgressComponent).setProgress((v as num).toDouble()),
          ),
        ]),
      ],
      );
}
