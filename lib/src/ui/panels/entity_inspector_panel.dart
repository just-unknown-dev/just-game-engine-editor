import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

import '../dialogs/add_component_picker.dart';
import '../../core/constants/editor_constants.dart';
import '../../core/level_map/tile_selection_ops.dart';
import '../../core/scope/editor_scope.dart';
import '../inspector/definition_section.dart';
import '../inspector/entity_header.dart';
import '../../core/state/editor_scene_state.dart';
import '../kit/kit.dart';

/// Inspector panel that shows and edits components on the selected entity.
class EntityInspectorPanel extends StatelessWidget {
  const EntityInspectorPanel({
    super.key,
    required this.sceneState,
    required this.world,
    required this.scope,
    required this.onDetachFromParent,
    required this.onGroupSelection,
    this.isLevelDesignerOpen = false,
  });

  final EditorSceneState sceneState;
  final World world;

  /// The editor: its definitions, field editors and extras.
  final EditorScope scope;
  final void Function(Entity entity) onDetachFromParent;
  final VoidCallback onGroupSelection;

  /// Whether the Level Designer is open. The tiles selected with Select
  /// tiles are shown only then: the selection outlives the designer, but
  /// what is done with it is the designer's.
  final bool isLevelDesignerOpen;

  @override
  Widget build(BuildContext context) {
    return SignalConsumer(
      signals: [
        sceneState.selectedEntity,
        sceneState.multiSelectedIds,
        sceneState.revision,
        scope.view.pinned,
        // The notices at the top read these, so the panel follows them.
        scope.view.locked,
        // Tiles selected with Select tiles, shown above the entity.
        scope.tiles.selection,
        scope.tiles.layerId,
      ],
      builder: (context, _) => _withTileSelection(_content()),
    );
  }

  /// [content], under the tiles selected with Select tiles, when there are
  /// any and the Level Designer is open: what they are, and what can be
  /// done with them.
  Widget _withTileSelection(Widget content) {
    if (!isLevelDesignerOpen || scope.tiles.selection.value.isEmpty) {
      return content;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TileSelectionCard(scope: scope, world: world),
        Divider(height: 1, color: EditorTheme.border),
        Expanded(child: content),
      ],
    );
  }

  /// What the panel shows for what is selected.
  Widget _content() {
    // Pinned: what is shown stops following what is selected, so an
    // entity's components can be read while picking something else.
    final pinnedId = scope.view.pinned.value;
    if (pinnedId != null) {
      final pinned = world.getEntity(pinnedId);
      if (pinned != null && pinned.isAlive) {
        return _EntityInspector(
          key: ValueKey('pinned:$pinnedId'),
          scope: scope,
          entity: pinned,
          sceneState: sceneState,
        );
      }
      // Pinned to something that has gone: let it go.
      scope.view.unpin();
    }
    if (sceneState.hasMultiSelection) {
      return _MultiSelectionPanel(
        sceneState: sceneState,
        onGroupSelection: onGroupSelection,
      );
    }
    final entity = sceneState.selectedEntity.value;
    if (entity == null) {
      return const EditorEmptyState(
        icon: Icons.ads_click_rounded,
        title: 'Nothing selected',
        hint:
            'Pick something in the level or in the list above to see what '
            'it is made of.',
      );
    }
    return _EntityInspector(
      key: ValueKey(entity.id),
      scope: scope,
      entity: entity,
      sceneState: sceneState,
    );
  }
}

// ── Tiles selected ────────────────────────────────────────────────────────────

/// The tiles selected with Select tiles: how many, on which layer, and
/// what can be done with them — the same as the viewport's right-click
/// menu and the tool's keys.
class _TileSelectionCard extends StatelessWidget {
  const _TileSelectionCard({required this.scope, required this.world});

  final EditorScope scope;
  final World world;

  void _say(String message) =>
      scope.log.log(message, source: 'tiles', mirrorToDebugger: false);

  @override
  Widget build(BuildContext context) => SignalBuilder<int>(
    // Tiles painted or cleared change what is selected.
    signal: scope.mapDocs.revision,
    builder: (context, _, _) => _build(),
  );

