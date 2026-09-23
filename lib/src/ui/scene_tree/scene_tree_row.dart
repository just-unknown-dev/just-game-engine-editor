/// One line of the scene tree.
///
/// Draws only; everything it can do is a callback, so the panel keeps the
/// decisions and this keeps the look.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/constants/editor_constants.dart';
import '../../core/entity/entity_ops.dart';
import 'scene_tree_model.dart';

/// Where a dragged row would land relative to the one under it.
enum DropZone { above, onto, below }

/// How near a row's edge a drop has to be to mean "between these two"
/// rather than "inside this one".
///
/// A few pixels, not a share of the row: dropping something *into* a
/// container is the common move and has to be the easy one. A band that
/// was a share of the row left barely a third of it meaning what the whole
/// row plainly looks like it means. Four, not five, because these rows are
/// 22 pixels tall and five each way took nearly half of one.
const double kTreeDropEdge = 4;

/// What a drop [dy] pixels down a row [height] tall means.
DropZone dropZoneFor(double dy, double height) {
  final edge = kTreeDropEdge < height / 3 ? kTreeDropEdge : height / 3;
  if (dy < edge) return DropZone.above;
  if (dy > height - edge) return DropZone.below;
  return DropZone.onto;
}

class SceneTreeRowTile extends StatelessWidget {
  const SceneTreeRowTile({
    super.key,
    required this.row,
    required this.isSelected,
    required this.isMultiSelected,
    required this.onToggleExpand,
    this.isRenaming = false,
    this.renameError,
    this.onCommitRename,
    this.onCancelRename,
    this.isHidden = false,
    this.isLocked = false,
    this.onToggleHidden,
    this.onToggleLocked,
    this.dropZone,
    this.icon,
    this.color,
    this.trailing = const [],
  });

  final TreeRow row;
  final bool isSelected;
  final bool isMultiSelected;

  /// Opens or shuts it; true when Alt was held, meaning the whole subtree.
  final void Function({required bool subtree}) onToggleExpand;

  /// What a module says this kind of entity looks like; the editor's own
  /// choice when none does.
  final IconData? icon;

  /// The swatch this row is marked with, if any.
  final Color? color;

  final bool isRenaming;
  final String? renameError;
  final void Function(String name)? onCommitRename;
  final VoidCallback? onCancelRename;

  final bool isHidden;
  final bool isLocked;
  final VoidCallback? onToggleHidden;
  final VoidCallback? onToggleLocked;

  /// Where a drag hovering over this row would drop, or null when none is.
  final DropZone? dropZone;

  /// Badges and buttons at the right-hand end.
  final List<Widget> trailing;

  jge.Entity get entity => row.entity;

  @override
  Widget build(BuildContext context) {
    final name = entity.name ?? 'Entity #${entity.id}';
    final zone = dropZone;
    final background = zone == DropZone.onto
        ? EditorTheme.dragOverBg
        : isSelected
        ? EditorTheme.selectionBg
        : isMultiSelected
        ? EditorTheme.multiSelectBg
        : Colors.transparent;

    // The line that says "between these two" starts where the row's
    // content starts, so it shows what depth the thing would land at
    // rather than spanning the panel and meaning nothing in particular.
    final indent = 8 + row.depth * 14.0;

    return DecoratedBox(
      decoration: BoxDecoration(color: background),
      child: Stack(
        children: [
          if (zone == DropZone.above || zone == DropZone.below)
            Positioned(
              left: indent,
              right: 6,
              top: zone == DropZone.above ? 0 : null,
              bottom: zone == DropZone.below ? 0 : null,
              child: Container(height: 2, color: EditorTheme.primaryBright),
            ),
          // The mark, down the left edge, where it reads as a label on
          // the row rather than as part of anything in it.
          if (color case final color?)
            Positioned(
              left: 0,
              top: 2,
              bottom: 2,
              child: Container(width: 3, color: color),
            ),
          _content(name, indent),
        ],
      ),
    );
  }

