import 'package:flutter/material.dart';

import 'package:just_editor_core/host.dart';

/// Asks before deleting [sceneName]. True when the user went ahead.
///
/// The scene goes to the project's trash, not away for good: the Scenes
/// list offers Undo straight after, and the file stays in
/// `.editor_trash/` until it is emptied.
Future<bool> confirmDeleteScene(BuildContext context, String sceneName) =>
    showEditorConfirm(
      context,
      title: 'Delete scene?',
      message:
          'This deletes "$sceneName" '
          '(assets/scenes/$sceneName.scene.json) and takes it out of the '
          'play order. The file goes to ${AssetIndex.trashFolder}/ in the '
          'project; Undo, straight after, brings it back.',
      confirmLabel: 'Delete',
    );

/// Shows a text-input dialog with live validation, used for both rename and
/// duplicate flows. Returns the entered name, or `null` if cancelled.
Future<String?> promptSceneName(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String initialValue = '',
  required String? Function(String) validate,
  String hint = 'e.g. level_2',
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => EditorLook(
      child: _SceneNamePromptDialog(
        title: title,
        actionLabel: actionLabel,
        initialValue: initialValue,
        validate: validate,
        hint: hint,
      ),
    ),
  );
}

class _SceneNamePromptDialog extends StatefulWidget {
  const _SceneNamePromptDialog({
    required this.title,
    required this.actionLabel,
    required this.initialValue,
    required this.validate,
    this.hint = 'e.g. level_2',
  });

  final String title;
  final String actionLabel;
  final String initialValue;
  final String? Function(String) validate;
  final String hint;

  @override
  State<_SceneNamePromptDialog> createState() => _SceneNamePromptDialogState();
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
    return EditorAlert(
      title: widget.title,
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
              cursorColor: EditorTheme.primaryBright,
              style: TextStyle(color: EditorTheme.textPrimary, fontSize: 13),
              decoration: editorFieldDecoration(
                hint: widget.hint,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: TextStyle(color: EditorTheme.errorLight, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
      actions: [
        EditorButton(
          label: 'Cancel',
          kind: EditorButtonKind.ghost,
          onPressed: () => Navigator.pop(context),
        ),
        EditorButton(
          label: widget.actionLabel,
          kind: EditorButtonKind.primary,
          onPressed: canSubmit ? _submit : null,
        ),
      ],
    );
  }
}
