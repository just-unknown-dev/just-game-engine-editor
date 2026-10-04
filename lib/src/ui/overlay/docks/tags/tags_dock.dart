import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import '../../../../core/constants/editor_constants.dart';
import '../../../../core/scope/editor_scope.dart';
import '../../../../core/tags/tag_references.dart';
import '../../../../core/tags/tag_refactor.dart';
import '../../../dialogs/scene_actions_dialogs.dart' show promptSceneName;
import '../../../inspector/tag_field_editors.dart' show TagHighlight;
import '../../../kit/kit.dart';
import '../../../widgets/editor_menu.dart';

/// The project's tags: every one, what it looks like, who carries it, and
/// renaming or deleting one everywhere it is used.
class TagsDock extends StatefulWidget {
  const TagsDock({super.key, required this.scope});

  final EditorScope scope;

  @override
  State<TagsDock> createState() => _TagsDockState();
}

class _TagsDockState extends State<TagsDock> {
  String _query = '';

  EditorScope get scope => widget.scope;

  @override
  Widget build(BuildContext context) => SignalBuilder<jge.TagLibrary>(
    signal: scope.tags.library,
    // The counts follow the scene too: a tag added in the inspector shows
    // here at once.
    builder: (context, _, _) => SignalBuilder<int>(
      signal: scope.sceneState.revision,
      builder: (context, _, _) => _body(context),
    ),
  );

