import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import '../../../../core/scope/editor_scope_services.dart';
import '../../../../core/validation/built_in_validators.dart';
import '../shared/dock_widgets.dart';

// ── Problems ─────────────────────────────────────────────────────────────────

/// What is wrong with the open scene, kept current: asked a few times a
/// second by the strip and the tab, recomputed only when the scene or the
/// project's files have changed since — or, for a file changed where the
/// editor does not watch, after [_maxAge] — and never during a play-test,
/// whose world is the game's, not the scene: what was found before it
/// stays until it ends.
class ProblemScan {
  ProblemScan(this.scope);

  static final Expando<ProblemScan> _byScope = Expando('problemScan');

  /// The scan for [scope] — the same one wherever it is asked for, so a
  /// scene is not checked once per thing that wants the answer.
  static ProblemScan of(EditorScope scope) =>
      _byScope[scope] ??= ProblemScan(scope);

  final EditorScope scope;
  List<SceneProblem> _problems = const [];
  DateTime? _at;
  (EditorScene?, int, int?)? _seen;

  static const Duration _maxAge = Duration(seconds: 10);

  /// How often a scene being edited is checked again while the edits keep
  /// coming — a drag changes it on every move, and every check there is
  /// runs per scan. Another scene, or a change on disk, is checked at once.
  /// What shows the problems reads them again after it: the Problems dock
  /// and the status strip on their own beat, the scene tree once the scene
  /// has been still a little longer than this.
  static const Duration editEvery = Duration(seconds: 1);

  /// What time it is: the clock, a test's own.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// What a scan was of: the scene, its edits, the files on disk — as the
  /// asset index has seen them, once something has made one (asking for it
  /// here would scan the whole project).
  (EditorScene?, int, int?) _now() => (
    scope.sceneState.activeScene.value,
    scope.sceneState.revision.value,
    scope.container.isRegistered<AssetIndex>()
        ? scope.assetIndex.revision.value
        : null,
  );

  List<SceneProblem> get problems {
    if (_isStale()) {
      final at = _at;
      final seen = _seen;
      final current = _now();
      final age = at == null ? null : now().difference(at);
      final onlyEdited =
          seen != null && seen.$1 == current.$1 && seen.$3 == current.$3;
      if (age == null || !onlyEdited || age >= editEvery) refresh();
    }
    return _problems;
  }

  bool _isStale() {
    if (scope.isPlayTesting.value) return false;
    final at = _at;
    return at == null || _now() != _seen || now().difference(at) > _maxAge;
  }

  /// Checks the scene now.
  void refresh() {
    _at = now();
    _seen = _now();
    _problems = scope.sceneState.hasScene
        ? BuiltInValidators.run(ScanValidationContext(scope: scope), [
            ...BuiltInValidators.all,
            ...scope.validators,
          ])
        : const [];
  }

  int get errors =>
      problems.where((p) => p.severity == ProblemSeverity.error).length;
}

/// A [ValidationContext] that reads each file once per scan: sixty enemies
/// sharing one animator graph and atlas are two reads and two decodes, not
/// a hundred and twenty.
class ScanValidationContext extends ValidationContext {
  ScanValidationContext({
    required super.scope,
    super.projectRoot,
    super.fileExists,
    super.readText,
  });

  final Map<String, bool> _exists = {};
  final Map<String, String?> _texts = {};
  final Map<String, Map<String, dynamic>?> _json = {};

  @override
  bool fileExists(String path) => _exists[path] ??= super.fileExists(path);

  @override
  String? readText(String path) => _texts.containsKey(path)
      ? _texts[path]
      : _texts[path] = super.readText(path);

  @override
  Map<String, dynamic>? readJson(String path) => _json.containsKey(path)
      ? _json[path]
      : _json[path] = super.readJson(path);
}

/// The Problems dock: each thing wrong with the scene, and who it is about.
class ProblemsDock extends StatefulWidget {
  const ProblemsDock({super.key, required this.scope, required this.scan});

  final EditorScope scope;
  final ProblemScan scan;

  @override
  State<ProblemsDock> createState() => _ProblemsDockState();
}

