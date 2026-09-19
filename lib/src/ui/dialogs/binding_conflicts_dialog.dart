import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';

/// Warns that saving would leave two or more actions bound to the same
/// physical input (see `findBindingConflicts` in `just_inputs`) — each
/// [conflictDescriptions] entry is one already-formatted line, e.g.
/// `'R is bound to both Reload and Skill Spit (player)'`. Returns `true` if
/// the user chose to save anyway, `false`/`null` if they cancelled.
Future<bool> confirmSaveWithBindingConflicts(
  BuildContext context, {
  required List<String> conflictDescriptions,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.warning_amber_rounded,
            color: EditorTheme.warning,
            size: 16,
          ),
          SizedBox(width: 8),
          Text(
            'Conflicting Bindings',
            style: TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The same input triggers more than one action:',
              style: TextStyle(color: EditorTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            for (final line in conflictDescriptions)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• $line',
                  style: const TextStyle(
                    color: EditorTheme.warning,
                    fontSize: 11.5,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            'Save Anyway',
            style: TextStyle(color: EditorTheme.primaryMuted, fontSize: 11),
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
