import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';
import '../../core/constants/editor_constants.dart';
import '../../core/entity/entity_ops.dart';
import '../widgets/editor_menu.dart';
import '../../core/scope/editor_scope.dart';
import '../../core/state/editor_scene_state.dart';
import '../../extension/editor_contributions.dart';

/// Scrollable, hierarchical list of the scene's entities: everything
/// with a [TransformComponent], and everything that is interface.
///
/// Root entities appear at depth 0. Entities with a [ParentComponent] are
/// nested under their parent with expand/collapse chevrons. Drag an entity row
/// onto another to reparent it; drop onto empty space to detach.
class SceneTreePanel extends StatefulWidget {
  const SceneTreePanel({
    super.key,
    required this.sceneState,
    required this.world,
    required this.onCreateEntity,
    required this.onCreateGroup,
    required this.onCreateGroupFrom,
    required this.onDeleteEntity,
    required this.onCopyEntity,
    required this.onPasteEntity,
    required this.onReparentEntity,
    this.onCreateUi,
    this.onReorderEntity,
    this.onToggleUiMode,
    this.uiModeOn = false,
    this.viewToggles,
    this.scope,
  });

  final EditorSceneState sceneState;
  final World world;

  /// Per-entity hide and lock, when the Level Designer is open. Null leaves
  /// the rows as they always were.
  final EntityViewToggles? viewToggles;

  /// The editor, for module actions, decorations and protection rules.
  /// Null keeps the tree exactly as it was.
  final EditorScope? scope;
  final VoidCallback onCreateEntity;
  final VoidCallback onCreateGroup;

  /// Called with the right-clicked entity to group it into a new parent.
  final void Function(Entity entity) onCreateGroupFrom;
  final void Function(Entity entity) onDeleteEntity;
  final void Function(Entity entity) onCopyEntity;
  final VoidCallback onPasteEntity;
  final void Function(Entity child, Entity newParent) onReparentEntity;

  /// Turns the viewport's UI mode on and off. Without it the button is
  /// not shown.
  final void Function(bool on)? onToggleUiMode;

  /// Whether that mode is on now.
  final bool uiModeOn;

  /// Moves an entity before or after one of its siblings. Without it, a
  /// drop always re-parents.
  final void Function(Entity moved, Entity anchor, {required bool before})?
  onReorderEntity;

  /// Creates a piece of interface of the given kind — `text`, `row`,
  /// `custom:inventory_grid`. Without it the Create-UI button is not shown.
  final void Function(String kind)? onCreateUi;

  @override
  State<SceneTreePanel> createState() => _SceneTreePanelState();
}

class _SceneTreePanelState extends State<SceneTreePanel> {
  final Set<EntityId> _expandedIds = {};
  EntityId? _anchorId;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Whether [entity] matches the search: by name, or by the type of any of
  /// its components, so "hazard" finds every hazard whatever it is called.
  bool _matches(Entity entity) {
    final q = _query.toLowerCase();
    if ((entity.name ?? '').toLowerCase().contains(q)) return true;
    return entity.components.any(
      (c) => c.runtimeType.toString().toLowerCase().contains(q),
    );
  }

