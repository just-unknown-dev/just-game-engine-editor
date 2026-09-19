import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

import '../dialogs/add_component_picker.dart';
import '../../core/constants/editor_constants.dart';
import '../../core/scope/editor_scope.dart';
import '../inspector/definition_section.dart';
import '../../core/state/editor_scene_state.dart';

/// Inspector panel that shows and edits components on the selected entity.
class EntityInspectorPanel extends StatelessWidget {
  const EntityInspectorPanel({
    super.key,
    required this.sceneState,
    required this.world,
    required this.scope,
    required this.onDetachFromParent,
    required this.onGroupSelection,
  });

  final EditorSceneState sceneState;
  final World world;

  /// The editor: its definitions, field editors and extras.
  final EditorScope scope;
  final void Function(Entity entity) onDetachFromParent;
  final VoidCallback onGroupSelection;

  @override
  Widget build(BuildContext context) {
    return SignalConsumer(
      signals: [
        sceneState.selectedEntity,
        sceneState.multiSelectedIds,
        sceneState.revision,
      ],
      builder: (context, _) {
        if (sceneState.hasMultiSelection) {
          return _MultiSelectionPanel(
            sceneState: sceneState,
            onGroupSelection: onGroupSelection,
          );
        }
        final entity = sceneState.selectedEntity.value;
        if (entity == null) {
          return const Center(
            child: Text(
              'No entity selected',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 12),
            ),
          );
        }
        return _EntityInspector(
          key: ValueKey(entity.id),
          scope: scope,
          entity: entity,
          sceneState: sceneState,
        );
      },
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
            style: const TextStyle(
              color: EditorTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onGroupSelection,
            style: ElevatedButton.styleFrom(
              backgroundColor: EditorTheme.buttonBg,
              foregroundColor: EditorTheme.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            icon: const Icon(Icons.folder_open_rounded, size: 14),
            label: Text(
              'Group $count entities',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
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
    final sections = buildComponentSections(
      entity: entity,
      sceneState: sceneState,
      scope: scope,
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            sections[i],
          ],
        ],
      ),
    );
  }
}
