import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../generator/component_registry.dart';

class AnimatedSpriteEditorComponent extends EditorComponent {
  AnimatedSpriteEditorComponent()
    : super(
        id: 'animated_sprite_4f8a2b1c',
        name: 'Animated Sprite',
        type: 'AnimatedSpriteComponent',
        group: 'Rendering',
        description: 'Sprite-sheet animation with named clips and keyframes.',
        allowMultiple: false,
        deletable: true,
        componentType: ComponentType.core,
        icon: Icons.movie_filter_rounded,
        accentColor: const Color(0xFF7DE6B1),
        factory: () => AnimatedSpriteComponent(),
        fields: const [],
        fieldGroups: [
          EditorFieldGroup(name: 'Sprite Sheet', fields: [
            EditorComponentField(
              name: 'spritePath',
              label: 'Sprite',
              kind: EditorFieldKind.assetRef,
              read: (c) => (c as AnimatedSpriteComponent).spritePath,
              write: (c, v) =>
                  (c as AnimatedSpriteComponent).spritePath = v as String,
            ),
            EditorComponentField(
              name: 'jsonPath',
              label: 'Animation JSON',
              kind: EditorFieldKind.assetRef,
              fileExtensions: const ['json'],
              read: (c) => (c as AnimatedSpriteComponent).jsonPath,
              write: (c, v) {
                final asc = c as AnimatedSpriteComponent;
                asc.jsonPath = v as String;
                asc.initialized = false;
              },
              generateTemplate: (c) async {
                final asc = c as AnimatedSpriteComponent;
                final spritePath = asc.spritePath.trim();
                if (spritePath.isEmpty) return null;

                // Derive output path: same dir, <spriteName>_data.json
                final normalized = spritePath.replaceAll(r'\', '/');
                final segments = normalized.split('/');
                final filename = segments.last;
                final nameWithoutExt = filename.contains('.')
                    ? filename.substring(0, filename.lastIndexOf('.'))
                    : filename;
                final dir = segments.sublist(0, segments.length - 1).join('/');
                final outputPath = '$dir/${nameWithoutExt}_data.json';

                final fw = asc.frameWidth > 0 ? asc.frameWidth : 64;
                final fh = asc.frameHeight > 0 ? asc.frameHeight : 64;
                final cols = asc.columns > 0 ? asc.columns : 4;
                final rows = asc.rows > 0 ? asc.rows : 4;

                const defaultNames = [
                  'idle', 'walk', 'run', 'jump',
                  'fall', 'attack', 'hurt', 'die',
                ];
                final clips = <String, dynamic>{};
                for (int r = 0; r < rows; r++) {
                  final name =
                      r < defaultNames.length ? defaultNames[r] : 'clip_$r';
                  clips[name] = {
                    'row': r,
                    'fps': 12,
                    'loop': r < 3,
                  };
                }

                final template = <String, dynamic>{
                  'meta': {
                    'frameWidth': fw,
                    'frameHeight': fh,
                    'columns': cols,
                    'rows': rows,
                  },
                  'clips': clips,
                };

                try {
                  final base =
                      Directory.current.path.replaceAll(r'\', '/');
                  final file = File('$base/$outputPath');
                  await file.parent.create(recursive: true);
                  await file.writeAsString(
                    const JsonEncoder.withIndent('  ').convert(template),
                  );
                  return outputPath;
                } catch (_) {
                  return null;
                }
              },
            ),
            EditorComponentField(
              name: 'frameWidth',
              label: 'Frame W',
              kind: EditorFieldKind.integer,
              scrubConfig: const NumberScrubConfig(step: 1, min: 1, integer: true),
              read: (c) => (c as AnimatedSpriteComponent).frameWidth,
              write: (c, v) =>
                  (c as AnimatedSpriteComponent).frameWidth = (v as num).toInt(),
            ),
            EditorComponentField(
              name: 'frameHeight',
              label: 'Frame H',
              kind: EditorFieldKind.integer,
              scrubConfig: const NumberScrubConfig(step: 1, min: 1, integer: true),
              read: (c) => (c as AnimatedSpriteComponent).frameHeight,
              write: (c, v) =>
                  (c as AnimatedSpriteComponent).frameHeight =
                      (v as num).toInt(),
            ),
            EditorComponentField(
              name: 'columns',
              label: 'Columns',
              kind: EditorFieldKind.integer,
              scrubConfig: const NumberScrubConfig(step: 1, min: 1, integer: true),
              read: (c) => (c as AnimatedSpriteComponent).columns,
              write: (c, v) =>
                  (c as AnimatedSpriteComponent).columns = (v as num).toInt(),
            ),
            EditorComponentField(
              name: 'rows',
              label: 'Rows',
              kind: EditorFieldKind.integer,
              scrubConfig: const NumberScrubConfig(step: 1, min: 1, integer: true),
              read: (c) => (c as AnimatedSpriteComponent).rows,
              write: (c, v) =>
                  (c as AnimatedSpriteComponent).rows = (v as num).toInt(),
            ),
          ]),
          EditorFieldGroup(name: 'Playback', fields: [
            EditorComponentField(
              name: 'activeClip',
              label: 'Active Clip',
              kind: EditorFieldKind.text,
              read: (c) => (c as AnimatedSpriteComponent).activeClip,
              write: (c, v) =>
                  (c as AnimatedSpriteComponent).activeClip = v as String,
            ),
            EditorComponentField(
              name: 'defaultFps',
              label: 'FPS',
              kind: EditorFieldKind.decimal,
              scrubConfig:
                  const NumberScrubConfig(step: 0.5, min: 0.1, max: 120),
              read: (c) => (c as AnimatedSpriteComponent).defaultFps,
              write: (c, v) =>
                  (c as AnimatedSpriteComponent).defaultFps =
                      (v as num).toDouble(),
            ),
            EditorComponentField(
              name: 'loop',
              label: 'Loop',
              kind: EditorFieldKind.boolean,
              read: (c) => (c as AnimatedSpriteComponent).loop,
              write: (c, v) =>
                  (c as AnimatedSpriteComponent).loop = v as bool,
            ),
            EditorComponentField(
              name: 'playOnStart',
              label: 'Play on Start',
              kind: EditorFieldKind.boolean,
              read: (c) => (c as AnimatedSpriteComponent).playOnStart,
              write: (c, v) =>
                  (c as AnimatedSpriteComponent).playOnStart = v as bool,
            ),
          ]),
          // clips is hidden from the inspector but included in scene JSON
          EditorFieldGroup(name: '_internal', fields: [
            EditorComponentField(
              name: 'clips',
              label: 'Clips',
              kind: EditorFieldKind.map,
              visible: false,
              editable: false,
              includeInJson: true,
              read: (c) => (c as AnimatedSpriteComponent).clipsToJson(),
              write: (c, v) =>
                  (c as AnimatedSpriteComponent).clipsFromJson(v),
            ),
          ]),
        ],
      );
}
