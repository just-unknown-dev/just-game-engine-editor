import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../level_designer_session.dart';

/// Lists the layers present in the level, with visibility, lock and
/// "move selection here".
///
/// Visibility and lock are **editor-only**: hiding a layer must never change
/// what the level does, only what the author has to look at while working on
/// something else.
class LayersPanel extends StatelessWidget {
  const LayersPanel({super.key, required this.session});

  /// The designer session whose layer state this edits.
  final LevelDesignerSession session;

  @override
  Widget build(BuildContext context) => SignalBuilder<String?>(
    // Everything below follows the designer in use.
    signal: session.scope.activeDesigner,
    builder: (context, _, _) => _buildLayers(context),
  );

  Widget _buildLayers(BuildContext context) {
    return SignalBuilder3<String, Set<String>, Set<String>>(
      signal1: session.controller.activeLayerId,
      signal2: session.controller.hiddenLayers,
      signal3: session.controller.lockedLayers,
      builder: (context, activeId, hidden, locked, _) {
        final counts = _entityCountsByLayer();
        // Registered layers plus any found on an entity but never declared —
        // so a scene authored elsewhere still shows all of its layers.
        final ids = <String>{
          ...session.scope.layers.all.map((l) => l.id),
          ...counts.keys,
        }.toList()..sort((a, b) => _order(a).compareTo(_order(b)));

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            for (final id in ids)
              _LayerRow(
                id: id,
                count: counts[id] ?? 0,
                isActive: id == activeId,
                isHidden: hidden.contains(id),
                isLocked: locked.contains(id),
                onSelect: () => session.controller.activeLayerId.value = id,
                onToggleHidden: () {
                  final nowHidden = !hidden.contains(id);
                  session.controller.setLayerHidden(id, hidden: nowHidden);
                  _applyVisibility(id, visible: !nowHidden);
                },
                onToggleLocked: () => session.controller.setLayerLocked(
                  id,
                  locked: !locked.contains(id),
                ),
                onMoveSelection: () => _moveSelectionTo(id),
              ),
          ],
        );
      },
    );
  }

  int _order(String layerId) => session.scope.layers.orderOf(layerId);

  Map<String, int> _entityCountsByLayer() {
    final counts = <String, int>{};
    for (final entity in session.world.query([jge.LayerComponent])) {
      if (!entity.isActive) continue;
      final layer = entity.getComponent<jge.LayerComponent>()!;
      counts[layer.layerId] = (counts[layer.layerId] ?? 0) + 1;
    }
    return counts;
  }

  /// Hides or shows every renderable on [layerId].
  ///
  /// Writes `renderable.visible` rather than deactivating the entity: an
  /// inactive entity stops being simulated, which would change what the level
  /// does rather than just what the editor shows.
  void _applyVisibility(String layerId, {required bool visible}) {
    for (final entity in session.world.query([jge.LayerComponent])) {
      final layer = entity.getComponent<jge.LayerComponent>()!;
      if (layer.layerId != layerId) continue;
      layer.visible = visible;
      entity.getComponent<jge.RenderableComponent>()?.renderable.visible =
          visible;
    }
    session.sceneState.refresh();
  }

  void _moveSelectionTo(String layerId) {
    final state = session.sceneState;
    final targets = state.multiSelectedIds.value.isEmpty
        ? <jge.Entity>[
            if (state.selectedEntity.value != null) state.selectedEntity.value!,
          ]
        : state.multiSelectedIds.value
              .map(session.world.getEntity)
              .whereType<jge.Entity>()
              .toList();

    for (final entity in targets) {
      final layer = entity.getComponent<jge.LayerComponent>();
      if (layer != null) {
        layer.layerId = layerId;
      } else {
        entity.addComponent(jge.LayerComponent(layerId: layerId));
      }
    }
    state
      ..markDirty()
      ..refresh();
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.id,
    required this.count,
    required this.isActive,
    required this.isHidden,
    required this.isLocked,
    required this.onSelect,
    required this.onToggleHidden,
    required this.onToggleLocked,
    required this.onMoveSelection,
  });

  final String id;
  final int count;
  final bool isActive;
  final bool isHidden;
  final bool isLocked;
  final VoidCallback onSelect;
  final VoidCallback onToggleHidden;
  final VoidCallback onToggleLocked;
  final VoidCallback onMoveSelection;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? EditorTheme.selectionBg : Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              _IconToggle(
                icon: isHidden ? Icons.visibility_off : Icons.visibility,
                tooltip: isHidden ? 'Show layer' : 'Hide layer',
                isOn: !isHidden,
                onTap: onToggleHidden,
              ),
              _IconToggle(
                icon: isLocked ? Icons.lock : Icons.lock_open,
                tooltip: isLocked ? 'Unlock layer' : 'Lock layer',
                isOn: !isLocked,
                onTap: onToggleLocked,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  id,
                  style: TextStyle(
                    color: isActive
                        ? EditorTheme.textBright
                        : EditorTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  color: EditorTheme.textMuted,
                  fontSize: 11,
                ),
              ),
              _IconToggle(
                icon: Icons.move_down,
                tooltip: 'Move selection to this layer',
                isOn: false,
                onTap: onMoveSelection,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconToggle extends StatelessWidget {
  const _IconToggle({
    required this.icon,
    required this.tooltip,
    required this.isOn,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 14,
            color: isOn ? EditorTheme.textSecondary : EditorTheme.textMuted,
          ),
        ),
      ),
    );
  }
}
