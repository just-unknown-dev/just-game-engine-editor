import 'package:flutter/material.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

/// Inspector editors for input actions (`InputDefinitions.actionType` and
/// `actionListType`): a picker over the actions the project's input assets
/// have, never a box to type a name into and hope.
///
/// A name the assets have no action for stays shown and is marked, so
/// opening the inspector never rewrites it, and one can still be typed: the
/// action may be added later. In a project with no input asset, one action
/// is typed in a plain text box, and a list's names in its Add box.
abstract final class InputActionFieldEditors {
  /// The editors, by field type id.
  static Map<String, FieldEditorBuilder> get all => {
    jge.InputDefinitions.actionType.id: (c) => InputActionFieldRow(ctx: c),
    jge.InputDefinitions.actionListType.id: (c) =>
        InputActionListFieldRow(ctx: c),
  };

  /// What a picker says of a name no input asset has.
  static const String unknownDetail = 'not an input action';
}

/// One name an input action goes by in the project, as a picker offers it.
class ProjectInputAction {
  /// The action [name], in the maps of [paths], of [type].
  const ProjectInputAction({
    required this.name,
    required this.paths,
    required this.type,
  });

  /// What a component saves and the input system copies it by: `jump`.
  final String name;

  /// Every `map/action` path with this name, in the order the assets list
  /// them: `player/jump`, and `ui/jump` when another map has one too.
  final List<String> paths;

  /// The value the first of them gives: a button, an axis, a vector.
  final jge.ActionValueType type;

  /// What the picker shows beside the name: its maps and its type.
  String get detail {
    final maps = [for (final p in paths) p.substring(0, p.indexOf('/'))];
    return '${maps.join(', ')} · ${type.name}';
  }
}

/// The actions of the project's input assets — every `.input.json` under
/// `assets/`, read with just_inputs — for the inspector's pickers.
///
/// Read again when the [index] has scanned since (a save in the Input
/// Actions editor, a file dropped in): only a file whose time or size
/// changed is read again. A file that does not read is passed over.
class ProjectInputActions {
  /// The actions in the input assets [index] lists.
  ProjectInputActions(this.index);

  /// The project's asset files.
  final AssetIndex index;

  int? _revision;
  final Map<String, _ReadFile> _read = {};
  List<String> _files = const [];
  List<ProjectInputAction> _actions = const [];

  /// The input assets found, project-relative: those that read and those
  /// that do not.
  List<String> get files {
    _refresh();
    return _files;
  }

  /// Every action name, in the order the assets list them; one entry for a
  /// name several maps share.
  List<ProjectInputAction> get actions {
    _refresh();
    return _actions;
  }

  /// Whether [value] names an action: its name, or its `map/action` path.
  bool knows(String value) =>
      actions.any((a) => a.name == value || a.paths.contains(value));

  void _refresh() {
    final revision = index.revision.value;
    if (revision == _revision) return;
    _revision = revision;
    final ending = '.${jge.InputActionAsset.extension}';
    final entries = [
      for (final e in index.entries)
        if (!e.isDirectory &&
            !e.isPackage &&
            e.path.toLowerCase().endsWith(ending))
          e,
    ];
    final kept = <String>{};
    for (final e in entries) {
      kept.add(e.path);
      final had = _read[e.path];
      if (had != null && had.modified == e.modified && had.size == e.size) {
        continue;
      }
      _read[e.path] = (
        modified: e.modified,
        size: e.size,
        asset: _parse(index.absolute(e.path)),
      );
    }
    _read.removeWhere((path, _) => !kept.contains(path));
    _files = List.unmodifiable([for (final e in entries) e.path]);
    final byName = <String, ProjectInputAction>{};
    for (final path in _files) {
      final asset = _read[path]?.asset;
      if (asset == null) continue;
      for (final ref in asset.actions) {
        final name = ref.action.name;
        final had = byName[name];
        byName[name] = ProjectInputAction(
          name: name,
          paths: [...?had?.paths, ref.path],
          type: had?.type ?? ref.action.type,
        );
      }
    }
    _actions = List.unmodifiable(byName.values);
  }

  static jge.InputActionAsset? _parse(String file) {
    try {
      return jge.InputActionAsset.parse(File(file).readAsStringSync());
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }
}

/// One input asset as last read: when, how big, and what it held (null
/// when it does not read).
typedef _ReadFile = ({
  DateTime? modified,
  int size,
  jge.InputActionAsset? asset,
});

/// The project's input actions on an [EditorScope], read from the files its
/// [ScopeAssets.assetIndex] lists.
extension ScopeInputActions on EditorScope {
  /// What the inspector's input action pickers offer.
  ProjectInputActions get inputActions =>
      service<ProjectInputActions>(() => ProjectInputActions(assetIndex));
}

/// The options a picker of [actions] lists for [current]: every action,
/// and [current] marked when no asset has it.
List<EditorDropdownOption<String>> _options(
  ProjectInputActions actions,
  String current, {
  Set<String> exclude = const {},
}) => [
  for (final a in actions.actions)
    if (!exclude.contains(a.name))
      EditorDropdownOption(value: a.name, label: a.name, detail: a.detail),
  if (current.isNotEmpty && !actions.knows(current))
    EditorDropdownOption(
      value: current,
      label: current,
      detail: InputActionFieldEditors.unknownDetail,
    ),
];

Widget _label(FieldEditorContext c) => SizedBox(
  width: InspectorField.labelWidth,
  child: Tooltip(
    message: c.hint.description ?? '',
    child: Text(c.label, style: InspectorField.labelStyle),
  ),
);

/// A mark beside a name no input asset has: why it may find nothing.
Widget _unknownMark(String name) => Tooltip(
  message: '"$name" is not an action in the project\'s input assets',
  child: Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Icon(
      Icons.warning_amber_rounded,
      size: 14,
      color: EditorTheme.warning,
    ),
  ),
);

