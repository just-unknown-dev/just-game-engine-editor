import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../core/prefabs/prefab_instances.dart';
import '../../core/scope/editor_scope_services.dart';

/// The inspector's view of prefab instances: a section at the top of an
/// entity that is part of one ([section]) and a mark beside each field the
/// instance changes ([marks]), each with Revert and Apply.
abstract final class PrefabInspector {
  /// The section: which prefab, how much this instance changes, and what
  /// can be done about it.
  static InspectorSection get section => InspectorSection(
    id: 'prefab.instance',
    order: -10,
    appliesTo: (entity) => PrefabInstances.topOf(entity) != null,
    build: (context, entity, scope) => _InstanceSection(scope: scope, entity: entity),
  );

  /// The marks beside changed fields.
  static FieldAccessory get marks => FieldAccessory(id: 'prefab.overrides', build: _mark);

  // What the instance [top] changes, worked out once per scene revision:
  // every row asks.
  static final Expando<(int, jge.PrefabInstance)> _cache = Expando('prefabChanges');

  /// What [top]'s instance changes now (cached until the scene changes).
  static jge.PrefabInstance changesOf(EditorScope scope, jge.Entity top) {
    final revision = scope.sceneState.revision.value;
    final known = _cache[top];
    if (known != null && known.$1 == revision) return known.$2;
    final block = scope.prefabInstances.changesOf(top).block;
    _cache[top] = (revision, block);
    return block;
  }

  static Widget? _mark(FieldAccessoryContext c) {
    final top = PrefabInstances.topOf(c.entity);
    final link = c.entity.getComponent<jge.PrefabLink>();
    if (top == null || link == null) return null;
    final type = c.definition.type;
    // Where the top stands is where the instance is, not a change.
    if (identical(top, c.entity) && type == 'TransformComponent') return null;
    final block = changesOf(c.scope, top);
    final changed = [
      for (final f in c.fields)
        if (block.overrides.any((o) => o.target == link.path && o.component == type && o.field == f.name)) f.name,
    ];
    if (changed.isEmpty) return null;
    return _OverrideMark(
      fields: changed,
      onRevert: () {
        for (final field in changed) {
          c.scope.prefabInstances.revertField(top, link.path, type, field);
        }
      },
      onApply: () async {
        for (final field in changed) {
          await c.scope.prefabInstances.apply(top, only: (link.path, type, field));
        }
      },
    );
  }
}

/// A blue mark beside a field the instance changes: a menu to put it back
/// as the prefab has it, or to make it the prefab's.
class _OverrideMark extends StatelessWidget {
  const _OverrideMark({required this.fields, required this.onRevert, required this.onApply});

  final List<String> fields;
  final VoidCallback onRevert;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Changed in this instance: ${fields.join(', ')}',
    color: EditorTheme.menuBg,
    padding: EdgeInsets.zero,
    onSelected: (v) => v == 'revert' ? onRevert() : onApply(),
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'revert', height: 30, child: Text('Revert to the prefab', style: TextStyle(fontSize: 12))),
      PopupMenuItem(value: 'apply', height: 30, child: Text('Apply to the prefab', style: TextStyle(fontSize: 12))),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: EditorTheme.primaryBright, shape: BoxShape.circle),
      ),
    ),
  );
}

class _InstanceSection extends StatelessWidget {
  const _InstanceSection({required this.scope, required this.entity});

  final EditorScope scope;
  final jge.Entity entity;

  @override
  Widget build(BuildContext context) {
    final top = PrefabInstances.topOf(entity)!;
    final instances = scope.prefabInstances;
    final instance = top.getComponent<jge.PrefabInstanceComponent>()!;
    return SignalBuilder2<int, jge.EntityId?>(
      signal1: scope.sceneState.revision,
      signal2: instances.editing,
      builder: (context, _, editing, _) {
        final block = instance.missing ? instance.block : PrefabInspector.changesOf(scope, top);
        final topPath = instances.library.loaded(instance.path)?.root.id ?? '';
        final changes =
            PrefabInstances.changesBeyondPlacement(block, topPath).length +
            block.removed.length +
            block.addedComponents.length +
            block.removedComponents.length +
            block.names.length +
            block.enabled.length;
        final label = TextStyle(color: EditorTheme.textSecondary, fontSize: 11);
        return Container(
          margin: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: EditorTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: EditorTheme.primary.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 14, color: EditorTheme.primaryBright),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      instance.path,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: EditorTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                instance.missing
                    ? 'Its prefab could not be read: it stands empty, and is saved as it was.'
                    : changes == 0
                    ? 'Just as its prefab has it.'
                    : '$changes change${changes == 1 ? '' : 's'} in this instance (marked in blue).',
                style: label,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (!identical(top, entity))
                    EditorButton(label: 'Select the instance', onPressed: () => scope.sceneState.selectEntity(top)),
                  if (!instance.missing && editing != top.id)
                    EditorButton(label: 'Edit the prefab', icon: Icons.edit_outlined, onPressed: () => instances.edit(top)),
                  if (!instance.missing)
                    EditorButton(
                      label: 'Apply all',
                      onPressed: changes == 0 ? null : () => instances.apply(top),
                    ),
                  if (!instance.missing)
                    EditorButton(
                      label: 'Revert all',
                      onPressed: changes == 0 ? null : () => instances.revertAll(top),
                    ),
                  EditorButton(label: 'Unpack', onPressed: () => instances.unpack(top)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Over the viewport while an instance is edited as its prefab: what is
/// being edited, and the way out — with its changes applied to the prefab
/// (every instance gets them) or without.
class PrefabModeBanner extends StatelessWidget {
  const PrefabModeBanner({super.key, required this.scope});

  final EditorScope scope;

  @override
  Widget build(BuildContext context) {
    final instances = scope.prefabInstances;
    return SignalBuilder<jge.EntityId?>(
      signal: instances.editing,
      builder: (context, id, _) {
        final top = id == null ? null : scope.world.getEntity(id);
        final instance = top?.getComponent<jge.PrefabInstanceComponent>();
        if (top == null || instance == null) return const SizedBox.shrink();
        return Material(
          color: EditorTheme.panelBg,
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined, size: 15, color: EditorTheme.primaryBright),
                const SizedBox(width: 8),
                Text(
                  'Editing the prefab ${instance.path.substring(instance.path.lastIndexOf('/') + 1)}',
                  style: TextStyle(color: EditorTheme.textPrimary, fontSize: 12),
                ),
                const SizedBox(width: 12),
                EditorButton(
                  label: 'Apply and leave',
                  kind: EditorButtonKind.primary,
                  onPressed: () => instances.leave(apply: true),
                ),
                const SizedBox(width: 6),
                EditorButton(label: 'Leave', onPressed: () => instances.leave()),
              ],
            ),
          ),
        );
      },
    );
  }
}
