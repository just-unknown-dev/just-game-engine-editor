import '../../core/state/scene_mode_filters.dart';
import '../timeline/field_key_button.dart';
import '../timeline/timeline_session.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/constants/editor_constants.dart';
import '../../core/theme/editor_metrics.dart';
import '../kit/kit.dart';
import 'package:just_signals/just_signals.dart';
import '../../core/scope/editor_scope.dart';
import '../../core/serialization/unknown_components.dart';
import '../../core/state/editor_scene_state.dart';
import '../level_designer/state/editor_commands.dart';
import '../level_designer/state/editor_history.dart';
import 'component_extras.dart';
import 'component_reorder.dart';
import '../widgets/scrubbable_number_field.dart';
import 'field_editor.dart';
import 'field_rows.dart';
import 'live_preview.dart';

/// One inspector section per component on [entity], built from each
/// component's definition. A component with no definition (and no legacy
/// descriptor) is not shown: it cannot be saved either. The exception is
/// what the file named but nothing could read, which is shown — read-only —
/// because it *is* saved.
///
/// [history] and [world] are the scene's unless given: a workspace editing
/// a document of its own (a screen) passes its own, with the [sceneState]
/// it keeps for it, so its edits undo there and never mark the scene dirty.
/// Only the scene's entities can be keyed on a timeline.
///
/// [hidden] leaves out components of those types, for a workspace whose
/// own panels already show them — a screen's links, in its hierarchy.
List<Widget> buildComponentSections({
  required jge.Entity entity,
  required EditorSceneState sceneState,
  required EditorScope scope,
  EditorHistory? history,
  jge.World? world,
  Set<Type> hidden = const {},
}) {
  final ownDocument = history != null;
  final undo = history ?? scope.history;
  // In the entity's order — rearranged by dragging a card or from its ⋮
  // menu, and saved so — with Transform always first.
  final components = entity.components.toList();
  final ordered = [
    for (final c in components)
      if (isPinnedComponent(c.componentType)) c,
    for (final c in components)
      if (!isPinnedComponent(c.componentType)) c,
  ];
  String titleOf(jge.ComponentDefinition d) => d.hints.name ?? d.type;
  final titles = <Type, String>{
    for (final c in ordered)
      if (scope.definitionForInspector(c) case final d?)
        c.componentType: titleOf(d),
  };
  // The cards that move, in the order shown: what a move is measured by.
  final shown = [
    for (final c in ordered)
      if (!hidden.contains(c.runtimeType) &&
          c is! UnknownComponents &&
          !isPinnedComponent(c.componentType) &&
          titles.containsKey(c.componentType))
        c.componentType,
  ];
  void move(Type type, {Type? before, Type? after}) {
    final now = reorderedTypes(entity, type, before: before, after: after);
    if (now == null) return;
    undo.push(
      ReorderComponentsCommand(
        entity: entity,
        before: entity.componentTypes,
        after: now,
        sceneState: sceneState,
        label: 'Move ${titles[type] ?? 'component'}',
      ),
    );
  }

  return [
    for (final component in ordered)
      if (hidden.contains(component.runtimeType))
        const SizedBox.shrink()
      else if (component is UnknownComponents)
        UnknownComponentsCard(component: component)
      else if (scope.definitionForInspector(component) case final definition?)
        // Keyed by type, so a card that moves keeps its own fields' state.
        ComponentDropZone(
          key: ValueKey(component.componentType),
          entity: entity,
          type: component.componentType,
          onDrop: (dragged, {required above}) => above
              ? move(dragged, before: component.componentType)
              : move(dragged, after: component.componentType),
          child: DefinitionSection(
            entity: entity,
            component: component,
            definition: definition,
            scope: scope,
            history: undo,
            sceneState: sceneState,
            world: world,
            timelineKeys: !ownDocument,
            placement: isPinnedComponent(component.componentType)
                ? null
                : ComponentPlacement(
                    entity: entity,
                    type: component.componentType,
                    title: titleOf(definition),
                    shown: shown,
                    move: move,
                  ),
            // Through the history, so a removed component comes back on
            // undo with every value it had, in its place.
            onDelete: () => undo.push(
              RemoveComponentCommand(
                entity: entity,
                component: component,
                sceneState: sceneState,
              ),
            ),
            onChanged: () {
              sceneState.syncEntityNode(entity);
              sceneState.markDirty();
              // Before the refresh, so what is drawn is what was keyed.
              if (!ownDocument) TimelineSession.of(scope).captureEdits();
              sceneState.refresh();
            },
          ),
        ),
  ];
}

