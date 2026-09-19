import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/constants/editor_constants.dart';
import '../../core/scope/editor_scope.dart';
import '../../core/state/editor_scene_state.dart';
import 'component_extras.dart';
import 'field_editor.dart';

/// One inspector section per component on [entity], built from each
/// component's definition. A component with no definition (and no legacy
/// descriptor) is not shown: it cannot be saved either.
List<Widget> buildComponentSections({
  required jge.Entity entity,
  required EditorSceneState sceneState,
  required EditorScope scope,
}) => [
  for (final component in entity.components)
    if (scope.definitionForInspector(component) case final definition?)
      DefinitionSection(
        component: component,
        definition: definition,
        scope: scope,
        onDelete: () {
          entity.removeComponentByType(component.componentType);
          sceneState.markDirty();
          sceneState.refresh();
        },
        onChanged: () {
          sceneState.syncEntityNode(entity);
          sceneState.markDirty();
          sceneState.refresh();
        },
      ),
];

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
  });

  final jge.Component component;
  final jge.ComponentDefinition definition;
  final EditorScope scope;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  jge.ComponentHints get hints => definition.hints;
  ComponentEditorExtras? get extras => scope.extras.forType(definition.type);

  @override
  Widget build(BuildContext context) {
    final accent = hints.accentColor;
    final actions = extras?.actions ?? const <InspectorAction>[];
    final section = extras?.section;
    return Container(
      decoration: BoxDecoration(
        color: EditorTheme.dialogBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EditorTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              border: accent != null
                  ? Border(left: BorderSide(color: accent, width: 3))
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                if (hints.icon != null) ...[
                  Icon(
                    hints.icon,
                    size: 13,
                    color: accent ?? EditorTheme.primaryMutedLight,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    hints.name ?? definition.type,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: EditorTheme.primaryMutedLight,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                for (final action in actions)
                  Tooltip(
                    message: action.label,
                    child: InkWell(
                      onTap: () async {
                        await action.run(context, component);
                        onChanged();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          action.icon ?? Icons.bolt,
                          size: 14,
                          color: EditorTheme.primaryMuted,
                        ),
                      ),
                    ),
                  ),
                if (hints.deletable)
                  GestureDetector(
                    onTap: onDelete,
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: EditorTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: EditorTheme.border),
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
                      style: const TextStyle(
                        color: EditorTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ..._fieldWidgets(),
                if (section != null) ...[
                  const SizedBox(height: 8),
                  section(context, component),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _shown(jge.SchemaField f) {
    final hint = hints.fields[f.name];
    if (hint == null) return true;
    return hint.visible && (hint.visibleWhen?.call(component) ?? true);
  }

  /// Ungrouped fields first, then each hinted group under a header. Names a
  /// group lists that the definition lacks are ignored.
  List<Widget> _fieldWidgets() {
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
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            entry.key.toUpperCase(),
            style: const TextStyle(
              color: EditorTheme.primaryMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
      out.addAll(_rows(fields));
    }
    if (out.isEmpty) {
      out.add(
        const Text(
          'No visible properties',
          style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
        ),
      );
    }
    return out;
  }

  List<Widget> _rows(List<jge.SchemaField> fields) => [
    for (final field in fields)
      Padding(padding: const EdgeInsets.only(bottom: 6), child: _row(field)),
  ];

  Widget _row(jge.SchemaField field) {
    final hint = hints.fields[field.name] ?? const jge.FieldHint();
    final ctx = FieldEditorContext(
      field: field,
      hint: hint,
      value: field.read(component),
      component: component,
      readOnly: !hint.editable || field.write == null,
      editors: scope.fieldEditors,
      onChanged: (next) {
        field.write?.call(component, next);
        onChanged();
      },
    );
    final custom = extras?.fieldEditors[field.name];
    return custom != null ? custom(ctx) : scope.fieldEditors.build(ctx);
  }
}