class _ProblemsDockState extends State<ProblemsDock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final problems = widget.scan.problems;
    if (!widget.scope.sceneState.hasScene) {
      return const EditorEmptyState(
        icon: Icons.rule_rounded,
        title: 'No scene open',
        hint: 'Problems are checked for the scene being edited.',
      );
    }
    if (problems.isEmpty) {
      return const EditorEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing wrong that the editor can see',
        hint:
            'Missing files, broken references, animator clips that do not '
            'exist and cameras with nothing to follow show up here.',
      );
    }
    return ListView.builder(
      itemCount: problems.length,
      itemBuilder: (context, i) {
        final p = problems[i];
        final color = p.severity == ProblemSeverity.error
            ? EditorTheme.error
            : EditorTheme.warning;
        return InkWell(
          onTap: p.entity == null
              ? null
              : () => widget.scope.sceneState.selectEntity(p.entity!),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(width: 2, color: color)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  p.severity == ProblemSeverity.error
                      ? Icons.error_outline_rounded
                      : Icons.warning_amber_rounded,
                  size: 13,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.message,
                        style: TextStyle(
                          color: EditorTheme.textPrimary,
                          fontSize: 11,
                        ),
                      ),
                      if (p.hint != null)
                        Text(
                          p.hint!,
                          style: TextStyle(
                            color: EditorTheme.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      if (p.fixes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 3,
                            children: [
                              for (final fix in p.fixes)
                                _FixButton(
                                  label: fix.label,
                                  onTap: () {
                                    fix.apply();
                                    widget.scan.refresh();
                                    setState(() {});
                                  },
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (p.entity != null)
                  Icon(
                    Icons.my_location_rounded,
                    size: 12,
                    color: EditorTheme.primaryBright,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One way to fix a problem, as a small button under it.
class _FixButton extends StatelessWidget {
  const _FixButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: EditorTheme.primary.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(3),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_fix_high_rounded,
              size: 11,
              color: EditorTheme.primaryBright,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: EditorTheme.primaryBright,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── History ──────────────────────────────────────────────────────────────────

/// The undo stack as a list: what was done, in order, and a click to go back
/// to any point of it.
class HistoryDock extends StatelessWidget {
  const HistoryDock({super.key, required this.history});

  /// The editor's undo stack. Null only if a module swaps in none.
  final ValueListenable<EditorHistory?> history;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<EditorHistory?>(
    valueListenable: history,
    builder: (context, h, _) {
      if (h == null) {
        return const EditorEmptyState(
          icon: Icons.history_rounded,
          title: 'No history',
          hint: 'Nothing is keeping an undo history for this editor.',
        );
      }
      return ValueListenableBuilder<int>(
        valueListenable: h.revision,
        builder: (context, _, _) {
          final done = h.undoEntries;
          final undone = h.redoEntries.reversed.toList();
          if (done.isEmpty && undone.isEmpty) {
            return const EditorEmptyState(
              icon: Icons.history_rounded,
              title: 'Nothing done yet',
              hint: 'Every edit is a step here: click one to go back to it.',
            );
          }
          return ListView(
            children: [
              _HistoryRow(
                label: 'Scene as opened',
                isCurrent: done.isEmpty,
                isUndone: false,
                onTap: () => h.jumpTo(0),
              ),
              for (var i = 0; i < done.length; i++)
                _HistoryRow(
                  label: done[i].label,
                  isCurrent: i == done.length - 1,
                  isUndone: false,
                  onTap: () => h.jumpTo(i + 1),
                ),
              for (var i = 0; i < undone.length; i++)
                _HistoryRow(
                  label: undone[i].label,
                  isCurrent: false,
                  isUndone: true,
                  onTap: () => h.jumpTo(done.length + i + 1),
                ),
            ],
          );
        },
      );
    },
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.label,
    required this.isCurrent,
    required this.isUndone,
    required this.onTap,
  });

  final String label;
  final bool isCurrent;
  final bool isUndone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: 22,
      color: isCurrent ? EditorTheme.selectionBg : null,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(
            isCurrent
                ? Icons.arrow_right_rounded
                : isUndone
                ? Icons.redo_rounded
                : Icons.check_rounded,
            size: 13,
            color: isCurrent
                ? EditorTheme.primaryBright
                : EditorTheme.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isUndone
                    ? EditorTheme.textMuted
                    : EditorTheme.textPrimary,
                fontStyle: isUndone ? FontStyle.italic : null,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Animator ─────────────────────────────────────────────────────────────────

/// The selected entity's animator while the game runs: the state it is in,
/// its parameters as they change, and the transitions it has taken.
class AnimatorMonitorDock extends StatefulWidget {
  const AnimatorMonitorDock({super.key, required this.scope});

  final EditorScope scope;

  @override
  State<AnimatorMonitorDock> createState() => _AnimatorMonitorDockState();
}

class _AnimatorMonitorDockState extends State<AnimatorMonitorDock> {
  Timer? _tick;
  StreamSubscription<jge.AnimatorStateChange>? _changes;
  jge.AnimatorSystem? _listeningTo;
  final List<String> _trail = [];

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      _listen();
      setState(() {});
    });
    _listen();
  }

  jge.AnimatorSystem? get _system {
    for (final s in widget.scope.world.systems) {
      if (s is jge.AnimatorSystem) return s;
    }
    return null;
  }

  /// The animator system may be replaced (a scene reload): follow it.
  void _listen() {
    final system = _system;
    if (identical(system, _listeningTo)) return;
    _changes?.cancel();
    _listeningTo = system;
    _changes = system?.stateChanges.listen((c) {
      if (!identical(c.entity, widget.scope.sceneState.selectedEntity.value)) {
        return;
      }
      _trail.insert(0, '${c.from.isEmpty ? 'entry' : c.from} → ${c.to}');
      if (_trail.length > 12) _trail.removeLast();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entity = widget.scope.sceneState.selectedEntity.value;
    final animator = entity?.getComponent<jge.AnimatorComponent>();
    if (entity == null || animator == null) {
      return const EditorEmptyState(
        icon: Icons.account_tree_outlined,
        title: 'Select an entity with an Animator',
        hint: 'Its state and parameters show here, live, while the game plays.',
      );
    }
    final graph = _system?.graphOf(entity);
    final sprite = entity.getComponent<jge.SpriteAnimationComponent>();
    // The clip its state plays, from the graph: the sprite's own clip field
    // is what was authored, not what the animator chose.
    final clip =
        graph?.stateNamed(animator.currentState)?.clipName ?? sprite?.clip;
    final bound = {
      for (final p in graph?.parameters ?? const <jge.AnimatorParameter>[])
        if (p.binding != null) p.name: p.binding!,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EditorToolbar(
                children: [
                  Text(
                    animator.currentState.isEmpty
                        ? 'not running'
                        : animator.currentState,
                    style: TextStyle(
                      color: EditorTheme.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    [
                      if (animator.previousState.isNotEmpty)
                        'from ${animator.previousState}',
                      '${animator.stateTime.toStringAsFixed(2)} s',
                      if (sprite != null)
                        'clip $clip · frame ${sprite.frameIndex + 1}',
                    ].join('  ·  '),
                    style: TextStyle(
                      color: EditorTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                  const Spacer(),
                  if (animator.graphPath.isNotEmpty)
                    EditorIconButton(
                      icon: Icons.open_in_new_rounded,
                      tooltip: 'Open the graph',
                      onTap: () =>
                          widget.scope.openInWorkspace(animator.graphPath),
                    ),
                ],
              ),
              Expanded(
                child: DockTable<MapEntry<String, Object>>(
                  rows: animator.parameters.entries.toList(),
                  empty: const EditorEmptyState(
                    icon: Icons.tune_rounded,
                    title: 'No parameters yet',
                    hint: 'They appear once the graph has loaded.',
                  ),
                  columns: [
                    DockColumn(label: 'Parameter', flex: 3, text: (e) => e.key),
                    DockColumn(
                      label: 'Value',
                      flex: 2,
                      numeric: true,
                      text: (e) => e.value is double
                          ? (e.value as double).toStringAsFixed(2)
                          : '${e.value}',
                      color: (e) =>
                          e.value == true ? EditorTheme.success : null,
                    ),
                    DockColumn(
                      label: 'From',
                      flex: 3,
                      text: (e) => bound[e.key] == null
                          ? 'the game'
                          : '⇠ ${bound[e.key]}',
                      color: (_) => EditorTheme.textMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: EditorTheme.border),
        Expanded(
          flex: 2,
          child: _trail.isEmpty
              ? const EditorEmptyState(
                  icon: Icons.swap_horiz_rounded,
                  title: 'No transitions yet',
                  hint: 'Press Play: each change of state is listed here.',
                )
              : ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (var i = 0; i < _trail.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          _trail[i],
                          style: TextStyle(
                            fontSize: 11,
                            color: i == 0
                                ? EditorTheme.textPrimary
                                : EditorTheme.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ── Search ───────────────────────────────────────────────────────────────────

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
class SceneSearchDock extends StatefulWidget {
  const SceneSearchDock({super.key, required this.scope, required this.dock});

  final EditorScope scope;
  final DockContext dock;

  @override
  State<SceneSearchDock> createState() => _SceneSearchDockState();
}

class _SceneSearchDockState extends State<SceneSearchDock> {
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
