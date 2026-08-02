import 'package:flutter/material.dart';

import '../theme/editor_theme.dart';

/// Shows a destructive-action confirmation dialog for deleting [sceneName].
/// Returns `true` if the user confirmed.
Future<bool> confirmDeleteScene(BuildContext context, String sceneName) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: const Text(
        'Delete scene?',
        style: TextStyle(
          color: EditorTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Text(
        'This permanently deletes "$sceneName" and its files '
        '(.level.dart, .data.dart, .scene.json). This cannot be undone.',
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

/// Shows a text-input dialog with live validation, used for both rename and
/// duplicate flows. Returns the entered name, or `null` if cancelled.
Future<String?> promptSceneName(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String initialValue = '',
  required String? Function(String) validate,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _SceneNamePromptDialog(
      title: title,
      actionLabel: actionLabel,
      initialValue: initialValue,
      validate: validate,
    ),
  );
}

class _SceneNamePromptDialog extends StatefulWidget {
  const _SceneNamePromptDialog({
    required this.title,
    required this.actionLabel,
    required this.initialValue,
    required this.validate,
  });

  final String title;
  final String actionLabel;
  final String initialValue;
  final String? Function(String) validate;

  @override
  State<_SceneNamePromptDialog> createState() =>
      _SceneNamePromptDialogState();
}

class _SceneNamePromptDialogState extends State<_SceneNamePromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _error = widget.validate(value.trim()));
  }

  void _submit() {
    final name = _controller.text.trim();
    final error = widget.validate(name);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _error == null && _controller.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(
        widget.title,
        style: const TextStyle(
          color: EditorTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: (_) => canSubmit ? _submit() : null,
              style: const TextStyle(
                color: EditorTheme.textPrimary,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. level_2',
                hintStyle: const TextStyle(color: EditorTheme.primaryMuted),
                filled: true,
                fillColor: EditorTheme.surfaceDark,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: EditorTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: _error != null
                        ? EditorTheme.error
                        : EditorTheme.border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: _error != null
                        ? EditorTheme.error
                        : EditorTheme.primaryActive,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: const TextStyle(
                  color: EditorTheme.errorLight,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
          ),
        ),
        TextButton(
          onPressed: canSubmit ? _submit : null,
          child: Text(
            widget.actionLabel,
            style: const TextStyle(
              color: EditorTheme.primaryMuted,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}
