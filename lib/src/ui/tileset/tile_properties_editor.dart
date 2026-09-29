import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../core/constants/editor_constants.dart';
import '../inspector/field_rows.dart';
import '../inspector/property_table_editor.dart';
import 'tileset_session.dart';

/// What the selected tiles say: their class, how likely a random brush is
/// to pick them, and properties a game reads (`damage`, `slippery`).
///
/// With several tiles selected, the fields show the lowest one and a
/// change goes to all of them.
class TilePropertiesEditor extends StatelessWidget {
  const TilePropertiesEditor({super.key, required this.session});

  final TilesetSession session;

  TilesetSession get s => session;

  @override
  Widget build(BuildContext context) {
    final id = s.primary;
    if (id == null) return const SizedBox.shrink();
    final def = s.data.tile(id);
    final props = def?.properties ?? TileProperties();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          label: 'Class',
          child: MiniTextField(
            value: def?.className ?? '',
            hint: 'e.g. spikes',
            onSubmitted: (v) => s.setClass(v.trim()),
          ),
        ),
        _Row(
          label: 'Probability',
          child: MiniNumberField(
            value: def?.probability ?? 1,
            fractionDigits: 2,
            onSubmitted: s.setProbability,
          ),
        ),
        const SizedBox(height: 6),
        PropertyTableEditor(
          properties: props,
          onSet: s.setProperty,
          onRemove: s.removeProperty,
          onInvalid: s.say,
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: EditorTheme.textSecondary),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}
