import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

final EditorComponentDescriptor kAudioStreamEditorComponent =
    EditorComponentDescriptor(
      id: 'audio_stream_91f6500b',
      name: 'Audio Stream',
      type: 'AudioStreamComponent',
      group: 'Audio',
      description: 'Streaming audio playback.',
      allowMultiple: false,
      deletable: true,
      componentType: ComponentType.core,
      icon: Icons.graphic_eq,
      accentColor: const Color(0xFFAB47BC),
      factory: () => AudioStreamComponent(path: ''),
      fields: const [],
      fieldGroups: [
        EditorFieldGroup(name: 'Stream', fields: [
          EditorComponentField(
            name: 'streamPath',
            label: 'Path',
            kind: EditorFieldKind.text,
            editable: false,
            read: (c) => (c as AudioStreamComponent).path,
          ),
        ]),
        EditorFieldGroup(name: 'Playback', fields: [
          EditorComponentField(
            name: 'loop',
            label: 'Loop',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as AudioStreamComponent).loop,
            write: (c, v) => (c as AudioStreamComponent).loop = v as bool,
          ),
          EditorComponentField(
            name: 'playOnAdd',
            label: 'Play on Add',
            kind: EditorFieldKind.boolean,
            read: (c) => (c as AudioStreamComponent).playOnAdd,
            write: (c, v) =>
                (c as AudioStreamComponent).playOnAdd = v as bool,
          ),
          EditorComponentField(
            name: 'volume',
            label: 'Volume',
            kind: EditorFieldKind.decimal,
            scrubConfig: const NumberScrubConfig(step: 0.05, fractionDigits: 2, min: 0.0, max: 1.0),
            read: (c) => (c as AudioStreamComponent).volume,
            write: (c, v) => (c as AudioStreamComponent).volume =
                (v as num).toDouble().clamp(0.0, 1.0),
          ),
        ]),
      ],
    );
