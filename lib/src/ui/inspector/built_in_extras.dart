import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'component_extras.dart';
import 'field_rows.dart';

/// What the editor itself adds to built-in components beyond their fields.
abstract final class BuiltInExtras {
  static List<ComponentEditorExtras> get all => [
    ComponentEditorExtras(
      type: 'AnimatedSpriteComponent',
      summary: (c) {
        final clip = (c as jge.AnimatedSpriteComponent).activeClip;
        return clip.isEmpty ? '—' : clip;
      },
      // The JSON picker gains a "generate" button that writes a template
      // sheet description next to the sprite.
      fieldEditors: {
        'jsonPath': (c) => AssetRefEditorRow(
          label: c.label,
          value: c.value as String? ?? '',
          extensions: c.hint.fileExtensions ?? const ['json'],
          onChanged: c.onChanged,
          onGenerate: () => generateAnimationTemplate(
            c.component as jge.AnimatedSpriteComponent,
          ),
        ),
      },
    ),
  ];

  /// Writes `<sprite>_data.json` beside the sprite sheet with one clip per
  /// row, and returns its path, or null when there is no sprite yet or the
  /// write fails.
  static Future<String?> generateAnimationTemplate(
    jge.AnimatedSpriteComponent asc,
  ) async {
    final spritePath = asc.spritePath.trim();
    if (spritePath.isEmpty) return null;

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
      'idle',
      'walk',
      'run',
      'jump',
      'fall',
      'attack',
      'hurt',
      'die',
    ];
    final clips = <String, dynamic>{};
    for (var r = 0; r < rows; r++) {
      final name = r < defaultNames.length ? defaultNames[r] : 'clip_$r';
      clips[name] = {'row': r, 'fps': 12, 'loop': r < 3};
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
      final base = Directory.current.path.replaceAll(r'\', '/');
      final file = File('$base/$outputPath');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(template),
      );
      return outputPath;
    } catch (_) {
      return null;
    }
  }
}