/// What a scene named that nothing registered can read: listed, not
/// editable, and saved back exactly as it came.
class UnknownComponentsCard extends StatelessWidget {
  const UnknownComponentsCard({super.key, required this.component});

  final UnknownComponents component;

  @override
  Widget build(BuildContext context) => EditorCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.help_outline,
              size: EditorMetrics.iconSm,
              color: EditorTheme.warning,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                component.types.join(', '),
                style: TextStyle(
                  color: EditorTheme.textPrimary,
                  fontSize: EditorMetrics.fontBody,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Nothing registered can read this. It is kept and saved as it '
          'was; register what defines it to edit it here.',
          style: TextStyle(
            color: EditorTheme.textMuted,
            fontSize: EditorMetrics.fontLabel,
          ),
        ),
      ],
    ),
  );
}

/// The inspector for one component: header from its hints, a control per
/// field from the scope's editors, and whatever extras the editor adds.
class DefinitionSection extends StatelessWidget {
  const DefinitionSection({
    super.key,
    required this.component,
    required this.definition,
    required this.scope,
    required this.onDelete,
    required this.onChanged,
    this.entity,
    this.history,
    this.sceneState,
    this.world,
    this.timelineKeys = true,
    this.placement,
  });

  /// Whose component this is; with it, fields get a timeline key button.
  final jge.Entity? entity;

  /// Its place among the entity's components: with it, the header has a
  /// grip to drag the card by and a ⋮ menu to move it. Null for a card
  /// that stays where it is — Transform, first.
  final ComponentPlacement? placement;

  /// Where edits are recorded, the scene's unless given.
  final EditorHistory? history;

  /// What an edit refreshes, the scene's unless given.
  final EditorSceneState? sceneState;

  /// Where names are offered from, the scene's world unless given.
  final jge.World? world;

  /// Whether fields offer a timeline key button — only the scene's
  /// entities can be keyed.
  final bool timelineKeys;
  final jge.Component component;
  final jge.ComponentDefinition definition;
  final EditorScope scope;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  jge.ComponentHints get hints => definition.hints;
  ComponentEditorExtras? get extras => scope.extras.forType(definition.type);

  @override
  Widget build(BuildContext context) => SignalBuilder<Set<String>>(
    signal: scope.chrome.collapsedComponents,
    builder: (context, collapsed, _) => SignalBuilder<Set<String>>(
      // Which groups are open: a fold redraws the card.
      signal: scope.chrome.flippedGroups,
      builder: (context, _, _) =>
          _card(context, collapsed.contains(definition.type)),
    ),
  );

