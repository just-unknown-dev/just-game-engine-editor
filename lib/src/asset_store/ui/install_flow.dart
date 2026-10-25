import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../store_controller.dart';

/// Shows [plan], and on the user's word applies it: progress in a message
/// (and the store window), a sticky notice when the editor must restart,
/// and the setup code kits ask for.
Future<void> runPlan(
  BuildContext context,
  StoreController controller,
  InstallPlan? plan, {
  required String verb,
  required String subject,
}) async {
  if (plan == null) return; // the catalogs are not loaded yet
  final go = await showInstallPreview(
    context,
    plan,
    verb: verb,
    subject: subject,
  );
  if (!go || !context.mounted) return;

  EditorSnackBarController? messages;
  try {
    messages = EditorMessenger.of(context);
  } on Object {
    // Not under the editor's messenger (a test): the window's own progress
    // strip still shows it.
  }
  final steps = StreamController<EditorSnackBarStep>();
  messages?.showSnackBar(
    EditorSnackBarEntry(
      title: '$verb $subject',
      message: _summary(plan),
      progressStream: steps.stream,
      onCancel: controller.cancel,
    ),
  );
  try {
    final result = await controller.apply(
      plan,
      onProgress: (p) => steps.add(
        EditorSnackBarStep(message: p.message, progress: p.fraction),
      ),
    );
    steps.add(const EditorSnackBarStep(message: 'Done'));
    await steps.close();
    if (!context.mounted) return;
    if (result.needsRestart) {
      messages?.showSnackBar(
        const EditorSnackBarEntry(
          title: 'Restart the editor',
          message:
              'New editor code was installed. Hot restart (R in the terminal '
              'running the editor) or restart it to use it.',
          type: EditorSnackBarType.warning,
          sticky: true,
        ),
      );
    }
    if (result.setupSnippets.isNotEmpty) {
      await showSetupSnippets(context, result.setupSnippets);
    }
  } on CancelledException {
    steps.add(
      const EditorSnackBarStep(message: 'Cancelled; nothing was changed.'),
    );
    await steps.close();
  } on Object catch (e) {
    final message = e is InstallFailure ? e.message : '$e';
    steps.add(EditorSnackBarStep(message: message, isError: true));
    await steps.close();
    if (messages == null && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => EditorAlert(
          title: '$verb failed',
          message: message,
          actions: [
            EditorButton(
              label: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
  }
}

String _summary(InstallPlan plan) {
  final n = plan.changes.length;
  return n == 1 ? plan.changes.single.name : '$n items';
}

/// Asks before [plan] is applied, showing exactly what it changes and what
/// the user should know. True when the user went ahead.
Future<bool> showInstallPreview(
  BuildContext context,
  InstallPlan plan, {
  required String verb,
  required String subject,
}) async {
  final go = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => EditorAlert(
      title: '$verb $subject?',
      content: SizedBox(
        width: 480,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(child: InstallPreview(plan: plan)),
        ),
      ),
      actions: [
        EditorButton(
          label: 'Cancel',
          kind: EditorButtonKind.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        EditorButton(
          label: verb,
          kind: plan.changes.any((c) => c.kind == ChangeKind.remove)
              ? EditorButtonKind.danger
              : EditorButtonKind.primary,
          autofocus: plan.canApply,
          onPressed: plan.canApply
              ? () => Navigator.of(context).pop(true)
              : null,
        ),
      ],
    ),
  );
  return go ?? false;
}

/// What a plan does, item by item, and what it asks the user to know.
class InstallPreview extends StatelessWidget {
  const InstallPreview({super.key, required this.plan});

  final InstallPlan plan;

  @override
  Widget build(BuildContext context) {
    final text = TextStyle(
      color: EditorTheme.textSecondary,
      fontSize: EditorMetrics.fontBody,
      height: 1.35,
    );
    final muted = text.copyWith(color: EditorTheme.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in plan.changes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  switch (c.kind) {
                    ChangeKind.install => Icons.add_circle_outline_rounded,
                    ChangeKind.update => Icons.sync_rounded,
                    ChangeKind.remove => Icons.remove_circle_outline_rounded,
                    ChangeKind.adopt => Icons.check_circle_outline_rounded,
                  },
                  size: EditorMetrics.iconLg,
                  color: c.kind == ChangeKind.remove
                      ? EditorTheme.error
                      : EditorTheme.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        switch (c.kind) {
                          ChangeKind.install =>
                            '${c.name} ${c.version!.version}',
                          ChangeKind.update =>
                            '${c.name} ${c.current?.version} → '
                                '${c.version!.version}',
                          ChangeKind.remove => c.name,
                          ChangeKind.adopt =>
                            '${c.name} ${c.current?.version}, kept as one of '
                                'yours',
                        },
                        style: text.copyWith(
                          color: EditorTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        [
                          c.reason,
                          if (c.path != null && c.kind != ChangeKind.remove)
                            c.path!,
                          if (c.kind == ChangeKind.remove && c.path != null)
                            '${c.path} goes to .editor_trash/',
                        ].join(' · '),
                        style: muted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (plan.downloadBytes > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              'Download: up to ${_bytes(plan.downloadBytes)}.',
              style: muted,
            ),
          ),
        if (plan.changes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'The store edits only its own marked block in pubspec.yaml '
              '(and pubspec_overrides.yaml), records the change in '
              'just_store.lock.json, and keeps a backup: if anything fails, '
              'everything is put back.',
              style: muted,
            ),
          ),
        if (plan.needsRestart)
          _Note(
            icon: Icons.restart_alt_rounded,
            colour: EditorTheme.warning,
            text:
                'This is code: the editor needs a restart (or hot restart) '
                'afterwards to run it.',
          ),
        for (final issue in plan.issues)
          _Note(
            icon: switch (issue.level) {
              IssueLevel.blocker => Icons.block_rounded,
              IssueLevel.warning => Icons.warning_amber_rounded,
              IssueLevel.info => Icons.info_outline_rounded,
            },
            colour: switch (issue.level) {
              IssueLevel.blocker => EditorTheme.error,
              IssueLevel.warning => EditorTheme.warning,
              IssueLevel.info => EditorTheme.info,
            },
            text: issue.message,
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.colour, required this.text});

  final IconData icon;
  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: EditorMetrics.iconMd, color: colour),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: EditorTheme.textSecondary,
              fontSize: EditorMetrics.fontBody,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The game code kits ask the user to add by hand, with a copy button.
Future<void> showSetupSnippets(
  BuildContext context,
  Map<String, String> snippets,
) => showDialog<void>(
  context: context,
  builder: (context) => EditorAlert(
    title: 'One more step',
    content: SizedBox(
      width: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in snippets.entries) ...[
            Text(
              '${e.key} needs this in your game code:',
              style: TextStyle(
                color: EditorTheme.textSecondary,
                fontSize: EditorMetrics.fontBody,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: EditorTheme.surfaceDarkest,
                borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
              ),
              child: SelectableText(
                e.value,
                style: TextStyle(
                  color: EditorTheme.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: EditorMetrics.fontBody,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    ),
    actions: [
      EditorButton(
        label: 'Copy',
        icon: Icons.copy_rounded,
        kind: EditorButtonKind.ghost,
        onPressed: () => Clipboard.setData(
          ClipboardData(text: snippets.values.join('\n\n')),
        ),
      ),
      EditorButton(
        label: 'Done',
        kind: EditorButtonKind.primary,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  ),
);

String _bytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
}