  Widget _content(String name, double indent) {
    return Padding(
      padding: EdgeInsets.only(left: indent, right: 6),
      child: Row(
        children: [
          if (row.hasChildren)
            GestureDetector(
              // Opaque and with room around it: a 14px glyph is not a
              // thing anyone can reliably hit.
              behavior: HitTestBehavior.opaque,
              onTap: () => onToggleExpand(
                subtree: HardwareKeyboard.instance.isAltPressed,
              ),
              child: SizedBox(
                width: 18,
                height: kSceneTreeRowTileHeight,
                child: Icon(
                  row.isExpanded
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded,
                  size: 14,
                  color: EditorTheme.primary,
                ),
              ),
            )
          else
            const SizedBox(width: 18),
          const SizedBox(width: 2),
          Icon(
            icon ?? uiIconFor(entity) ?? _worldIcon(entity),
            size: 14,
            color: isSelected
                ? EditorTheme.primaryBright
                : row.isMatch
                ? EditorTheme.primaryMuted
                : EditorTheme.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: isRenaming
                ? _RenameBox(
                    initial: name,
                    error: renameError,
                    onCommit: onCommitRename,
                    onCancel: onCancelRename,
                  )
                : Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: !row.isMatch
                          ? EditorTheme.textMuted
                          : isSelected
                          ? EditorTheme.textBright
                          : EditorTheme.textSecondary,
                      fontStyle: row.isRuntime
                          ? FontStyle.italic
                          : FontStyle.normal,
                      decoration: entity.isActive
                          ? null
                          : TextDecoration.lineThrough,
                    ),
                  ),
          ),
          ...trailing,
          if (onToggleHidden != null)
            _RowButton(
              icon: isHidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              tooltip: isHidden ? 'Show in the viewport' : 'Hide',
              faded: !isHidden,
              onPressed: onToggleHidden!,
            ),
          if (onToggleLocked != null)
            _RowButton(
              icon: isLocked ? Icons.lock_outline : Icons.lock_open_outlined,
              tooltip: isLocked ? 'Unlock' : 'Lock against picking',
              faded: !isLocked,
              onPressed: onToggleLocked!,
            ),
        ],
      ),
    );
  }

  /// The icon for something in the world; a module can say better.
  static IconData _worldIcon(jge.Entity entity) {
    if (entity.getComponent<jge.ChildrenComponent>()?.childIds.isNotEmpty ??
        false) {
      return Icons.folder_rounded;
    }
    return Icons.category_rounded;
  }
}

/// The height the list lays a row out at.
const double kSceneTreeRowTileHeight = 22;

/// The name, while it is being typed.
class _RenameBox extends StatefulWidget {
  const _RenameBox({
    required this.initial,
    this.error,
    this.onCommit,
    this.onCancel,
  });

  final String initial;
  final String? error;
  final void Function(String name)? onCommit;
  final VoidCallback? onCancel;

  @override
  State<_RenameBox> createState() => _RenameBoxState();
}

class _RenameBoxState extends State<_RenameBox> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'rename');
  final FocusNode _keys = FocusNode(debugLabel: 'renameKeys');
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Clicking anywhere else takes the name as typed. A box left open
    // behind a click is a rename the author believes they finished.
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
    _focus.requestFocus();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _keys.dispose();
    super.dispose();
  }

  /// Takes the name, once. Losing focus and pressing Enter can both
  /// happen for one rename, and it must not be applied twice.
  void _commit() {
    if (_done) return;
    _done = true;
    widget.onCommit?.call(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    return KeyboardListener(
      focusNode: _keys,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          // Escape throws the typing away, so losing focus afterwards
          // must not take it.
          _done = true;
          widget.onCancel?.call();
        }
      },
      // Exactly a row tall, and never taller: the list lays its rows out
      // at a fixed height, so a box that grew to fit an error message
      // drew straight over the rows beneath it. What is wrong is said by
      // the box's colour and its tooltip instead.
      // Only when there is something to say: a `Tooltip` with an empty
      // message still opens on hover, as a small empty box.
      child: _MaybeTooltip(
        message: error,
        child: SizedBox(
          height: kSceneTreeRowTileHeight,
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            style: TextStyle(
              color: error == null
                  ? EditorTheme.textPrimary
                  : EditorTheme.errorLight,
              fontSize: 11,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 3,
              ),
              filled: true,
              fillColor: EditorTheme.inputBg,
              border: _renameBorder(error),
              enabledBorder: _renameBorder(error),
              focusedBorder: _renameBorder(error, focused: true),
            ),
            onSubmitted: (_) => _commit(),
          ),
        ),
      ),
    );
  }
}

/// A tooltip, or nothing at all when there is no message.
class _MaybeTooltip extends StatelessWidget {
  const _MaybeTooltip({required this.message, required this.child});

  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      message == null ? child : Tooltip(message: message!, child: child);
}

/// The box's edge, which is how it says whether the name will do.
OutlineInputBorder _renameBorder(String? error, {bool focused = false}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(3),
      borderSide: BorderSide(
        color: error != null
            ? EditorTheme.error
            : focused
            ? EditorTheme.primaryBright
            : EditorTheme.primaryActive,
      ),
    );

class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.faded = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool faded;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: const Duration(milliseconds: 600),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox(
        width: 20,
        height: kSceneTreeRowTileHeight,
        child: Icon(
          icon,
          size: 13,
          color: faded
              ? EditorTheme.textMuted.withValues(alpha: 0.45)
              : EditorTheme.primaryBright,
        ),
      ),
    ),
  );
}