/// One input action, picked from the project's ([InputActionFieldEditors]).
class InputActionFieldRow extends StatelessWidget {
  /// The row for the field [ctx] edits.
  const InputActionFieldRow({super.key, required this.ctx});

  /// The field, its value and how to write it.
  final FieldEditorContext ctx;

  @override
  Widget build(BuildContext context) {
    final c = ctx;
    final current = c.value is String ? c.value! as String : '';
    if (c.readOnly) return ReadonlyFieldRow(label: c.label, value: current);
    final scope = c.scope;
    if (scope == null) return _textRow(c, current);
    final actions = scope.inputActions;
    return ValueListenableBuilder<int>(
      valueListenable: actions.index.revision,
      builder: (context, _, _) {
        if (actions.files.isEmpty) return _textRow(c, current);
        return Row(
          children: [
            _label(c),
            Expanded(
              child: EditorDropdown<String>(
                value: current,
                hint: 'Pick an action',
                searchable: true,
                options: _options(actions, current),
                customValue: (typed) => typed.trim(),
                onChanged: (name) {
                  if (name != current) c.onChanged(name);
                },
              ),
            ),
            if (current.isNotEmpty && !actions.knows(current))
              _unknownMark(current),
          ],
        );
      },
    );
  }

  static Widget _textRow(FieldEditorContext c, String current) => TextFieldRow(
    label: c.label,
    initialValue: current,
    onSubmitted: (text) => c.onChanged(text.trim()),
  );
}

/// Several input actions: each a chip that can be taken off, and a picker
/// that adds one from the project's ([InputActionFieldEditors]).
class InputActionListFieldRow extends StatelessWidget {
  /// The row for the field [ctx] edits.
  const InputActionListFieldRow({super.key, required this.ctx});

  /// The field, its value and how to write it.
  final FieldEditorContext ctx;

  @override
  Widget build(BuildContext context) {
    final c = ctx;
    final names = [...(c.value as List? ?? const []).whereType<String>()];
    if (c.readOnly) {
      return ReadonlyFieldRow(label: c.label, value: names.join(', '));
    }
    final actions = c.scope?.inputActions;
    Widget row(BuildContext context) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 4), child: _label(c)),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (i, name) in names.indexed)
                InputActionChip(
                  name: name,
                  isKnown: actions == null || actions.knows(name),
                  onRemove: () => c.onChanged([
                    for (final (j, n) in names.indexed)
                      if (j != i) n,
                  ]),
                ),
              EditorDropdown<String>(
                value: '',
                hint: names.isEmpty ? 'Add an action' : 'Add',
                isExpanded: false,
                height: 22,
                searchable: true,
                options: actions == null
                    ? const []
                    : _options(actions, '', exclude: names.toSet()),
                customValue: (typed) => typed.trim(),
                onChanged: (name) {
                  if (name.isNotEmpty && !names.contains(name)) {
                    c.onChanged([...names, name]);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
    if (actions == null) return Builder(builder: row);
    return ValueListenableBuilder<int>(
      valueListenable: actions.index.revision,
      builder: (context, _, _) => row(context),
    );
  }
}

/// One input action in a list: its name, marked when no asset has it, and
/// a way to take it off.
class InputActionChip extends StatelessWidget {
  /// A chip for [name]; [onRemove] takes it off.
  const InputActionChip({
    super.key,
    required this.name,
    required this.onRemove,
    this.isKnown = true,
  });

  /// The action's name, as saved.
  final String name;

  /// Takes it off the list.
  final VoidCallback onRemove;

  /// Whether an input asset has an action by this name; drawn in the
  /// warning colour when not.
  final bool isKnown;

  @override
  Widget build(BuildContext context) {
    final color = isKnown ? EditorTheme.textPrimary : EditorTheme.warning;
    return Tooltip(
      message: isKnown
          ? name
          : '"$name" is not an action in the project\'s input assets',
      child: Container(
        height: 22,
        padding: const EdgeInsets.only(left: 8, right: 2),
        decoration: BoxDecoration(
          color: EditorTheme.inputBg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isKnown ? EditorTheme.border : EditorTheme.warning,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: TextStyle(color: color, fontSize: 11)),
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
}
