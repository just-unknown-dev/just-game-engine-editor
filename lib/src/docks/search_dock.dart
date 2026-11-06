import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_editor_core/host.dart';
import 'dock_widgets.dart';

/// A query over the scene. Words match names, tags and component types; a
/// term like `Health.health < 3` or `transform.x >= 100` compares a field;
/// `#enemy` is only what carries that tag, exactly.
class SceneQuery {
  SceneQuery(String text) {
    final comparison = RegExp(
      r'(\w+)\.(\w+)\s*(<=|>=|==|!=|<|>|=)\s*("[^"]*"|\S+)',
    );
    var rest = text;
    for (final m in comparison.allMatches(text)) {
      _comparisons.add((
        component: m.group(1)!.toLowerCase(),
        field: m.group(2)!.toLowerCase(),
        op: m.group(3)! == '=' ? '==' : m.group(3)!,
        value: m.group(4)!.replaceAll('"', ''),
      ));
      rest = rest.replaceFirst(m.group(0)!, ' ');
    }
    for (final word in rest.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      if (word.startsWith('#') && word.length > 1) {
        _tags.add(word.substring(1));
      } else {
        _words.add(word.toLowerCase());
      }
    }
  }

  final List<String> _words = [];
  final List<String> _tags = [];
  final List<({String component, String field, String op, String value})>
  _comparisons = [];

  bool get isEmpty => _words.isEmpty && _tags.isEmpty && _comparisons.isEmpty;

  bool matches(jge.Entity entity, EditorScope scope) {
    if (!_tags.every(entity.hasTag)) return false;
    final haystack = [
      entity.name ?? '',
      ...entity.tags,
      for (final c in entity.components) '${c.runtimeType}',
    ].join(' ').toLowerCase();
    if (!_words.every(haystack.contains)) return false;
    return _comparisons.every((q) => _holds(q, entity, scope));
  }

  static bool _holds(
    ({String component, String field, String op, String value}) q,
    jge.Entity entity,
    EditorScope scope,
  ) {
    for (final component in entity.components) {
      final type = '${component.runtimeType}'.toLowerCase();
      if (type != q.component && type != '${q.component}component') continue;
      final definition = scope.definitions.definitionFor(component);
      if (definition == null) continue;
      for (final field in definition.fields) {
        final value = field.read(component);
        // `transform.x` reaches into a vector field's axis.
        final axis = switch (value) {
          final jge.Vector3 v => {'x': v.x, 'y': v.y, 'z': v.z}[q.field],
          final jge.Vector2 v => {'x': v.x, 'y': v.y}[q.field],
          _ => null,
        };
        if (axis != null) return _compare(axis, q.op, q.value);
        // `Tag.tag` still means the tag list it became.
        final name = field.name.toLowerCase();
        final plural = value is Iterable && name == '${q.field}s';
        if (name != q.field && !plural) continue;
        return _compare(value, q.op, q.value);
      }
    }
    return false;
  }

  static bool _compare(Object? actual, String op, String wanted) {
    final a = actual is num ? actual.toDouble() : null;
    final b = double.tryParse(wanted);
    if (a != null && b != null) {
      return switch (op) {
        '<' => a < b,
        '<=' => a <= b,
        '>' => a > b,
        '>=' => a >= b,
        '!=' => a != b,
        _ => a == b,
      };
    }
    // A list — an entity's tags — holds the value when any item is it.
    final same = actual is Iterable
        ? actual.any((x) => '$x'.toLowerCase() == wanted.toLowerCase())
        : '$actual'.toLowerCase() == wanted.toLowerCase();
    return op == '!=' ? !same : same;
  }
}

/// Finds entities across the scene, and selects what it finds.
class SearchDock extends StatefulWidget {
  const SearchDock({super.key, required this.scope, required this.dock});

  final EditorScope scope;
  final DockContext dock;

  @override
  State<SearchDock> createState() => _SearchDockState();
}

class _SearchDockState extends State<SearchDock> {
  late String _text = widget.dock.memory?.read<String>('query') ?? '';

  @override
  Widget build(BuildContext context) {
    final query = SceneQuery(_text);
    final found = query.isEmpty
        ? const <jge.Entity>[]
        : [
            for (final e in widget.scope.world.entities)
              if (query.matches(e, widget.scope)) e,
          ];
    final selected = widget.scope.sceneState.selectedEntity.value;
    return Column(
      children: [
        EditorToolbar(
          children: [
            EditorSearchField(
              initial: _text,
              width: 360,
              hint: 'name, tag, component — or Health.health < 3',
              onChanged: (v) {
                setState(() => _text = v);
                widget.dock.memory?.write('query', v);
              },
            ),
            const SizedBox(width: 10),
            Text(
              query.isEmpty ? '' : '${found.length} found',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
            ),
            const Spacer(),
            EditorIconButton(
              icon: Icons.select_all_rounded,
              tooltip: 'Select everything found',
              onTap: found.isEmpty
                  ? null
                  : () => found.length == 1
                        ? widget.scope.sceneState.selectEntity(found.single)
                        : widget.scope.sceneState.selectRange(
                            found,
                            anchor: found.first,
                          ),
            ),
          ],
        ),
        Expanded(
          child: query.isEmpty
              ? const EditorEmptyState(
                  icon: Icons.manage_search_rounded,
                  title: 'Search the scene',
                  hint:
                      'Words match names, tags and component types; '
                      '#enemy is exactly what carries that tag.\n'
                      'Compare a field: Health.health < 3 · '
                      'transform.x >= 100 · Tag.tags = enemy',
                )
              : DockTable<jge.Entity>(
                  rows: found,
                  isSelected: (e) => identical(e, selected),
                  onTap: (e) {
                    widget.scope.sceneState.selectEntity(e);
                    setState(() {});
                  },
                  empty: const EditorEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Nothing matches',
                  ),
                  columns: [
                    DockColumn(
                      label: 'Name',
                      flex: 3,
                      text: (e) => e.name ?? 'Entity ${e.id}',
                    ),
                    DockColumn(
                      label: 'Tags',
                      flex: 2,
                      text: (e) => e.tags.join(', '),
                    ),
                    DockColumn(
                      label: 'Components',
                      flex: 6,
                      text: (e) => [
                        for (final c in e.components)
                          '${c.runtimeType}'.replaceAll('Component', ''),
                      ].join(', '),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
