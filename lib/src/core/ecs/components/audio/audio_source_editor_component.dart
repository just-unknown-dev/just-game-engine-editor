import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kAudioSourceEditorComponent =
    EditorComponentDescriptor(
      id: 'audio_source_111e2e48',
      name: 'Audio Source',
      type: 'AudioSourceComponent',
      group: 'Audio',
      description: 'One-shot audio clip playback.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.volume_up,
      accentColor: const Color(0xFFAB47BC),
      factory: () => AudioSourceComponent(clipPath: ''),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Clip', fields: [
          EditorComponentField(
            name: 'path',
            label: 'Path',
            kind: EditorFieldKind.text,
            editable: false,
            read: (c) => (c as AudioSourceComponent).clipPath,
          ),
        ]),
        EditorFieldGroup(name: 'Playback', fields: [
          EditorComponentField(
            name: 'loop',
            label: 'Loop',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as AudioSourceComponent).loop,
            write: (c, v) => (c as AudioSourceComponent).loop = v as bool,
          ),
          EditorComponentField(
            name: 'playOnAdd',
            label: 'Play on Add',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as AudioSourceComponent).playOnAdd,
            write: (c, v) =>
                (c as AudioSourceComponent).playOnAdd = v as bool,
          ),
          EditorComponentField(
            name: 'volume',
            label: 'Volume',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0.0, max: 1.0),
            read: (c) => (c as AudioSourceComponent).volume,
            write: (c, v) => (c as AudioSourceComponent).volume =
                (v as num).toDouble().clamp(0.0, 1.0),
          ),
          EditorComponentField(
            name: 'pitch',
            label: 'Pitch',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0.0),
            read: (c) => (c as AudioSourceComponent).pitch,
            write: (c, v) =>
                (c as AudioSourceComponent).pitch = (v as num).toDouble(),
          ),
        ]),
      ],
    );