  Widget _card(BuildContext context, bool collapsed) {
    final accent = hints.accentColor;
    final actions = extras?.actions ?? const <InspectorAction>[];
    final section = extras?.section;
    final summary = collapsed ? extras?.summary?.call(component) : null;
    final title = hints.name ?? definition.type;
    return Container(
      decoration: BoxDecoration(
        color: EditorTheme.dialogBg,
        borderRadius: BorderRadius.circular(EditorMetrics.radiusMd),
        border: Border.all(
          color: EditorTheme.borderStrong.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              border: accent != null
                  ? Border(left: BorderSide(color: accent, width: 3))
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(2, 2, 4, 2),
            child: Row(
              children: [
                if (placement case final place?)
                  ComponentDragGrip(placement: place),
                // Folds the card to this line — on every entity, so a
                // component read once and left alone stays out of the way.
                EditorIconButton(
                  icon: collapsed
                      ? Icons.chevron_right_rounded
                      : Icons.expand_more_rounded,
                  tooltip: collapsed ? 'Show $title' : 'Fold $title',
                  onTap: () => scope.chrome.toggleCollapsed(definition.type),
                ),
                if (hints.icon != null) ...[
                  Icon(
                    hints.icon,
                    size: 13,
                    color: accent ?? EditorTheme.primaryMutedLight,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: title,
                          style: TextStyle(
                            color: EditorTheme.primaryMutedLight,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        // Folded, what matters about it, on the same line.
                        if (summary != null && summary.isNotEmpty)
                          TextSpan(
                            text: '   $summary',
                            style: TextStyle(
                              color: EditorTheme.textMuted,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final action in actions)
                  EditorIconButton(
                    icon: action.icon ?? Icons.bolt,
                    tooltip: action.label,
                    onTap: () async {
                      await action.run(context, component);
                      onChanged();
                    },
                  ),
                if (placement case final place?)
                  ComponentPlaceMenu(placement: place),
                if (hints.deletable)
                  EditorIconButton(
                    icon: Icons.close,
                    tooltip: 'Remove $title (undo brings it back)',
                    onTap: onDelete,
                  ),
              ],
            ),
          ),
          if (!collapsed) ...[
            Divider(height: 1, color: EditorTheme.border),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hints.description case final d? when d.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        d,
                        style: TextStyle(
                          color: EditorTheme.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ..._fieldWidgets(context),
                  if (section != null) ...[
                    const SizedBox(height: 8),
                    section(context, component),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _shown(jge.SchemaField f) {
    final hint = hints.fields[f.name];
    if (hint == null) return true;
    final mode = sceneState?.editingMode ?? jge.SceneMode.twoD;
    return hint.visible &&
        SceneModeFilters.fieldShown(hint, mode) &&
        (hint.visibleWhen?.call(component) ?? true);
  }

  /// Ungrouped fields first, then each hinted group under a header that
  /// folds it. Names a group lists that the definition lacks are ignored;
  /// a group none of whose fields is shown is left out, header and all.
  List<Widget> _fieldWidgets(BuildContext context) {
    final byName = {for (final f in definition.fields) f.name: f};
    final groups = hints.fieldGroups ?? const <String, List<String>>{};
    final grouped = {for (final names in groups.values) ...names};
    final loose = [
      for (final f in definition.fields)
        if (!grouped.contains(f.name) && _shown(f)) f,
    ];
    final out = <Widget>[..._rows(loose)];
    for (final entry in groups.entries) {
      final fields = [
        for (final n in entry.value)
          if (byName[n] case final f? when _shown(f)) f,
      ];
      if (fields.isEmpty) continue;
      if (out.isNotEmpty) out.add(const SizedBox(height: 6));
      final folded = scope.chrome.isGroupFolded(
        definition.type,
        entry.key,
        startsFolded: hints.foldedGroups.contains(entry.key),
      );
      out.add(_groupHeader(entry.key, folded, fields.length));
      if (folded) continue;
      if (extras?.groupLeading[entry.key] case final leading?) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: leading(context, component),
          ),
        );
      }
      out.addAll(_rows(fields));
    }
    if (out.isEmpty) {
      out.add(
        Text(
          'No visible properties',
          style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
        ),
      );
    }
    return out;
  }

  /// A group's title, which folds and opens it; folded, it says how many
  /// settings are inside.
  Widget _groupHeader(String name, bool folded, int count) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: InkWell(
      onTap: () => scope.chrome.toggleGroup(definition.type, name),
      borderRadius: BorderRadius.circular(3),
      child: Row(
        children: [
          Icon(
            folded ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
            size: 12,
            color: EditorTheme.primaryMuted,
          ),
          const SizedBox(width: 2),
          Text(
            name.toUpperCase(),
            style: TextStyle(
              color: EditorTheme.primaryMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          if (folded) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 9),
            ),
          ],
        ],
      ),
    ),
  );

  /// One row per field — except fields a [jge.FieldRowHint] gathers, which
  /// share the row where the first of them would be.
  List<Widget> _rows(List<jge.SchemaField> fields) {
    final out = <Widget>[];
    final done = <String>{};
    for (final field in fields) {
      if (done.contains(field.name)) continue;
      final together = _rowMates(field, fields);
      done.addAll([for (final f in together.$2) f.name]);
      final description = together.$1 == null
          ? hints.fields[field.name]?.description
          : null;
      Widget row = together.$1 == null
          ? _row(field)
          : _sharedRow(together.$1!, together.$2);
      // What the setting does, on a hover that lingers.
      if (description != null && description.isNotEmpty) {
        row = Tooltip(
          message: description,
          waitDuration: const Duration(milliseconds: 700),
          child: row,
        );
      }
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _withKeyButton(row, together.$2),
        ),
      );
    }
    return out;
  }

  /// [row] with a key button after it, when a timeline is open that could
  /// animate its [fields] on this entity.
  Widget _withKeyButton(Widget row, List<jge.SchemaField> fields) {
    final owner = entity;
    if (owner == null || !timelineKeys) return row;
    final session = TimelineSession.of(scope);
    if (session.asset.value == null || session.bindingFor(owner) == null) {
      return row;
    }
    final keyable = [
      for (final f in fields)
        if (jge.PropertyAccess.canAnimate(f)) f,
    ];
    if (keyable.isEmpty ||
        TimelineSession.unrecorded.contains(definition.type)) {
      return row;
    }
    return Row(
      children: [
        Expanded(child: row),
        FieldKeyButton(
          session: session,
          entity: owner,
          component: component,
          fields: keyable,
        ),
      ],
    );
  }

  bool _isNumber(jge.SchemaField f) =>
      f.kind.id == jge.FieldTypes.decimal.id ||
      f.kind.id == jge.FieldTypes.integer.id;

  /// The row hint [field] belongs to and the fields of it that are here,
  /// in the hint's order; `(null, [field])` when it stands alone. A field
  /// with an editor of its own is never gathered.
  (jge.FieldRowHint?, List<jge.SchemaField>) _rowMates(
    jge.SchemaField field,
    List<jge.SchemaField> among,
  ) {
    for (final row in hints.fieldRows) {
      if (!row.cells.containsKey(field.name)) continue;
      final mates = [
        for (final name in row.cells.keys)
          for (final f in among)
            if (f.name == name &&
                _isNumber(f) &&
                extras?.fieldEditors[name] == null)
              f,
      ];
      if (mates.length > 1 && mates.contains(field)) return (row, mates);
    }
    return (null, [field]);
  }

  Widget _sharedRow(jge.FieldRowHint row, List<jge.SchemaField> fields) {
    final contexts = [for (final f in fields) _context(f)];
    double shown(FieldEditorContext c) {
      final raw = (c.value as num?)?.toDouble() ?? 0.0;
      return c.hint.unit == jge.AngleUnit.degrees ? raw * 180 / math.pi : raw;
    }

    final values = [for (final c in contexts) shown(c)];
    return AxesFieldRow(
      label: row.label,
      axes: [for (final f in fields) row.cells[f.name]!],
      values: values,
      scrubConfig: const NumberScrubConfig(),
      scrubConfigs: [
        for (final c in contexts)
          c.scrub ??
              NumberScrubConfig(
                integer: c.field.kind.id == jge.FieldTypes.integer.id,
              ),
      ],
      readOnly: contexts.any((c) => c.readOnly),
      onChanged: (next) {
        for (var i = 0; i < next.length; i++) {
          if (next[i] == values[i]) continue;
          final c = contexts[i];
          final stored = c.hint.unit == jge.AngleUnit.degrees
              ? next[i] * math.pi / 180
              : next[i];
          c.onChanged(
            c.field.kind.id == jge.FieldTypes.integer.id
                ? stored.round()
                : stored,
          );
        }
      },
    );
  }

  Widget _row(jge.SchemaField field) {
    final ctx = _context(field);
    final custom = extras?.fieldEditors[field.name];
    return custom != null ? custom(ctx) : scope.fieldEditors.build(ctx);
  }

  FieldEditorContext _context(jge.SchemaField field) {
    final hint = hints.fields[field.name] ?? const jge.FieldHint();
    return FieldEditorContext(
      field: field,
      hint: hint,
      value: field.read(component),
      component: component,
      readOnly: !hint.editable || field.write == null,
      editors: scope.fieldEditors,
      world: world,
      sceneState: sceneState,
      scope: scope,
      entityNames: () => [
        for (final e in (world ?? scope.world).query([jge.TransformComponent]))
          if (e.isActive && e.name != null) e.name!,
      ],
      preview: field.write == null
          ? null
          : LivePreview(
              read: () => field.read(component),
              write: (v) {
                field.write!(component, v);
                (sceneState ?? scope.sceneState).refresh();
              },
              scope: scope,
              history: history ?? scope.history,
            ),
      onChanged: (next) {
        final write = field.write;
        if (write == null) return;
        // Through the history, so an inspector edit is undoable like every
        // other edit. `ComponentFieldCommand` merges consecutive writes to
        // the same field, which is what makes a scrub one undo step
        // instead of one per pixel.
        (history ?? scope.history).push(
          ComponentFieldCommand(
            label: 'Change ${hint.label ?? field.name}',
            component: component,
            write: (c, v) => write(c, v),
            before: field.read(component),
            after: next,
            // The state this section edits, not always the scene's: the
            // refresh on undo has to reach whoever shows it.
            sceneState: sceneState ?? scope.sceneState,
          ),
        );
        onChanged();
      },
    );
  }
}