  Widget _build() {
    final cells = scope.tiles.selection.value.length;
    final n = TileSelectionOps.tileCount(scope, world);
    final target = scope.tiles.peek(world);
    final layer = target == null ? null : scope.tiles.peekLayer(target);
    Widget action(
      IconData icon,
      String tooltip,
      String shortcut,
      VoidCallback onTap,
    ) => EditorIconButton(
      icon: icon,
      tooltip: tooltip,
      shortcut: shortcut,
      onTap: onTap,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.highlight_alt,
                size: 14,
                color: EditorTheme.primaryBright,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  n == 0
                      ? '$cells empty cell${cells == 1 ? '' : 's'} selected'
                      : n == cells
                      ? '$n tile${n == 1 ? '' : 's'} selected'
                      : '$n tile${n == 1 ? '' : 's'} in $cells cells selected',
                  style: TextStyle(
                    color: EditorTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (target != null && layer != null)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(
                '${target.entity.name ?? 'Map'} ▸ ${layer.name}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
              ),
            ),
          if (n == 0 && layer != null)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 6),
              child: Text(
                '${layer.name} has no tiles there. Choose the layer the '
                'tiles are on in LAYERS, or start a selection on a tile: '
                'it picks their layer.',
                style: TextStyle(color: EditorTheme.warning, fontSize: 11),
              ),
            ),
          const SizedBox(height: 10),
          EditorButton(
            label: 'Make ${n == 1 ? 'it' : 'them'} an entity',
            icon: Icons.open_in_new,
            kind: EditorButtonKind.primary,
            onPressed: n == 0
                ? null
                : () => TileSelectionOps.makeEntity(scope, world, _say),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              action(
                Icons.content_copy_outlined,
                'Copy tiles',
                'Ctrl+C',
                () => TileSelectionOps.copy(scope, world, _say),
              ),
              action(
                Icons.content_cut,
                'Cut tiles',
                'Ctrl+X',
                () => TileSelectionOps.cut(scope, world, _say),
              ),
              action(
                Icons.delete_outline,
                'Delete tiles',
                'Delete',
                () => TileSelectionOps.delete(scope, world, _say),
              ),
              action(
                Icons.deselect,
                'Select none',
                'Esc',
                () => TileSelectionOps.deselect(scope, _say),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Multi-selection panel ─────────────────────────────────────────────────────

class _MultiSelectionPanel extends StatelessWidget {
  const _MultiSelectionPanel({
    required this.sceneState,
    required this.onGroupSelection,
  });

  final EditorSceneState sceneState;
  final VoidCallback onGroupSelection;

  @override
  Widget build(BuildContext context) {
    final count = sceneState.multiSelectedIds.value.length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '$count entities selected',
            style: TextStyle(
              color: EditorTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          EditorButton(
            label: 'Group $count entities',
            icon: Icons.folder_open_rounded,
            onPressed: onGroupSelection,
          ),
        ],
      ),
    );
  }
}

// ── Per-entity inspector ──────────────────────────────────────────────────────

class _EntityInspector extends StatelessWidget {
  const _EntityInspector({
    super.key,
    required this.entity,
    required this.sceneState,
    required this.scope,
  });

  final Entity entity;
  final EditorSceneState sceneState;
  final EditorScope scope;

  @override
  Widget build(BuildContext context) {
    // Tags are in the header, with the entity; the Tag component's own
    // card would only say the same thing again.
    final sections = buildComponentSections(
      entity: entity,
      sceneState: sceneState,
      scope: scope,
      hidden: const {TagComponent},
    );
    sections.add(
      AddComponentPicker(entity: entity, sceneState: sceneState, scope: scope),
    );
    // What the modules add, after the components and the picker.
    for (final section in scope.inspectorSections) {
      if (section.appliesTo?.call(entity) ?? true) {
        sections.add(
          Builder(builder: (context) => section.build(context, entity, scope)),
        );
      }
    }

    // Switched off: what it is made of is not running, so nothing here
    // can be changed by accident. Said in words as well as in ink — a
    // panel that quietly ignores every click is worse than one that
    // explains itself.
    final off = !entity.isActive;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Outside the part a switched-off entity greys out: its tick is
          // how it comes back on.
          EntityHeader(
            key: ValueKey(entity.id),
            entity: entity,
            scope: scope,
            sceneState: sceneState,
          ),
          const SizedBox(height: 6),
          // Why the panel is behaving oddly, said in the panel itself:
          // showing something other than the selection, refusing edits,
          // or sitting over an entity the viewport will not give up.
          if (off) ...[
            _Notice(
              icon: Icons.do_not_disturb_on_outlined,
              tint: EditorTheme.warning,
              message:
                  'Switched off in the game. Turn it on with its tick '
                  'above to edit it.',
            ),
            const SizedBox(height: 6),
          ],
          if (scope.view.isPinned(entity.id)) ...[
            _Notice(
              icon: Icons.push_pin_outlined,
              tint: EditorTheme.primaryBright,
              message:
                  'Pinned to ${entity.name ?? 'this entity'}. The inspector '
                  'stays here while you select other things.',
              actionLabel: 'Unpin',
              onAction: scope.view.unpin,
            ),
            const SizedBox(height: 6),
          ],
          if (scope.view.isLocked(entity.id)) ...[
            _Notice(
              icon: Icons.back_hand_outlined,
              tint: EditorTheme.textMuted,
              message:
                  'Locked against picking: it cannot be grabbed in the '
                  'viewport. Its fields still work.',
              actionLabel: 'Unlock',
              onAction: () => scope.view.toggleLocked(entity.id),
            ),
            const SizedBox(height: 6),
          ],
          IgnorePointer(
            ignoring: off,
            child: Opacity(
              opacity: off ? 0.45 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < sections.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    sections[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A line at the top of the inspector saying why it is behaving as it
/// is, and — where there is one — the way out.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.tint,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color tint;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
    decoration: BoxDecoration(
      color: tint.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: tint.withValues(alpha: 0.45)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 13, color: tint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: EditorTheme.textSecondary,
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              constraints: const BoxConstraints(minHeight: 24),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                actionLabel!,
                style: TextStyle(
                  color: tint,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
