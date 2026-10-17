import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../../core/scope/editor_scope_services.dart';

/// The 3-D designer's GROUPS section: every group in the scene — an empty
/// entity holding others — with its eye and lock, groups inside groups
/// indented. Click one to select it, the arrow to select what it holds;
/// Group (Ctrl+G) and Ungroup (Ctrl+Shift+G) below.
class Groups3DPanel extends StatelessWidget {
  const Groups3DPanel({super.key, required this.scope});

  /// The editor whose groups it lists.
  final EditorScope scope;

  @override
  Widget build(BuildContext context) {
    final state = scope.sceneState;
    return SignalBuilder3<int, Set<jge.EntityId>, Set<jge.EntityId>>(
      signal1: state.revision,
      signal2: scope.view.hidden,
      signal3: scope.view.locked,
      builder: (context, _, _, _, _) => SignalBuilder<jge.Entity?>(
        signal: state.selectedEntity,
        builder: (context, selected, _) {
          final groups = _groups();
          final ops = scope.entities;
          return Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      'No groups yet: select things and press Ctrl+G',
                      style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
                    ),
                  ),
                for (final (group, depth) in groups)
                  _GroupRow(
                    scope: scope,
                    group: group,
                    depth: depth,
                    selected: selected?.id == group.id,
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: EditorButton(
                        label: 'Group',
                        icon: Icons.folder_outlined,
                        onPressed: state.hasAnySelection ? ops.groupSelection : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: EditorButton(
                        label: 'Ungroup',
                        icon: Icons.folder_off_outlined,
                        onPressed: selected != null && ops.isGroup(selected)
                            ? () => ops.ungroup(selected)
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The groups, in the tree's order, each with how deep it is among
  /// groups.
  List<(jge.Entity, int)> _groups() {
    final world = scope.world;
    final ops = scope.entities;
    final out = <(jge.Entity, int)>[];
    void visit(jge.Entity e, int depth) {
      final group = ops.isGroup(e);
      if (group) out.add((e, depth));
      for (final id in e.getComponent<jge.ChildrenComponent>()?.childIds ?? const <jge.EntityId>[]) {
        final child = world.getEntity(id);
        if (child != null) visit(child, group ? depth + 1 : depth);
      }
    }

    for (final id in scope.sceneState.rootOrder(world)) {
      final root = world.getEntity(id);
      if (root != null) visit(root, 0);
    }
    return out;
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.scope,
    required this.group,
    required this.depth,
    required this.selected,
  });

  final EditorScope scope;
  final jge.Entity group;
  final int depth;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final view = scope.view;
    final hidden = view.isHidden(group.id);
    final locked = view.isLocked(group.id);
    final children = group.getComponent<jge.ChildrenComponent>()?.childIds ?? const [];
    final muted = EditorTheme.textMuted;
    return Material(
      color: selected ? EditorTheme.selectionBg : Colors.transparent,
      child: InkWell(
        onTap: () => scope.sceneState.selectEntity(group),
        child: Padding(
          padding: EdgeInsets.fromLTRB(4.0 + depth * 12, 2, 2, 2),
          child: Row(
            children: [
              EditorIconButton(
                icon: hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                tooltip: hidden ? 'Show it' : 'Hide it',
                size: 22,
                iconSize: 14,
                onTap: () => view.toggleHidden(group.id),
              ),
              EditorIconButton(
                icon: locked ? Icons.lock_outline : Icons.lock_open_outlined,
                tooltip: locked ? 'Unlock it' : 'Lock it: not picked in the view',
                size: 22,
                iconSize: 14,
                onTap: () => view.toggleLocked(group.id),
              ),
              const SizedBox(width: 4),
              Icon(Icons.folder_outlined, size: 14, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.name ?? 'group',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hidden
                        ? muted
                        : selected
                        ? EditorTheme.textBright
                        : EditorTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              Text('${children.length}', style: TextStyle(color: muted, fontSize: 10)),
              EditorIconButton(
                icon: Icons.select_all,
                tooltip: 'Select what it holds',
                size: 22,
                iconSize: 14,
                onTap: () => _selectContents(children),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectContents(List<jge.EntityId> ids) {
    final state = scope.sceneState;
    final inside = [
      for (final id in ids) ?scope.world.getEntity(id),
    ];
    if (inside.isEmpty) return;
    state.clearMultiSelection();
    if (inside.length > 1) {
      for (final e in inside) {
        state.toggleMultiSelect(e);
      }
    }
    state.selectEntity(inside.first);
  }
}
