import 'package:flutter/material.dart';
import 'package:just_inputs/just_inputs.dart';

import '../../core/constants/editor_constants.dart';

/// Prompts for a new action's name and [ActionType] (Button vs. Vector 2) —
/// same dialog shell/styling as `scene_actions_dialogs.dart`'s
/// `promptSceneName`, extended with a type choice since a new action needs
/// both. Returns `(name, type)`, or `null` if cancelled.
Future<(String, ActionType)?> promptNewAction(
  BuildContext context, {
  required String? Function(String) validateName,
}) {
  return showDialog<(String, ActionType)>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _NewActionDialog(validateName: validateName),
  );
}

class _NewActionDialog extends StatefulWidget {
  const _NewActionDialog({required this.validateName});

  final String? Function(String) validateName;

  @override
  State<_NewActionDialog> createState() => _NewActionDialogState();
}

class _NewActionDialogState extends State<_NewActionDialog> {
  late final TextEditingController _controller = TextEditingController();
  String? _error;
  ActionType _type = ActionType.button;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _error = widget.validateName(value.trim()));
  }

  void _submit() {
    final name = _controller.text.trim();
    final error = widget.validateName(name);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, (name, _type));
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _error == null && _controller.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: const Text(
        'New Action',
        style: TextStyle(
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
                hintText: 'e.g. dash',
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
            const SizedBox(height: 14),
            const Text(
              'TYPE',
              style: TextStyle(
                color: EditorTheme.textMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _TypeChoiceButton(
                    label: 'Button',
                    selected: _type == ActionType.button,
                    onTap: () => setState(() => _type = ActionType.button),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TypeChoiceButton(
                    label: 'Vector 2',
                    selected: _type == ActionType.vector2,
                    onTap: () => setState(() => _type = ActionType.vector2),
                  ),
                ),
              ],
            ),
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
          child: const Text(
            'Create',
            style: TextStyle(color: EditorTheme.primaryMuted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _TypeChoiceButton extends StatelessWidget {
  const _TypeChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? EditorTheme.primaryMuted.withValues(alpha: 0.2)
              : EditorTheme.surfaceDark,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? EditorTheme.primaryActive : EditorTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? EditorTheme.textPrimary : EditorTheme.textMuted,
          ),
        ),
      ),
    );
  }
}
