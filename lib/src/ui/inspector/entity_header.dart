import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import '../../core/tags/tag_edits.dart';
import '../../extension/built_in_tag_contributions.dart';
import '../overlay/docks/shell/built_in_docks.dart';
import '../timeline/timeline_renames.dart';
import 'tag_field_editors.dart';
import '../../core/scope/editor_scope_services.dart';

/// The top of the inspector: the entity itself — whether it is on, what it
/// is, what it is called — and the tags it carries.
///
/// `[✓] [icon] Name ·············· (player ×) (enemy ×) (+2) [⋮]`
///
/// The tick and the name work while the entity is switched off, since the
/// tick is how it comes back on; its tags wait, like the rest of the panel.
/// The tags show as many as fit; `+N` opens the rest. `⋮` adds a tag,
/// selects what shares one, or opens the Tags dock.
class EntityHeader extends StatefulWidget {
  const EntityHeader({
    super.key,
    required this.entity,
    required this.scope,
    required this.sceneState,
  });

  final jge.Entity entity;
  final EditorScope scope;
  final EditorSceneState sceneState;

  @override
  State<EntityHeader> createState() => _EntityHeaderState();
}

class _EntityHeaderState extends State<EntityHeader> {
  bool _renaming = false;
  String? _renameError;

  jge.Entity get entity => widget.entity;
  EditorScope get scope => widget.scope;

  static const double _gap = 4;
  static const TextStyle _nameStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  String get _name => entity.name ?? 'Entity ${entity.id}';

  void _setTags(List<String> tags) =>
      TagEdits.apply(scope.history, entity, tags, widget.sceneState);

  void _toggleEnabled() => scope.history.push(
    SetEnabledCommand(
      sceneState: widget.sceneState,
      entity: entity,
      enabled: !entity.isActive,
    ),
  );

  void _commitRename(String name) {
    if (_renameWithTimelines(name) ||
        scope.entities.renameEntity(entity, name)) {
      setState(() {
        _renaming = false;
        _renameError = null;
      });
      return;
    }
    // Left open, saying why, as the scene tree does.
    setState(
      () => _renameError = name.trim().isEmpty
          ? 'It needs a name'
          : 'Something else is already called that',
    );
  }

