import 'package:flutter/material.dart';

import '../widgets/scrubbable_number_field.dart';
import 'field_rows.dart';

/// Space around something, as four numbers on one row.
class EdgeInsetsEditorRow extends StatelessWidget {
  const EdgeInsetsEditorRow({
    super.key,
    required this.label,
    required this.insets,
    required this.onChanged,
  });

  final String label;
  final EdgeInsets insets;
  final ValueChanged<EdgeInsets> onChanged;

  @override
  Widget build(BuildContext context) => AxesFieldRow(
    label: label,
    axes: const ['L', 'T', 'R', 'B'],
    values: [insets.left, insets.top, insets.right, insets.bottom],
    scrubConfig: const NumberScrubConfig(step: 1, fractionDigits: 0),
    onChanged: (next) =>
        onChanged(EdgeInsets.fromLTRB(next[0], next[1], next[2], next[3])),
  );
}
