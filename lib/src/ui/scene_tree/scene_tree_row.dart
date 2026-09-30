/// One line of the scene tree.
///
/// Draws only; everything it can do is a callback, so the panel keeps the
/// decisions and this keeps the look.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/constants/editor_constants.dart';
import '../../core/theme/editor_metrics.dart';
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
    this.isDisabled = false,
    this.isPinned = false,
    this.onControlDown,
    this.onToggleEnabled,
    this.onToggleHidden,
    this.onTogglePinned,
    this.onPickColor,
    this.onShowMenu,
    this.dropZone,
    this.icon,
    this.color,
    this.hasKeyboardFocus = false,
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

  /// Whether the tree has the keyboard and this is the row the arrows
  /// would move from — drawn with an outline, because otherwise there is
  /// no telling what the keys are about to act on.
  final bool hasKeyboardFocus;

  final bool isRenaming;
  final String? renameError;
  final void Function(String name)? onCommitRename;
  final VoidCallback? onCancelRename;

  /// Hidden in the viewport — the editor's own business, which the row
  /// says by going faint rather than by carrying an icon for it.
  final bool isHidden;

  /// Out of reach right now — everything but the Level Map, while the
  /// Level Designer is open. Drawn faint with its eye shut, since the
  /// viewport does not draw it either, and only its chevron still
  /// answers: a Level Map can sit inside a group, and the way to it is
  /// through that group's row.
  final bool isDisabled;

  /// Whether the inspector is pinned to this row — it keeps showing
  /// this entity's components while another is selected.
  final bool isPinned;

  /// Told as the pointer goes down on any of the row's own controls,
  /// so the row does not read that press as picking it.
  final VoidCallback? onControlDown;

  /// Switches the entity on or off in the game — saved with the scene.
  final VoidCallback? onToggleEnabled;

  /// Hides it in the viewport while building. The editor's own state:
  /// nothing about it is saved and the game never sees it.
  final VoidCallback? onToggleHidden;

  final VoidCallback? onTogglePinned;

  /// Opens the swatches, and the row's menu, at the button pressed.
  final void Function(Offset at)? onPickColor;
  final void Function(Offset at)? onShowMenu;

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
    final indent = 4 + row.depth * 12.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: hasKeyboardFocus && isSelected
            ? Border.all(color: EditorTheme.primaryActive, width: 1)
            : null,
      ),
      child: Stack(
        children: [
          if (zone == DropZone.above || zone == DropZone.below)
            Positioned(
              left: indent + kSceneTreeRowTileHeight,
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
          isDisabled || isHidden
              ? Opacity(
                  opacity: isDisabled ? 0.35 : 0.45,
                  child: _content(name, indent),
                )
              : _content(name, indent),
        ],
      ),
    );
  }

  Widget _content(String name, double indent) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          // On in the game. In a column of its own at the far left,
          // outside the indent, so every tick lines up whatever the
          // depth and the column can be read — and clicked — down.
          if (onToggleEnabled != null)
            IgnorePointer(
              ignoring: isDisabled,
              child: SceneTreeRowButton(
                icon: entity.isActive
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                tooltip: entity.isActive ? 'On in the game' : 'Off in the game',
                faded: !entity.isActive,
                onPressed: onToggleEnabled!,
                onDown: onControlDown,
              ),
            ),
          SizedBox(width: indent),
          if (row.hasChildren)
            Semantics(
              button: true,
              label: row.isExpanded ? 'Collapse' : 'Expand',
              child: GestureDetector(
                // Opaque and with room around it: a 14px glyph is not a
                // thing anyone can reliably hit.
                behavior: HitTestBehavior.opaque,
                onTap: () => onToggleExpand(
                  subtree: HardwareKeyboard.instance.isAltPressed,
                ),
                child: SizedBox(
                  width: kSceneTreeRowTileHeight,
                  height: kSceneTreeRowTileHeight,
                  child: Icon(
                    row.isExpanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 14,
                    color: EditorTheme.primary,
                  ),
                ),
              ),
            )
          else
            SizedBox(width: kSceneTreeRowTileHeight),
          const SizedBox(width: 2),
          Icon(
            icon ?? defaultIcon(entity),
            size: 14,
            // The accent is for what the editor *knows*: something a
            // module claimed as its own. A plain entity gets a plain
            // colour, so the column carries something instead of being
            // eleven pink glyphs.
            color: !row.isMatch
                ? EditorTheme.textMuted
                : isSelected
                ? EditorTheme.primaryBright
                : icon != null
                ? EditorTheme.primaryMuted
                : EditorTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: isRenaming
                ? EntityRenameBox(
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
          // Between the name and what is drawn after it — a badge, the
          // eye, the padlock — so they do not read as part of it.
          if (trailing.isNotEmpty) const SizedBox(width: 6),
          ...trailing,
          // The mark, then hidden, then locked, then everything else.
          // The two that only *act* keep their place while they are
          // invisible, so nothing shifts under the pointer.
          if (onPickColor != null)
            IgnorePointer(
              ignoring: isDisabled,
              child: Builder(
                builder: (context) => _ColorMark(
                  color: color,
                  onPressed: () => onPickColor!(_below(context)),
                  onDown: onControlDown,
                ),
              ),
            ),
          if (onToggleHidden != null)
            isDisabled
                // Hidden by the designer, not by this eye: shut, and it
                // says so rather than offering to open.
                ? SceneTreeRowButton(
                    icon: Icons.visibility_off_outlined,
                    tooltip: 'Hidden while the Level Designer is open',
                    onPressed: () {},
                    onDown: onControlDown,
                  )
                : SceneTreeRowButton(
                    icon: isHidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    tooltip: isHidden ? 'Show it' : 'Hide it while building',
                    faded: !isHidden,
                    onPressed: onToggleHidden!,
                    onDown: onControlDown,
                  ),
          if (onTogglePinned != null)
            IgnorePointer(
              ignoring: isDisabled,
              child: SceneTreeRowButton(
                icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                tooltip: isPinned
                    ? 'Unpin the inspector'
                    : 'Keep the inspector on it',
                faded: !isPinned,
                onPressed: onTogglePinned!,
                onDown: onControlDown,
              ),
            ),
          if (onShowMenu != null)
            IgnorePointer(
              ignoring: isDisabled,
              child: Builder(
                builder: (context) => SceneTreeRowButton(
                  icon: Icons.more_vert,
                  tooltip: 'More for it',
                  faded: true,
                  onPressed: () => onShowMenu!(_below(context)),
                  onDown: onControlDown,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Where a menu opened from [context]'s button should appear.
  static Offset _below(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null
        ? Offset.zero
        : box.localToGlobal(box.size.bottomLeft(Offset.zero));
  }

  /// The icon for something in the world; a module can say better
  /// (`EditorScope.iconFor`).
  static IconData defaultIcon(jge.Entity entity) {
    if (entity.getComponent<jge.ChildrenComponent>()?.childIds.isNotEmpty ??
        false) {
      return Icons.folder_rounded;
    }
    return Icons.category_rounded;
  }
}

/// The height the list lays a row out at.
double get kSceneTreeRowTileHeight => EditorMetrics.minTarget;

/// An entity's name, while it is being typed: Enter or a click elsewhere
/// takes it, Escape throws it away. The scene tree's rows and the
/// inspector's header both rename with it.
class EntityRenameBox extends StatefulWidget {
  const EntityRenameBox({
    super.key,
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
  State<EntityRenameBox> createState() => _EntityRenameBoxState();
}

class _EntityRenameBoxState extends State<EntityRenameBox> {
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

/// A small button at the end of a row: the eye, the padlock, the swatch.
class SceneTreeRowButton extends StatelessWidget {
  const SceneTreeRowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.faded = false,
    this.onDown,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool faded;

  /// Called as the pointer goes down on it, before the row's own
  /// listener hears the same press. A press on a control is about the
  /// control, not about picking the row it sits on.
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Listener(
      onPointerDown: (_) => onDown?.call(),
      // An InkWell, not a bare detector: it takes the keyboard's focus,
      // and Enter or Space presses it.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          hoverColor: EditorTheme.hoverBg,
          child: SizedBox(
            width: kSceneTreeRowTileHeight,
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
      ),
    ),
  );
}

/// The row's colour mark: a label, filled with the colour it carries
/// and hollow when it carries none.
class _ColorMark extends StatelessWidget {
  const _ColorMark({required this.color, required this.onPressed, this.onDown});

  final Color? color;
  final VoidCallback onPressed;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: color == null ? 'Mark with a colour' : 'Change the mark',
    child: Listener(
      onPointerDown: (_) => onDown?.call(),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          hoverColor: EditorTheme.hoverBg,
          child: SizedBox(
            width: kSceneTreeRowTileHeight,
            height: kSceneTreeRowTileHeight,
            child: Icon(
              color == null ? Icons.label_outline : Icons.label,
              size: 13,
              color: color ?? EditorTheme.textMuted.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    ),
  );
}