  /// The rename and what follows it — inline timelines' tracks bound to the
  /// old name, which would otherwise come loose — as one undo step. False
  /// when there is nothing to follow (the plain rename does it) or the name
  /// is not free.
  bool _renameWithTimelines(String name) {
    final from = entity.name ?? '';
    final to = name.trim();
    if (to == from) return false;
    final rebind = TimelineRenames.commandFor(scope, from, to);
    if (rebind == null ||
        !RenameCommand.isAvailable(to, entity, world: scope.world)) {
      return false;
    }
    final rename = RenameCommand(
      sceneState: widget.sceneState,
      entity: entity,
      name: to,
    );
    scope.history.push(
      CompositeCommand(label: rename.label, commands: [rename, rebind]),
    );
    scope.entities.onChanged?.call();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final on = entity.isActive;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: EditorTheme.inputBg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: EditorTheme.border),
      ),
      child: Row(
        children: [
          SceneTreeRowButton(
            icon: on
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            tooltip: on
                ? 'On in the game'
                : 'Off in the game — click to turn on',
            faded: !on,
            onPressed: _toggleEnabled,
          ),
          Icon(
            scope.iconFor(entity) ?? SceneTreeRowTile.defaultIcon(entity),
            size: 14,
            color: on ? EditorTheme.primaryMuted : EditorTheme.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => _nameAndTags(context, box.maxWidth),
            ),
          ),
          const SizedBox(width: 4),
          Builder(
            builder: (anchor) => EditorIconButton(
              icon: Icons.more_vert_rounded,
              tooltip: 'Tags',
              onTap: () => _showMenu(anchor),
            ),
          ),
        ],
      ),
    );
  }

  /// The name takes what it needs, up to half; the tags have the rest.
  Widget _nameAndTags(BuildContext context, double width) {
    final nameWidth = _renaming
        ? width * 0.6
        : (_textWidth(_name, _nameStyle) + 4).clamp(0.0, width * 0.5);
    final tagsWidth = width - nameWidth - 8;
    final on = entity.isActive;
    return Row(
      children: [
        SizedBox(
          width: nameWidth,
          child: _renaming
              ? EntityRenameBox(
                  initial: _name,
                  error: _renameError,
                  onCommit: _commitRename,
                  onCancel: () => setState(() {
                    _renaming = false;
                    _renameError = null;
                  }),
                )
              : Tooltip(
                  message: 'Double-click to rename',
                  child: GestureDetector(
                    onDoubleTap: () => setState(() => _renaming = true),
                    child: Text(
                      _name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _nameStyle.copyWith(
                        color: on
                            ? EditorTheme.textPrimary
                            : EditorTheme.textMuted,
                        decoration: on ? null : TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        if (tagsWidth > 0)
          SizedBox(
            width: tagsWidth,
            // Off, like the rest of the panel: turned back on first.
            child: IgnorePointer(
              ignoring: !on,
              child: Opacity(
                opacity: on ? 1 : 0.45,
                child: _tags(context, tagsWidth),
              ),
            ),
          ),
      ],
    );
  }

  /// As many chips as fit, right-aligned, then `+N` for the rest.
  Widget _tags(BuildContext context, double width) {
    final tags = entity.tags.toList();
    if (tags.isEmpty) return const SizedBox.shrink();
    final widths = [for (final t in tags) _chipWidth(t)];
    var shown = tags.length;
    double used(int n) {
      var w = 0.0;
      for (var i = 0; i < n; i++) {
        w += widths[i] + (i > 0 ? _gap : 0);
      }
      return w;
    }

    if (used(shown) > width) {
      shown = tags.length - 1;
      while (shown > 0 &&
          used(shown) + _gap + _moreWidth(tags.length - shown) > width) {
        shown--;
      }
    }
    final hidden = tags.length - shown;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < shown; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          _chip(tags[i], tags),
        ],
        if (hidden > 0) ...[
          if (shown > 0) const SizedBox(width: _gap),
          Builder(
            builder: (anchor) => _MoreChip(
              count: hidden,
              tooltip: tags.skip(shown).map((t) => '#$t').join('  '),
              onTap: () => _showAllTags(anchor),
            ),
          ),
        ],
      ],
    );
  }

  Widget _chip(String tag, List<String> tags, {VoidCallback? removed}) =>
      TagChip(
        tag: tag,
        color: scope.tags.colorOf(tag),
        unknown: !scope.tags.isKnown(tag),
        onHover: (inside) => TagHighlight.set(scope, tag, inside),
        onRemove: () {
          TagHighlight.set(scope, tag, false);
          _setTags([
            for (final t in tags)
              if (t != tag) t,
          ]);
          removed?.call();
        },
      );

  // A chip: padding, dot, gap, name, the remove button, the border.
  static double _chipWidth(String tag) =>
      7 + 7 + 5 + _textWidth(tag, const TextStyle(fontSize: 11)) + 18 + 4;

  static double _moreWidth(int count) =>
      _textWidth('+$count', const TextStyle(fontSize: 11)) + 18;

  static double _textWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  // ── The menus ───────────────────────────────────────────────────────────

  Future<void> _showMenu(BuildContext anchor) async {
    final tags = entity.tags;
    final chosen = await showEditorMenuBelow<String>(anchor, [
      editorMenuItem(
        'add',
        'Add tag…',
        icon: Icons.new_label_outlined,
        enabled: entity.isActive,
      ),
      editorMenuItem(
        'select',
        'Select everything tagged like this',
        icon: Icons.select_all_rounded,
        enabled: tags.isNotEmpty,
      ),
      editorMenuDivider(),
      editorMenuItem('manage', 'Manage tags…', icon: Icons.label_outline),
    ]);
    if (!mounted || !anchor.mounted) return;
    switch (chosen) {
      case 'add':
        await _addTag(anchor);
      case 'select':
        BuiltInTagContributions.selectTaggedLike(entity, scope);
      case 'manage':
        scope.dockController.open(BuiltInDocks.tags);
    }
  }

  /// The project's tags, searchable, with "Create tag …" for a new one.
  Future<void> _addTag(BuildContext anchor) async {
    final carried = entity.tags;
    final picked = await openEditorDropdownMenu<String>(
      anchor,
      width: 220,
      gap: 4,
      searchable: true,
      options: TagFieldEditors.tagOptions(scope, scope.world, exclude: carried),
      customValue: (typed) => typed,
      customLabel: TagFieldEditors.createLabel(scope),
    );
    if (picked == null) return;
    final tag = TagFieldEditors.accept(scope, picked.value);
    if (tag == null || tag.isEmpty || carried.contains(tag)) return;
    _setTags([...carried, tag]);
  }

  /// Every tag, each with its remove button — what `+N` hid.
  Future<void> _showAllTags(BuildContext anchor) async {
    final box = anchor.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    ).translate(0, 4);
    await showMenu<void>(
      context: anchor,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      color: EditorTheme.menuBg,
      elevation: 6,
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 280),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: EditorTheme.border),
      ),
      items: [
        _AllTagsEntry(
          tags: () => entity.tags.toList(),
          chip: (tag, tags, removed) => _chip(tag, tags, removed: removed),
        ),
      ],
    );
  }
}

/// `+N`: how many more tags there are than room.
class _MoreChip extends StatelessWidget {
  const _MoreChip({
    required this.count,
    required this.tooltip,
    required this.onTap,
  });

  final int count;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: EditorTheme.hoverBg,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: EditorTheme.borderStrong),
          ),
          child: Text(
            '+$count',
            style: TextStyle(
              color: EditorTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The whole tag list as one menu entry, redrawn as chips come off.
class _AllTagsEntry extends PopupMenuEntry<void> {
  const _AllTagsEntry({required this.tags, required this.chip});

  final List<String> Function() tags;
  final Widget Function(String tag, List<String> tags, VoidCallback removed)
  chip;

  @override
  double get height => 40;

  @override
  bool represents(void value) => false;

  @override
  State<_AllTagsEntry> createState() => _AllTagsEntryState();
}

class _AllTagsEntryState extends State<_AllTagsEntry> {
  @override
  Widget build(BuildContext context) {
    final tags = widget.tags();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: tags.isEmpty
          ? Text(
              'No tags',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
            )
          : Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final tag in tags)
                  widget.chip(tag, tags, () => setState(() {})),
              ],
            ),
    );
  }
}