  Widget _body(BuildContext context) {
    final tags = scope.tags;
    final q = _query.trim().toLowerCase();
    final names = [
      for (final name in tags.names)
        if (q.isEmpty || name.toLowerCase().contains(q)) name,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              EditorSearchField(
                hint: 'Filter tags',
                width: 200,
                onChanged: (text) => setState(() => _query = text),
              ),
              const SizedBox(width: 8),
              EditorButton(
                label: 'New tag',
                icon: Icons.add_rounded,
                onPressed: () => _create(context),
              ),
              const Spacer(),
              if (!tags.hasFile)
                Flexible(
                  child: Tooltip(
                    message: tags.path,
                    child: Text(
                      'No tag file yet: these are the tags code declares and '
                      'the scenes carry. The first change writes it.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: EditorTheme.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ),
              if (tags.loadError case final error?)
                Flexible(
                  child: Text(
                    error,
                    style: TextStyle(color: EditorTheme.error, fontSize: 10.5),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: names.isEmpty
              ? EditorEmptyState(
                  icon: Icons.label_outline,
                  title: q.isEmpty ? 'No tags yet' : 'No tag matches',
                  hint:
                      'Tags are what cameras, triggers and systems find '
                      'entities by. Make one here, or in any tag field.',
                  actionLabel: q.isEmpty ? 'New tag' : null,
                  onAction: q.isEmpty ? () => _create(context) : null,
                )
              : ListView.builder(
                  itemCount: names.length,
                  itemBuilder: (context, i) => _row(context, names[i]),
                ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, String name) {
    final tags = scope.tags;
    final def = tags[name];
    final color = tags.colorOf(name);
    final carriers = scope.world.allTagged(name, includeInactive: true);
    final spawned = tags.spawnersGiving(name);
    final listed = def != null;
    final locked = def?.isDeclared ?? false;
    return MouseRegion(
      onEnter: (_) => TagHighlight.set(scope, name, true),
      onExit: (_) => TagHighlight.set(scope, name, false),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: EditorTheme.border.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            Tooltip(
              message: listed ? 'Change the colour' : 'Only in a spawner',
              child: InkWell(
                onTapDown: listed
                    ? (d) => _pickColour(context, d.globalPosition, def)
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: EditorTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (locked) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message:
                          'Declared by ${def!.declaredBy}: its code looks for '
                          'this tag by name, so it cannot be renamed or '
                          'deleted here.',
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 11,
                        color: EditorTheme.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: 170,
              child: Text(
                [
                  carriers.isEmpty
                      ? 'on nothing here'
                      : '${carriers.length} in this scene',
                  if (spawned.isNotEmpty)
                    'spawned: ${spawned.map((s) => s.displayName).join(', ')}',
                ].join(' · '),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: EditorTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: listed ? () => _describe(context, def) : null,
                child: Text(
                  (def?.description.isNotEmpty ?? false)
                      ? def!.description
                      : (listed ? 'Add a description…' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: (def?.description.isNotEmpty ?? false)
                        ? EditorTheme.textSecondary
                        : EditorTheme.textMuted,
                    fontSize: 11,
                    fontStyle: (def?.description.isNotEmpty ?? false)
                        ? FontStyle.normal
                        : FontStyle.italic,
                  ),
                ),
              ),
            ),
            EditorIconButton(
              icon: Icons.select_all_rounded,
              tooltip: 'Select everything tagged "$name"',
              onTap: carriers.isEmpty ? null : () => _select(carriers),
            ),
            EditorIconButton(
              icon: Icons.drive_file_rename_outline_rounded,
              tooltip: locked
                  ? 'Declared by code: cannot be renamed'
                  : 'Rename everywhere',
              onTap: locked || !listed ? null : () => _rename(context, name),
            ),
            EditorIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: locked
                  ? 'Declared by code: cannot be deleted'
                  : 'Delete everywhere',
              onTap: locked || !listed ? null : () => _delete(context, name),
            ),
          ],
        ),
      ),
    );
  }

  void _select(List<jge.Entity> entities) {
    final selectable = [
      for (final e in entities)
        if (scope.sceneState.canSelect(e)) e,
    ];
    if (selectable.isEmpty) return;
    scope.sceneState.selectRange(selectable, anchor: selectable.first);
  }

  Future<void> _create(BuildContext context) async {
    final name = await promptSceneName(
      context,
      title: 'New tag',
      actionLabel: 'Create',
      hint: 'e.g. enemy',
      validate: (text) => scope.tags.problemWithNew(text.trim()),
    );
    if (name == null) return;
    scope.tags.create(name.trim());
  }

  Future<void> _describe(BuildContext context, jge.TagDefinition def) async {
    final text = await promptSceneName(
      context,
      title: 'Describe "${def.name}"',
      actionLabel: 'Save',
      initialValue: def.description,
      hint: 'What carries it, and who looks for it',
      validate: (_) => null,
    );
    if (text == null) return;
    scope.tags.update(def.copyWith(description: text.trim()));
  }

  Future<void> _pickColour(
    BuildContext context,
    Offset at,
    jge.TagDefinition def,
  ) async {
    const palette = [
      Color(0xFF4FC3F7),
      Color(0xFFFF8A65),
      Color(0xFF81C784),
      Color(0xFFBA68C8),
      Color(0xFFFFD54F),
      Color(0xFF4DB6AC),
      Color(0xFFF06292),
      Color(0xFF9575CD),
      Color(0xFFAED581),
      Color(0xFF7986CB),
      Color(0xFFE57373),
      Color(0xFF90A4AE),
    ];
    final chosen = await showEditorMenu<Color>(context, at, [
      for (final c in palette)
        editorMenuItem(
          c,
          c == def.color ? 'Current' : '',
          icon: Icons.circle,
          iconColor: c,
        ),
    ]);
    if (chosen == null) return;
    scope.tags.update(def.copyWith(color: chosen));
  }

  Future<void> _rename(BuildContext context, String from) async {
    final to = await promptSceneName(
      context,
      title: 'Rename "$from"',
      actionLabel: 'Next',
      initialValue: from,
      hint: 'The new name',
      validate: (text) {
        final name = text.trim();
        if (name == from) return 'That is its name already.';
        final problem = jge.TagNames.problemWith(name);
        if (problem != null) return problem;
        if (scope.tags[name]?.isDeclared ?? false) {
          return '"$name" is declared by code; rename into another name.';
        }
        return null;
      },
    );
    if (to == null || !context.mounted) return;
    final refactor = TagRefactor(scope);
    final plan = refactor.plan(from, renameTo: to.trim());
    final merges = scope.tags.library.value.contains(to.trim());
    final go = await _preview(
      context,
      plan,
      title: merges
          ? 'Merge "$from" into "${to.trim()}"'
          : 'Rename "$from" to "${to.trim()}"',
      confirm: merges ? 'Merge' : 'Rename',
      danger: false,
    );
    if (!go) return;
    await refactor.apply(plan);
  }

  Future<void> _delete(BuildContext context, String tag) async {
    final refactor = TagRefactor(scope);
    final plan = refactor.plan(tag);
    final go = await _preview(
      context,
      plan,
      title: 'Delete "$tag"',
      confirm: 'Delete',
      danger: true,
    );
    if (!go) return;
    await refactor.apply(plan);
  }

  /// Lists what [plan] will change, and asks.
  Future<bool> _preview(
    BuildContext context,
    TagChangePlan plan, {
    required String title,
    required String confirm,
    required bool danger,
  }) async {
    Widget group(String heading, List<TagUse> uses, {String? note}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$heading — ${uses.length}',
            style: TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (note != null)
            Text(
              note,
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 10.5),
            ),
          for (final use in uses.take(8))
            Text(
              '  ${use.owner}: ${use.where}'
              '${use.kind == TagUseKind.reference && !plan.isRename ? '  (left as it is)' : ''}',
              style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
            ),
          if (uses.length > 8)
            Text(
              '  …and ${uses.length - 8} more',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
            ),
        ],
      ),
    );

    final references = plan.references.length;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => EditorAlert(
        title: title,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 360),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (plan.all.isEmpty)
                  Text(
                    'Nothing in the project uses it: only the tag list '
                    'changes.',
                    style: TextStyle(
                      color: EditorTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                if (plan.openUses.isNotEmpty)
                  group(
                    'The open scene (${plan.openScene})',
                    plan.openUses,
                    note:
                        'Changed now, as one step you can undo; saved when '
                        'you save the scene.',
                  ),
                for (final e in plan.scenes.entries)
                  group(
                    'Scene ${e.key}',
                    e.value,
                    note: 'Rewritten on disk, after a backup.',
                  ),
                if (plan.isRename)
                  for (final e in plan.timelines.entries)
                    group('Timeline ${e.key}', e.value),
                if (!plan.isRename && references > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '$references ${references == 1 ? 'field names' : 'fields name'} '
                      'the tag. They are left as they are — the Problems dock '
                      'will list them, so nothing breaks silently.',
                      style: TextStyle(
                        color: EditorTheme.warning,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          EditorButton(
            label: 'Cancel',
            kind: EditorButtonKind.ghost,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          EditorButton(
            label: confirm,
            kind: danger ? EditorButtonKind.danger : EditorButtonKind.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}
