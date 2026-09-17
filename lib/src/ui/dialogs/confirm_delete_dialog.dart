import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';

/// Generic destructive-action confirmation dialog — same shape/styling as
/// `scene_actions_dialogs.dart`'s `confirmDeleteScene`, generalized with a
/// caller-supplied [title]/[message] rather than scene-specific wording.
/// Returns `true` if the user confirmed.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(
        title,
        style: const TextStyle(
          color: EditorTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Text(
        message,
        style: const TextStyle(color: EditorTheme.textSecondary, fontSize: 12),
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
            'Delete',
            style: TextStyle(color: EditorTheme.error, fontSize: 11),
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
