import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';
import '../../core/theme/editor_metrics.dart';
import 'buttons.dart';
import 'look.dart';

/// A small dialog in the editor's look: a title, what it is about, and the
/// buttons — the one to press last and filled.
class EditorAlert extends StatelessWidget {
  const EditorAlert({
    super.key,
    required this.title,
    this.message,
    this.content,
    required this.actions,
  });

  final String title;
  final String? message;

  /// Anything more than a message: a field, a list.
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => EditorLook(
    child: AlertDialog(
      backgroundColor: EditorTheme.dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EditorMetrics.radiusLg),
        side: BorderSide(color: EditorTheme.borderStrong),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      title: Text(
        title,
        style: TextStyle(
          color: EditorTheme.textPrimary,
          fontSize: EditorMetrics.fontTitle,
          fontWeight: FontWeight.w600,
        ),
      ),
      content:
          content ??
          (message == null
              ? null
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    message!,
                    style: TextStyle(
                      color: EditorTheme.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                )),
      actions: actions,
    ),
  );
}

/// Asks before something that cannot be taken back. True when the user
/// went ahead.
Future<bool> showEditorConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => EditorAlert(
      title: title,
      message: message,
      actions: [
        EditorButton(
          label: 'Cancel',
          kind: EditorButtonKind.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        EditorButton(
          label: confirmLabel,
          kind: danger ? EditorButtonKind.danger : EditorButtonKind.primary,
          autofocus: !danger,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// What to do with work that has not been saved.
enum UnsavedChoice { save, discard }

/// Asks whether to save before something that would lose unsaved work:
/// Save, Don't save, or Cancel — which is null.
Future<UnsavedChoice?> askToSaveChanges(
  BuildContext context, {
  required String title,
  String? message,
}) => showDialog<UnsavedChoice>(
  context: context,
  barrierColor: Colors.black54,
  builder: (context) => EditorAlert(
    title: title,
    message: message,
    actions: [
      EditorButton(
        label: "Don't save",
        kind: EditorButtonKind.danger,
        onPressed: () => Navigator.of(context).pop(UnsavedChoice.discard),
      ),
      EditorButton(
        label: 'Cancel',
        kind: EditorButtonKind.ghost,
        onPressed: () => Navigator.of(context).pop(),
      ),
      EditorButton(
        label: 'Save',
        kind: EditorButtonKind.primary,
        autofocus: true,
        onPressed: () => Navigator.of(context).pop(UnsavedChoice.save),
      ),
    ],
  ),
);

/// Offers work that was never saved — an autosaved backup: Recover (true),
/// Open saved (false), or Cancel — which is null, and decides nothing.
Future<bool?> askToRecover(
  BuildContext context, {
  required String title,
  String? message,
}) => showDialog<bool>(
  context: context,
  barrierColor: Colors.black54,
  builder: (context) => EditorAlert(
    title: title,
    message: message,
    actions: [
      EditorButton(
        label: 'Open saved',
        kind: EditorButtonKind.ghost,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      EditorButton(
        label: 'Recover',
        kind: EditorButtonKind.primary,
        autofocus: true,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  ),
);
