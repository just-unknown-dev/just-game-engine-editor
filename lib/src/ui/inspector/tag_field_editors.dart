import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';

/// Inspector editors for tags, spawners and targets: pickers over what the
/// project knows, never a box to type a name into and hope.
abstract final class TagFieldEditors {
  static Map<String, FieldEditorBuilder> get all => {
    jge.FieldTypes.tagRef.id: _tagRef,
    jge.FieldTypes.tagList.id: _tagList,
    jge.FieldTypes.spawnerRef.id: _spawnerRef,
    jge.FieldTypes.target.id: (c) => TargetEditorRow(ctx: c),
  };

  static const String _none = '';

  static Widget _tagRef(FieldEditorContext c) {
    final current = c.value as String? ?? '';
    if (c.readOnly || c.scope == null) {
      return ReadonlyRow(label: c.label, value: current);
    }
    return _labelled(
      c.label,
      TagPicker(
        scope: c.scope!,
        world: c.world,
        value: current,
        allowNone: true,
        onChanged: c.onChanged,
      ),
    );
  }

  static Widget _tagList(FieldEditorContext c) {
    final current = [...(c.value as List? ?? const []).whereType<String>()];
    if (c.readOnly || c.scope == null) {
      return ReadonlyRow(label: c.label, value: current.join(', '));
    }
    return _labelled(
      c.label,
      TagChips(
        scope: c.scope!,
        world: c.world,
        tags: current,
        onChanged: (next) => c.onChanged(next),
      ),
    );
  }

  static Widget _spawnerRef(FieldEditorContext c) {
    final current = c.value as String? ?? '';
    final spawners = c.scope?.spawners.value ?? const <jge.Spawner>[];
    if (c.readOnly) return ReadonlyRow(label: c.label, value: current);
    final known = spawners.any((s) => s.id == current);
    return _labelled(
      c.label,
      EditorDropdown<String>(
        value: current,
        hint: 'Nothing',
        searchable: spawners.length > 6,
        options: [
          for (final s in spawners)
            EditorDropdownOption(
              value: s.id,
              label: s.displayName,
              detail: s.tags.map((t) => '#$t').join(' '),
            ),
          if (!known && current.isNotEmpty)
            EditorDropdownOption(
              value: current,
              label: current,
              detail: 'not a spawner',
            ),
        ],
        onChanged: c.onChanged,
      ),
    );
  }

  static Widget _labelled(String label, Widget child) => Row(
    children: [
      SizedBox(
        width: InspectorField.labelWidth,
        child: Text(label, style: InspectorField.labelStyle),
      ),
      Expanded(child: child),
    ],
  );

  /// How a tag is used, for the muted text beside it in a picker.
  static String usageOf(EditorScope scope, jge.World? world, String tag) {
    final here = (world ?? scope.world)
        .allTagged(tag, includeInactive: true)
        .length;
    final spawned = scope.tags.spawnersGiving(tag);
    return [
      if (here > 0) '$here here',
      if (spawned.isNotEmpty)
        'spawned: ${spawned.map((s) => s.displayName).join(', ')}',
    ].join(' · ');
  }

  /// The tags to offer, coloured and counted. [current] is kept listed when
  /// the project does not know it, so opening a picker never rewrites it.
  static List<EditorDropdownOption<String>> tagOptions(
    EditorScope scope,
    jge.World? world, {
    String current = '',
    bool allowNone = false,
    Set<String> exclude = const {},
  }) {
    final tags = scope.tags;
    final names = tags.names;
    return [
      if (allowNone) const EditorDropdownOption(value: _none, label: '(none)'),
      for (final name in names)
        if (!exclude.contains(name))
          EditorDropdownOption(
            value: name,
            label: name,
            color: tags.colorOf(name),
            detail: usageOf(scope, world, name),
          ),
      if (current.isNotEmpty && !names.contains(current))
        EditorDropdownOption(
          value: current,
          label: current,
          color: tags.colorOf(current),
          detail: 'not in the tag list',
        ),
    ];
  }

  /// What the entry for a typed name says: that it will be made, or why
  /// it cannot be.
  static String Function(String typed) createLabel(EditorScope scope) =>
      (typed) => scope.tags.problemWithNew(typed) ?? 'Create tag "$typed"';

