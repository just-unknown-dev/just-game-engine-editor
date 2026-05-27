import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';
import '../theme/editor_theme.dart';
import '../../core/state/editor_scene_state.dart';

/// Scrollable, hierarchical list of all ECS entities with a [TransformComponent].
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
  });

  final EditorSceneState sceneState;
  final World world;
  final VoidCallback onCreateEntity;
  final VoidCallback onCreateGroup;

  /// Called with the right-clicked entity to group it into a new parent.
  final void Function(Entity entity) onCreateGroupFrom;
  final void Function(Entity entity) onDeleteEntity;
  final void Function(Entity entity) onCopyEntity;
  final VoidCallback onPasteEntity;
  final void Function(Entity child, Entity newParent) onReparentEntity;

  @override
  State<SceneTreePanel> createState() => _SceneTreePanelState();
}

class _SceneTreePanelState extends State<SceneTreePanel> {
  final Set<EntityId> _expandedIds = {};
  EntityId? _anchorId;

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
        // ── Tree list ──────────────────────────────────────────────────────
        Expanded(
          child: ListenableBuilder(
            listenable: widget.sceneState,
            builder: (context, _) {
              final allEntities = widget.world
                  .query([TransformComponent])
                  .where((e) => e.isActive)
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
              for (final root in roots) {
                _buildSubtree(root, 0, childrenMap, rows, visibleEntities);
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
    final isSelected = widget.sceneState.selectedEntity?.id == entity.id;
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
  });

  final Entity entity;
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

  @override
  State<_EntityTreeRow> createState() => _EntityTreeRowState();
}

class _EntityTreeRowState extends State<_EntityTreeRow> {
  bool _isEditing = false;
  late TextEditingController _nameCtrl;
  final FocusNode _nameFocus = FocusNode();
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

    showMenu<_ContextAction>(
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
        case null:
          break;
      }
    });
  }

  PopupMenuItem<_ContextAction> _menuItem(
    _ContextAction value,
    IconData icon,
    String label, {
    bool enabled = true,
    Color textColor = EditorTheme.textSecondary,
  }) {
    return PopupMenuItem<_ContextAction>(
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
                  onTap: widget.onToggleExpand,
                  child: Icon(
                    widget.isExpanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 14,
                    color: EditorTheme.primary,
                  ),
                )
              else
                const SizedBox(width: 14),
              const SizedBox(width: 4),
              Icon(
                isGroup ? Icons.folder_rounded : _iconForTag(tag),
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
                        focusNode: FocusNode(),
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
          setState(() => _isDragOver = false);
          widget.onReparent(details.data, widget.entity);
        },
        onMove: (_) => setState(() => _isDragOver = true),
        onLeave: (_) => setState(() => _isDragOver = false),
        builder: (context, candidates, rejected) => row,
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