  void _toggleExpanded(EntityId id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  void _handleShiftTap(Entity clicked, List<Entity> visibleEntities) {
    if (_anchorId == null) {
      _anchorId = clicked.id;
      widget.sceneState.selectEntity(clicked);
      return;
    }
    final anchorIdx = visibleEntities.indexWhere((e) => e.id == _anchorId);
    final clickedIdx = visibleEntities.indexWhere((e) => e.id == clicked.id);
    if (anchorIdx == -1 || clickedIdx == -1) {
      _anchorId = clicked.id;
      widget.sceneState.selectEntity(clicked);
      return;
    }
    final from = anchorIdx < clickedIdx ? anchorIdx : clickedIdx;
    final to = anchorIdx < clickedIdx ? clickedIdx : anchorIdx;
    widget.sceneState.selectRange(
      visibleEntities.sublist(from, to + 1),
      anchor: visibleEntities[anchorIdx],
    );
  }

  /// Whether an entity belongs to the interface rather than the world.
  static bool _isUiEntity(Entity entity) =>
      entity.getComponent<UiCanvasComponent>() != null ||
      entity.getComponent<UiSlotComponent>() != null;

  /// Everything that can be made, grouped as the menu shows it: the
  /// built-in kinds first, then whatever the running game registered.
  Future<void> _showCreateUiMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final at = box == null
        ? Offset.zero
        : box.localToGlobal(box.size.bottomLeft(Offset.zero));
    final items = <PopupMenuEntry<String>>[];
    var group = '';
    for (final option in UiCreateOptions.all) {
      if (option.group != group) {
        if (items.isNotEmpty) items.add(editorMenuDivider());
        items.add(editorMenuHeading<String>(option.group));
        group = option.group;
      }
      items.add(
        editorMenuItem<String>(option.id, option.label, icon: option.icon),
      );
    }
    final chosen = await showEditorMenu<String>(context, at, items);
    if (chosen != null) widget.onCreateUi?.call(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── Header ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
          child: Row(
            children: <Widget>[
              const Text(
                'SCENE TREE',
                style: TextStyle(
                  color: EditorTheme.primaryBright,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (widget.onToggleUiMode != null)
                Tooltip(
                  message: widget.uiModeOn
                      ? 'Back to the world'
                      : 'Edit the interface',
                  child: IconButton(
                    onPressed: () => widget.onToggleUiMode!(!widget.uiModeOn),
                    icon: Icon(
                      widget.uiModeOn ? Icons.public_off : Icons.phone_iphone,
                    ),
                    iconSize: 15,
                    color: widget.uiModeOn
                        ? EditorTheme.primaryBright
                        : EditorTheme.primary,
                    splashRadius: 16,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ),
              if (widget.onCreateUi != null)
                Tooltip(
                  message: 'Create UI',
                  child: Builder(
                    builder: (context) => IconButton(
                      onPressed: () => _showCreateUiMenu(context),
                      icon: const Icon(Icons.widgets_outlined),
                      iconSize: 15,
                      color: EditorTheme.primary,
                      splashRadius: 16,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ),
                ),
              Tooltip(
                message: 'Create group',
                child: IconButton(
                  onPressed: widget.onCreateGroup,
                  icon: const Icon(Icons.folder_open_rounded),
                  iconSize: 16,
                  color: EditorTheme.primary,
                  splashRadius: 16,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ),
              Tooltip(
                message: 'Create new entity',
                child: IconButton(
                  onPressed: widget.onCreateEntity,
                  icon: const Icon(Icons.add_rounded),
                  iconSize: 18,
                  color: EditorTheme.primary,
                  splashRadius: 16,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
          child: SizedBox(
            height: 26,
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value.trim()),
              style: const TextStyle(
                color: EditorTheme.textPrimary,
                fontSize: 11,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search name or component',
                hintStyle: const TextStyle(
                  color: EditorTheme.primaryMuted,
                  fontSize: 11,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 14,
                  color: EditorTheme.primaryMuted,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 26),
                suffixIcon: _query.isEmpty
                    ? null
                    : InkWell(
                        onTap: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: EditorTheme.primaryMuted,
                        ),
                      ),
                suffixIconConstraints: const BoxConstraints(minWidth: 26),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                filled: true,
                fillColor: EditorTheme.inputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        // ── Tree list ──────────────────────────────────────────────────────
        Expanded(
          child: SignalConsumer(
            signals: [
              widget.sceneState.activeScene,
              widget.sceneState.selectedEntity,
              widget.sceneState.multiSelectedIds,
              widget.sceneState.revision,
            ],
            builder: (context, _) {
              // Anything in the world — a piece of interface has no
              // transform, and the tree is where it is authored too.
              final allEntities = widget.world.entities
                  .where(
                    (e) =>
                        e.isActive &&
                        (e.getComponent<TransformComponent>() != null ||
                            _isUiEntity(e)),
                  )
                  .toList();

              if (allEntities.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No entities in the world.\nLoad a level to see entities here.',
                    style: TextStyle(
                      color: EditorTheme.primaryMuted,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                );
              }

              // Build children map from ChildrenComponent.childIds.
              final allIds = {for (final e in allEntities) e.id};
              final childrenMap = <EntityId, List<Entity>>{};
              for (final e in allEntities) {
                final cc = e.getComponent<ChildrenComponent>();
                if (cc == null || cc.childIds.isEmpty) continue;
                childrenMap[e.id] = cc.childIds
                    .where(allIds.contains)
                    .map(widget.world.getEntity)
                    .whereType<Entity>()
                    .where((c) => c.isActive)
                    .toList();
              }

              // Root = no ParentComponent or parentId not in current entity set.
              final roots = allEntities.where((e) {
                final pc = e.getComponent<ParentComponent>();
                return pc?.parentId == null || !allIds.contains(pc!.parentId);
              }).toList();

              final visibleEntities = <Entity>[];
              final rows = <Widget>[];
              if (_query.isNotEmpty) {
                // A flat list of matches: a match inside a collapsed group
                // should not be hidden by the group being collapsed.
                for (final entity in allEntities.where(_matches)) {
                  _buildSubtree(entity, 0, const {}, rows, visibleEntities);
                }
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Nothing matches "$_query".',
                      style: const TextStyle(
                        color: EditorTheme.primaryMuted,
                        fontSize: 11,
                      ),
                    ),
                  );
                }
              } else {
                for (final root in roots) {
                  _buildSubtree(root, 0, childrenMap, rows, visibleEntities);
                }
              }

              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: rows,
              );
            },
          ),
        ),
      ],
    );
  }

  void _buildSubtree(
    Entity entity,
    int depth,
    Map<EntityId, List<Entity>> childrenMap,
    List<Widget> rows,
    List<Entity> visibleEntities,
  ) {
    visibleEntities.add(entity);
    final children = childrenMap[entity.id] ?? [];
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedIds.contains(entity.id);
    final isSelected = widget.sceneState.selectedEntity.value?.id == entity.id;
    final isMultiSelected = widget.sceneState.isInMultiSelection(entity.id);

    rows.add(
      _EntityTreeRow(
        key: ValueKey(entity.id),
        entity: entity,
        depth: depth,
        hasChildren: hasChildren,
        isExpanded: isExpanded,
        isSelected: isSelected,
        isMultiSelected: isMultiSelected,
        sceneState: widget.sceneState,
        onTap: () {
          _anchorId = entity.id;
          widget.sceneState.selectEntity(entity);
        },
        onCtrlTap: () => widget.sceneState.toggleMultiSelect(entity),
        onShiftTap: () => _handleShiftTap(entity, visibleEntities),
        onToggleExpand: () => _toggleExpanded(entity.id),
        onDelete: () => widget.onDeleteEntity(entity),
        onCopy: () => widget.onCopyEntity(entity),
        onPaste: widget.onPasteEntity,
        onCreateGroupFrom: () => widget.onCreateGroupFrom(entity),
        onReparent: widget.onReparentEntity,
        onReorder: widget.onReorderEntity,
        viewToggles: widget.viewToggles,
        scope: widget.scope,
      ),
    );

    if (hasChildren && isExpanded) {
      for (final child in children) {
        _buildSubtree(child, depth + 1, childrenMap, rows, visibleEntities);
      }
    }
  }
}

// ── Entity tree row ───────────────────────────────────────────────────────────

enum _ContextAction { copy, paste, groupSelected, delete }

class _EntityTreeRow extends StatefulWidget {
  const _EntityTreeRow({
    super.key,
    required this.entity,
    required this.depth,
    required this.hasChildren,
    required this.isExpanded,
    required this.isSelected,
    required this.isMultiSelected,
    required this.sceneState,
    required this.onTap,
    required this.onCtrlTap,
    required this.onShiftTap,
    required this.onToggleExpand,
    required this.onDelete,
    required this.onCopy,
    required this.onPaste,
    required this.onCreateGroupFrom,
    required this.onReparent,
    this.onReorder,
    this.viewToggles,
    this.scope,
  });

  final Entity entity;
  final EntityViewToggles? viewToggles;

  /// The editor, for module actions, decorations and protection rules.
  /// Null keeps the tree exactly as it was.
  final EditorScope? scope;
  final int depth;
  final bool hasChildren;
  final bool isExpanded;
  final bool isSelected;
  final bool isMultiSelected;
  final EditorSceneState sceneState;
  final VoidCallback onTap;
  final VoidCallback onCtrlTap;
  final VoidCallback onShiftTap;
  final VoidCallback onToggleExpand;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onCreateGroupFrom;
  final void Function(Entity child, Entity newParent) onReparent;
  final void Function(Entity moved, Entity anchor, {required bool before})?
  onReorder;

  @override
  State<_EntityTreeRow> createState() => _EntityTreeRowState();
}

class _EntityTreeRowState extends State<_EntityTreeRow> {
  /// Where a drop would land: inside this entity, or between it and the
  /// sibling above or below.
  DropZone _dropZone = DropZone.onto;

  DropZone _zoneOf(Offset globalOffset) {
    if (widget.onReorder == null) return DropZone.onto;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return DropZone.onto;
    return dropZoneFor(box.globalToLocal(globalOffset).dy, box.size.height);
  }

  bool _isEditing = false;
  late TextEditingController _nameCtrl;
  final FocusNode _nameFocus = FocusNode();
  // Backs the rename row's KeyboardListener (Escape-to-cancel). Must be a
  // stable field, not created inline in build() — a fresh FocusNode() on
  // every rebuild while renaming is a leak (each one registers with
  // FocusManager and the previous one is discarded without being disposed).
  final FocusNode _escapeKeyFocus = FocusNode();
  bool _isDragOver = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _nameFocus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocus.removeListener(_onFocusChange);
    _nameFocus.dispose();
    _escapeKeyFocus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_nameFocus.hasFocus && _isEditing) _commitRename();
  }

  void _startEditing() {
    final display = widget.entity.name ?? 'Entity #${widget.entity.id}';
    _nameCtrl.text = display;
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nameFocus.requestFocus();
        _nameCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _nameCtrl.text.length,
        );
      }
    });
  }

  void _commitRename() {
    final newName = _nameCtrl.text.trim();
    if (newName.isNotEmpty) {
      widget.sceneState.renameEntity(widget.entity, newName);
    }
    setState(() => _isEditing = false);
  }

  void _cancelEditing() => setState(() => _isEditing = false);

  void _showContextMenu(BuildContext context, Offset globalPos) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final relRect = RelativeRect.fromRect(
      Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
      Offset.zero & overlay.size,
    );
    // Nothing is protected by the editor itself: a virtual camera is one
    // shot among several, as deletable as a spawn point. Modules add rules.
    final scope = widget.scope;
    final isProtected = scope?.isProtected(widget.entity) ?? false;
    final extra = scope?.sceneTreeActions ?? const <SceneTreeAction>[];

    showMenu<Object>(
      context: context,
      position: relRect,
      color: EditorTheme.menuBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: EditorTheme.border),
      ),
      items: [
        _menuItem(_ContextAction.copy, Icons.copy_rounded, 'Copy'),
        _menuItem(
          _ContextAction.paste,
          Icons.content_paste_rounded,
          'Paste',
          enabled: widget.sceneState.hasClipboard,
        ),
        _menuItem(
          _ContextAction.groupSelected,
          Icons.folder_open_rounded,
          'Group selected',
        ),
        const PopupMenuDivider(height: 1),
        _menuItem(
          _ContextAction.delete,
          Icons.delete_outline_rounded,
          'Delete',
          textColor: EditorTheme.error,
          enabled: !isProtected,
        ),
        if (extra.isNotEmpty) const PopupMenuDivider(height: 1),
        for (final a in extra)
          _menuItem(
            a,
            a.icon ?? Icons.extension_rounded,
            a.label,
            enabled: a.isEnabled?.call(widget.entity, scope!) ?? true,
          ),
      ],
    ).then((action) {
      if (!mounted) return;
      switch (action) {
        case _ContextAction.copy:
          widget.onCopy();
        case _ContextAction.paste:
          widget.onPaste();
        case _ContextAction.groupSelected:
          widget.onCreateGroupFrom();
        case _ContextAction.delete:
          widget.onDelete();
        case SceneTreeAction a:
          a.run(widget.entity, scope!);
        default:
          break;
      }
    });
  }

  PopupMenuItem<Object> _menuItem(
    Object value,
    IconData icon,
    String label, {
    bool enabled = true,
    Color textColor = EditorTheme.textSecondary,
  }) {
    return PopupMenuItem<Object>(
      value: value,
      enabled: enabled,
      height: 36,
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: enabled ? textColor : EditorTheme.primaryMuted,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: enabled ? textColor : EditorTheme.primaryMuted,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _viewToggleButtons(EntityViewToggles toggles) {
    final hidden = toggles.isHidden(widget.entity);
    final locked = toggles.isLocked(widget.entity);
    Widget button(IconData icon, bool active, String tip, VoidCallback onTap) =>
        Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Icon(
                icon,
                size: 13,
                color: active ? EditorTheme.primary : EditorTheme.primaryMuted,
              ),
            ),
          ),
        );
    return [
      const SizedBox(width: 4),
      button(
        hidden ? Icons.visibility_off : Icons.visibility,
        hidden,
        hidden ? 'Show (editor only)' : 'Hide (editor only)',
        () => toggles.onToggleHidden(widget.entity),
      ),
      button(
        locked ? Icons.lock : Icons.lock_open,
        locked,
        locked ? 'Unlock' : 'Lock against picking',
        () => toggles.onToggleLocked(widget.entity),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tag = widget.entity.getComponent<TagComponent>()?.tag ?? '';
    final displayName = widget.entity.name ?? 'Entity #${widget.entity.id}';
    final isGroup = widget.entity.hasComponent<ChildrenComponent>();
    final leftPad = 12.0 + widget.depth * 16.0;

    Widget row = GestureDetector(
      onDoubleTap: _startEditing,
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: InkWell(
        onTap: () {
          if (HardwareKeyboard.instance.isControlPressed) {
            widget.onCtrlTap();
          } else if (HardwareKeyboard.instance.isShiftPressed) {
            widget.onShiftTap();
          } else {
            widget.onTap();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          color: _isDragOver
              ? EditorTheme.dragOverBg
              : widget.isSelected
              ? EditorTheme.selectionBg
              : widget.isMultiSelected
              ? EditorTheme.multiSelectBg
              : Colors.transparent,
          padding: EdgeInsets.only(left: leftPad, right: 12, top: 7, bottom: 7),
          child: Row(
            children: <Widget>[
              // Expand/collapse chevron for groups with children.
              if (widget.hasChildren)
                GestureDetector(
                  // Opaque, and with room around it: a 14px glyph left the
                  // chevron all but unhittable — the tap fell through to
                  // the row and selected it instead of opening it.
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onToggleExpand,
                  child: SizedBox(
                    width: 18,
                    height: 22,
                    child: Icon(
                      widget.isExpanded
                          ? Icons.expand_more_rounded
                          : Icons.chevron_right_rounded,
                      size: 14,
                      color: EditorTheme.primary,
                    ),
                  ),
                )
              else
                const SizedBox(width: 18),
              Icon(
                // A piece of interface says what kind it is; a folder icon
                // on a Column would say only that it has children, which
                // the chevron beside it already says.
                uiIconFor(widget.entity) ??
                    (isGroup ? Icons.folder_rounded : _iconForTag(tag)),
                size: 14,
                color: widget.isSelected
                    ? EditorTheme.primary
                    : isGroup
                    ? EditorTheme.primary
                    : EditorTheme.primaryMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _isEditing
                    ? KeyboardListener(
                        focusNode: _escapeKeyFocus,
                        onKeyEvent: (event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.escape) {
                            _cancelEditing();
                          }
                        },
                        child: TextField(
                          controller: _nameCtrl,
                          focusNode: _nameFocus,
                          onEditingComplete: _commitRename,
                          style: const TextStyle(
                            color: EditorTheme.textPrimary,
                            fontSize: 12,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            filled: true,
                            fillColor: EditorTheme.inputBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(
                                color: EditorTheme.primaryActive,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(
                                color: EditorTheme.primaryActive,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(
                                color: EditorTheme.primaryActive,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Text(
                        displayName,
                        style: TextStyle(
                          color: widget.isSelected
                              ? EditorTheme.textPrimary
                              : EditorTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: widget.isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              if (!_isEditing && tag.isNotEmpty)
                Text(
                  tag,
                  style: const TextStyle(
                    color: EditorTheme.primaryMuted,
                    fontSize: 10,
                  ),
                ),
              if (!_isEditing && widget.viewToggles != null)
                ..._viewToggleButtons(widget.viewToggles!),
              if (!_isEditing)
                for (final d in widget.scope?.rowDecorations ?? const [])
                  ?d.build(context, widget.entity),
            ],
          ),
        ),
      ),
    );

    // Wrap with drag-and-drop support.
    return Draggable<Entity>(
      data: widget.entity,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: EditorTheme.selectionBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: EditorTheme.primaryActive),
          ),
          child: Text(
            displayName,
            style: const TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 12,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: DragTarget<Entity>(
        onWillAcceptWithDetails: (details) =>
            details.data.id != widget.entity.id,
        onAcceptWithDetails: (details) {
          final zone = _zoneOf(details.offset);
          setState(() {
            _isDragOver = false;
            _dropZone = DropZone.onto;
          });
          if (zone == DropZone.onto || widget.onReorder == null) {
            widget.onReparent(details.data, widget.entity);
          } else {
            widget.onReorder!(
              details.data,
              widget.entity,
              before: zone == DropZone.above,
            );
          }
        },
        onMove: (details) => setState(() {
          _isDragOver = true;
          _dropZone = _zoneOf(details.offset);
        }),
        onLeave: (_) => setState(() {
          _isDragOver = false;
          _dropZone = DropZone.onto;
        }),
        builder: (context, candidates, rejected) =>
            _isDragOver && _dropZone != DropZone.onto
            // A line where it would land, rather than the whole row lit up
            // as if it would go inside.
            ? DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: _dropZone == DropZone.above
                        ? const BorderSide(
                            color: EditorTheme.primaryBright,
                            width: 2,
                          )
                        : BorderSide.none,
                    bottom: _dropZone == DropZone.below
                        ? const BorderSide(
                            color: EditorTheme.primaryBright,
                            width: 2,
                          )
                        : BorderSide.none,
                  ),
                ),
                child: row,
              )
            : row,
      ),
    );
  }

  IconData _iconForTag(String tag) {
    return switch (tag.toLowerCase()) {
      'player' => Icons.person_rounded,
      'platform' => Icons.crop_landscape_rounded,
      'enemy' ||
      'walker' ||
      'jumper' ||
      'shooter' ||
      'flyer' ||
      'boss' => Icons.smart_toy_rounded,
      'coin' ||
      'collectible' ||
      'healthpack' ||
      'powerup' => Icons.stars_rounded,
      'hazard' || 'spike' => Icons.warning_rounded,
      'checkpoint' => Icons.flag_rounded,
      'projectile' => Icons.circle_rounded,
      _ => Icons.category_rounded,
    };
  }
}

/// Where a dragged entity would land relative to the row under it.
enum DropZone { above, onto, below }

/// How near a row's edge a drop has to be to mean "between these two"
/// rather than "inside this one".
///
/// A few pixels, not a share of the row: dropping something *into* a
/// container is the common move and has to be the easy one. A band that
/// was a share of the row left barely a third of it meaning what the whole
/// row plainly looks like it means, and re-parenting felt broken.
const double kTreeDropEdge = 5;

/// What a drop [dy] pixels down a row [height] tall means.
DropZone dropZoneFor(double dy, double height) {
  final edge = math.min(kTreeDropEdge, height / 3);
  if (dy < edge) return DropZone.above;
  if (dy > height - edge) return DropZone.below;
  return DropZone.onto;
}

/// Per-entity hide and lock for the scene tree, supplied by the Level
/// Designer while it is open. Viewing aids only: neither changes the entity.
class EntityViewToggles {
  const EntityViewToggles({
    required this.isHidden,
    required this.isLocked,
    required this.onToggleHidden,
    required this.onToggleLocked,
  });

  /// Whether the entity is hidden in the viewport.
  final bool Function(Entity entity) isHidden;

  /// Whether the entity is locked against picking.
  final bool Function(Entity entity) isLocked;

  /// Flips the entity's hidden state.
  final void Function(Entity entity) onToggleHidden;

  /// Flips the entity's locked state.
  final void Function(Entity entity) onToggleLocked;
}