  /// [picked], made into a tag first if it is new. Null when it is new and
  /// cannot be one.
  static String? accept(EditorScope scope, String picked) {
    if (picked.isEmpty || scope.tags.isKnown(picked)) return picked;
    return scope.tags.create(picked)?.name;
  }
}

/// One tag from the project's list, with a way to make a new one.
class TagPicker extends StatelessWidget {
  const TagPicker({
    super.key,
    required this.scope,
    required this.value,
    required this.onChanged,
    this.world,
    this.allowNone = false,
    this.hint = 'Pick a tag',
    this.exclude = const {},
    this.isExpanded = true,
    this.height,
  });

  final EditorScope scope;
  final jge.World? world;
  final String value;
  final ValueChanged<String> onChanged;
  final bool allowNone;
  final String hint;
  final Set<String> exclude;
  final bool isExpanded;
  final double? height;

  @override
  Widget build(BuildContext context) => SignalBuilder<jge.TagLibrary>(
    signal: scope.tags.library,
    builder: (context, _, _) => EditorDropdown<String>(
      value: value,
      hint: hint,
      isExpanded: isExpanded,
      height: height,
      searchable: true,
      options: TagFieldEditors.tagOptions(
        scope,
        world,
        current: value,
        allowNone: allowNone,
        exclude: exclude,
      ),
      customValue: (typed) => typed,
      customLabel: TagFieldEditors.createLabel(scope),
      onChanged: (picked) {
        final tag = TagFieldEditors.accept(scope, picked);
        if (tag != null) onChanged(tag);
      },
    ),
  );
}

/// An entity's tags as chips, each with a remove button, and an "add" menu.
class TagChips extends StatelessWidget {
  const TagChips({
    super.key,
    required this.scope,
    required this.tags,
    required this.onChanged,
    this.world,
  });

  final EditorScope scope;
  final jge.World? world;
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) => SignalBuilder<jge.TagLibrary>(
    signal: scope.tags.library,
    builder: (context, _, _) => Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in tags)
          TagChip(
            tag: tag,
            color: scope.tags.colorOf(tag),
            unknown: !scope.tags.isKnown(tag),
            onHover: (inside) => TagHighlight.set(scope, tag, inside),
            onRemove: () {
              // The chip goes without the pointer leaving it, so nothing
              // else would put the ring out.
              TagHighlight.set(scope, tag, false);
              onChanged([
                for (final t in tags)
                  if (t != tag) t,
              ]);
            },
          ),
        TagPicker(
          scope: scope,
          world: world,
          value: '',
          hint: tags.isEmpty ? 'Add a tag' : 'Add',
          exclude: tags.toSet(),
          isExpanded: false,
          height: 22,
          onChanged: (tag) {
            if (tag.isNotEmpty && !tags.contains(tag)) {
              onChanged([...tags, tag]);
            }
          },
        ),
      ],
    ),
  );
}

