/// What every workspace is framed with — the sprite editor, the tileset
/// editor, the interface editor — so they read as one editor's windows
/// rather than four programs that happen to open from it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';
import '../../core/theme/editor_metrics.dart';
import 'buttons.dart';
import 'dialogs.dart';

/// The bar along the top of a workspace: what it is and what file it has
/// open, whether that is saved, Save, Undo and Redo — then the workspace's
/// own [tools], and on the right full screen and close.
class WorkspaceHeader extends StatelessWidget {
  const WorkspaceHeader({
    super.key,
    required this.icon,
    required this.title,
    this.file,
    this.dirty = false,
    this.onSave,
    this.onUndo,
    this.onRedo,
    this.undoLabel,
    this.redoLabel,
    this.showHistory = true,
    this.tools = const [],
    this.trailing = const [],
    this.fullScreen,
    this.onToggleFullScreen,
    this.onClose,
    this.closeTooltip = 'Close',
  });

  final IconData icon;

  /// What the workspace is: "Interface", "Sprite Studio".
  final String title;

  /// The file it has open, when it has one.
  final String? file;

  /// Whether there is work not yet saved: a dot after the file, and Save lit.
  final bool dirty;

  /// Null hides Save.
  final VoidCallback? onSave;

  /// Null greys the button out: there is nothing to undo, or to redo.
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  /// What Undo and Redo would do, for their tooltips.
  final String? undoLabel;
  final String? redoLabel;

  /// False for a workspace with no undo: no Undo and Redo at all, rather
  /// than two buttons that never light.
  final bool showHistory;

  /// The workspace's own buttons, after Undo and Redo.
  final List<Widget> tools;

  /// Buttons before full screen and close.
  final List<Widget> trailing;

  final ValueListenable<bool>? fullScreen;
  final VoidCallback? onToggleFullScreen;

  /// Null hides Close.
  final VoidCallback? onClose;
  final String closeTooltip;

  /// The header's height, for anything laid out against it.
  static const double height = 36;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: EditorTheme.panelBg,
        border: Border(bottom: BorderSide(color: EditorTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  icon,
                  size: EditorMetrics.iconMd,
                  color: EditorTheme.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: EditorTheme.textPrimary,
                    fontSize: EditorMetrics.fontTitle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (file != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      file!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: EditorTheme.textMuted,
                        fontSize: EditorMetrics.fontBody,
                      ),
                    ),
                  ),
                ],
                if (dirty) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Not saved',
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: EditorTheme.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                if (onSave != null)
                  EditorIconButton(
                    icon: Icons.save_outlined,
                    tooltip: dirty ? 'Save' : 'Save — nothing has changed',
                    shortcut: 'Ctrl+S',
                    isActive: dirty,
                    onTap: onSave,
                  ),
                if (showHistory) ...[
                  EditorIconButton(
                    icon: Icons.undo_rounded,
                    tooltip: undoLabel == null ? 'Undo' : 'Undo $undoLabel',
                    shortcut: 'Ctrl+Z',
                    onTap: onUndo,
                  ),
                  EditorIconButton(
                    icon: Icons.redo_rounded,
                    tooltip: redoLabel == null ? 'Redo' : 'Redo $redoLabel',
                    shortcut: 'Ctrl+Y',
                    onTap: onRedo,
                  ),
                ],
                if (tools.isNotEmpty) ...[
                  const _HeaderDivider(),
                  Flexible(
                    flex: 3,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: tools,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...trailing,
          ?WorkspaceFullScreenButton.maybe(
            fullScreen: fullScreen,
            onToggle: onToggleFullScreen,
          ),
          if (onClose != null)
            EditorIconButton(
              icon: Icons.close_rounded,
              tooltip: closeTooltip,
              onTap: onClose,
            ),
        ],
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  const _HeaderDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 16,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: EditorTheme.border,
  );
}

/// Fills the editor with a workspace, or puts it back in its dialog.
class WorkspaceFullScreenButton extends StatelessWidget {
  const WorkspaceFullScreenButton({
    super.key,
    required this.fullScreen,
    required this.onToggle,
  });

  /// The button, or null where the host offers no such choice.
  static Widget? maybe({
    required ValueListenable<bool>? fullScreen,
    required VoidCallback? onToggle,
  }) => fullScreen == null || onToggle == null
      ? null
      : WorkspaceFullScreenButton(fullScreen: fullScreen, onToggle: onToggle);

  final ValueListenable<bool> fullScreen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: fullScreen,
    builder: (context, filled, _) => EditorIconButton(
      icon: filled ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
      tooltip: filled ? 'Back to a window' : 'Fill the editor',
      isActive: filled,
      onTap: onToggle,
    ),
  );
}

/// Where a workspace's keys arrive.
///
/// [onKey] hears every key the workspace sees — except while text is being
/// typed: then Delete deletes a letter and Escape leaves the field, rather
/// than deleting the selection and closing the window. A click anywhere
/// that is not a field takes the keys back, so a shortcut works again
/// straight after typing.
class WorkspaceKeyScope extends StatefulWidget {
  const WorkspaceKeyScope({
    super.key,
    required this.onKey,
    required this.child,
    this.autofocus = true,
  });

  final KeyEventResult Function(KeyEvent event) onKey;
  final Widget child;
  final bool autofocus;

  /// Whether the keyboard is in a text field right now.
  static bool get isTyping =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>() !=
      null;

  @override
  State<WorkspaceKeyScope> createState() => _WorkspaceKeyScopeState();
}

class _WorkspaceKeyScopeState extends State<WorkspaceKeyScope> {
  final FocusNode _node = FocusNode(debugLabel: 'workspace');

  @override
  void initState() {
    super.initState();
    // Asked for outright once it is on screen, not only through autofocus:
    // a route that finishes opening after this was built takes the focus
    // for itself, and the first key pressed went nowhere.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !WorkspaceKeyScope.isTyping) _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) {
      // A field takes the focus itself on this same press; anything else
      // hands it back to the workspace.
      if (!WorkspaceKeyScope.isTyping) _node.requestFocus();
    },
    child: Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) => WorkspaceKeyScope.isTyping
          ? KeyEventResult.ignored
          : widget.onKey(event),
      child: widget.child,
    ),
  );
}

/// Asks what to do with unsaved work before leaving it, and does it.
///
/// True when it is fine to go on: nothing was unsaved, the work was
/// dropped, or [save] saved it. False when the author cancelled — or the
/// save did not go through, in which case staying is the only safe choice.
Future<bool> mayLeaveUnsaved(
  BuildContext context, {
  required bool dirty,
  required Future<bool> Function() save,
  String title = 'Save your changes?',
  String? message,
}) async {
  if (!dirty) return true;
  final choice = await askToSaveChanges(
    context,
    title: title,
    message: message,
  );
  return switch (choice) {
    null => false,
    UnsavedChoice.discard => true,
    UnsavedChoice.save => await save(),
  };
}