/// One tag: its colour, its name, and a way to take it off.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.tag,
    required this.color,
    this.onRemove,
    this.unknown = false,
    this.onHover,
  });

  final String tag;
  final Color color;
  final VoidCallback? onRemove;

  /// The pointer came in (true) or left (false) — for ringing the tag's
  /// entities in the viewport while it is over the chip.
  final ValueChanged<bool>? onHover;

  /// Not in the project's tag list: drawn dashed-looking and muted.
  final bool unknown;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: onHover == null ? null : (_) => onHover!(true),
    onExit: onHover == null ? null : (_) => onHover!(false),
    child: _chip(),
  );

  Widget _chip() => Tooltip(
    message: unknown ? '"$tag" is not in the project\'s tag list' : '#$tag',
    child: Container(
      height: 22,
      padding: EdgeInsets.only(left: 7, right: onRemove == null ? 8 : 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: unknown ? 0.08 : 0.18),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: unknown ? EditorTheme.warning : color.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            tag,
            style: TextStyle(
              color: unknown ? EditorTheme.warning : EditorTheme.textPrimary,
              fontSize: 11,
            ),
          ),
          if (onRemove != null)
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: EditorTheme.textMuted,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Rings a tag's entities in the viewport while something points at it.
abstract final class TagHighlight {
  static void set(EditorScope scope, String tag, bool on) {
    if (on) {
      scope.highlightedTag.value = tag;
    } else if (scope.highlightedTag.value == tag) {
      scope.highlightedTag.value = null;
    }
  }
}

/// Who a component means: Self, an entity by name, or a tag — the kind as a
/// switch, the name or tag from a list.
class TargetEditorRow extends StatefulWidget {
  const TargetEditorRow({super.key, required this.ctx});

  final FieldEditorContext ctx;

  @override
  State<TargetEditorRow> createState() => _TargetEditorRowState();
}

class _TargetEditorRowState extends State<TargetEditorRow> {
  // Held here for a target that names nobody yet: saved, "nobody" has no
  // kind, and the switch would otherwise jump back to Entity.
  jge.EntityTargetKind? _kind;

  FieldEditorContext get c => widget.ctx;

  jge.EntityTarget get _value => c.value is jge.EntityTarget
      ? c.value! as jge.EntityTarget
      : jge.EntityTarget.none;

  List<jge.EntityTargetKind> get _kinds {
    final kind = c.field.kind;
    return kind is jge.EntityTargetFieldType
        ? kind.kinds
        : const [jge.EntityTargetKind.name, jge.EntityTargetKind.tag];
  }

  jge.EntityTargetKind get _shownKind {
    final value = _value;
    if (!value.isNone) return value.kind;
    return _kind ??
        (_kinds.contains(jge.EntityTargetKind.tag)
            ? jge.EntityTargetKind.tag
            : _kinds.first);
  }

  void _setKind(jge.EntityTargetKind kind) {
    setState(() => _kind = kind);
    if (kind == _value.kind && !_value.isNone) return;
    c.onChanged(
      kind == jge.EntityTargetKind.self
          ? const jge.EntityTarget.self()
          : jge.EntityTarget.none,
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    if (c.readOnly) {
      return ReadonlyRow(
        label: c.label,
        value: value.isNone ? '(nobody)' : value.label,
      );
    }
    final kind = _shownKind;
    final scope = c.scope;
    final Widget picker = switch (kind) {
      jge.EntityTargetKind.self => Text(
        'This entity',
        style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
      ),
      jge.EntityTargetKind.tag when scope != null => TagPicker(
        scope: scope,
        world: c.world,
        value: value.isTag ? value.value : '',
        hint: 'Pick a tag',
        onChanged: (tag) => c.onChanged(
          tag.isEmpty ? jge.EntityTarget.none : jge.EntityTarget.tag(tag),
        ),
      ),
      jge.EntityTargetKind.tag => Text(value.label),
      jge.EntityTargetKind.name => _entityPicker(value),
    };
    return Row(
      children: [
        SizedBox(
          width: InspectorField.labelWidth,
          child: Tooltip(
            message: c.hint.description ?? '',
            child: Text(c.label, style: InspectorField.labelStyle),
          ),
        ),
        // The picker where every row's control starts; what kind of thing
        // it picks beside it, the way a unit sits beside a number.
        Expanded(child: picker),
        const SizedBox(width: 6),
        EditorSegmented<jge.EntityTargetKind>(
          value: kind,
          options: [
            for (final k in _kinds)
              (
                k,
                switch (k) {
                  jge.EntityTargetKind.self => 'Self',
                  jge.EntityTargetKind.name => 'Entity',
                  jge.EntityTargetKind.tag => 'Tag',
                },
              ),
          ],
          onChanged: _setKind,
        ),
      ],
    );
  }

  Widget _entityPicker(jge.EntityTarget value) {
    final current = value.isName ? value.value : '';
    final names = <String>{
      ...?c.entityNames?.call(),
      if (current.isNotEmpty) current,
    }.toList()..sort();
    return EditorDropdown<String>(
      value: current,
      hint: 'Pick an entity',
      searchable: true,
      options: [
        for (final n in names) EditorDropdownOption(value: n, label: n),
      ],
      // The entity may not exist yet: one the game spawns is named here
      // before it is ever in the scene.
      customValue: (typed) => typed,
      onChanged: (name) => c.onChanged(
        name.isEmpty ? jge.EntityTarget.none : jge.EntityTarget.name(name),
      ),
    );
  }
}
