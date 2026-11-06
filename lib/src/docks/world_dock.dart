import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import 'dock_widgets.dart';

enum _WorldTab { entities, systems, components }

/// The world as tables: every entity, every system, every component type —
/// searchable, sortable, and a click away from the scene.
class WorldDock extends StatefulWidget {
  const WorldDock({
    super.key,
    required this.scope,
    required this.dock,
    this.debugger,
  });

  final EditorScope scope;
  final DockContext dock;

  /// For per-system timings; without it the Systems tab has no times.
  final JustDebuggerController? debugger;

  @override
  State<WorldDock> createState() => WorldDockState();
}

/// The state of a [WorldDock]; public for tests.
class WorldDockState extends State<WorldDock> {
  late _WorldTab _tab =
      _WorldTab.values.asNameMap()[widget.dock.memory?.read<String>('tab')] ??
      _WorldTab.entities;
  String _query = '';

  /// Twice a second while the world changes without telling anyone — a
  /// play-test runs the game — or the Systems tab shows their times.
  Timer? _poll;

  /// A rebuild waiting out [_settle] after a change to the scene: a drag
  /// changes it on every move.
  Timer? _soon;
  final List<VoidCallback> _stops = [];

  static const Duration _pollEvery = Duration(milliseconds: 500);
  static const Duration _settle = Duration(milliseconds: 100);

  /// How many times the dock has been built; for tests.
  @visibleForTesting
  int builds = 0;

  /// Each entity's searchable text — name, tags, component types — by id,
  /// lower-cased, for the scene revision it was made at: a filter typed or
  /// a rebuild with nothing changed walks no component.
  Map<int, String> _searchText = {};
  int? _searchedAt;

  jge.World get _world => widget.scope.world;

  @override
  void initState() {
    super.initState();
    final scope = widget.scope;
    _stops
      ..add(scope.sceneState.selectedEntity.watch(_rebuild))
      ..add(scope.sceneState.revision.watch(_changed))
      ..add(scope.isPlayTesting.watch(_followPlay));
    _followPlay();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _soon?.cancel();
    for (final stop in _stops) {
      stop();
    }
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // The scene changed: built again once it has been still a moment.
  void _changed() => _soon ??= Timer(_settle, () {
    _soon = null;
    _rebuild();
  });

  // Polled only while the world changes on its own or times are shown.
  void _followPlay() {
    final poll = widget.scope.isPlayTesting.value || _tab == _WorldTab.systems;
    if (poll == (_poll != null)) return;
    _poll?.cancel();
    _poll = poll ? Timer.periodic(_pollEvery, (_) => _rebuild()) : null;
  }

  bool _matches(String text) =>
      _query.trim().isEmpty ||
      text.toLowerCase().contains(_query.trim().toLowerCase());

  // [e]'s text for the filter, made once per scene revision (each poll
  // during a play-test, when the world moves without one).
  String _searchTextOf(jge.Entity e) {
    final at = widget.scope.isPlayTesting.value
        ? null
        : widget.scope.sceneState.revision.value;
    if (at == null || at != _searchedAt) {
      _searchedAt = at;
      _searchText = {};
    }
    return _searchText[e.id] ??= [
      _nameOf(e),
      e.tags.join(', '),
      for (final c in e.components) '${c.runtimeType}',
    ].join('\u0000').toLowerCase();
  }

  static String _nameOf(jge.Entity e) => e.name ?? 'Entity ${e.id}';

  void _select(List<jge.Entity> entities) {
    if (entities.isEmpty) return;
    final state = widget.scope.sceneState;
    entities.length == 1
        ? state.selectEntity(entities.single)
        : state.selectRange(entities, anchor: entities.first);
  }

  @override
  Widget build(BuildContext context) {
    builds++;
    final entities = _world.entities.toList();
    final systems = _world.systems.toList();
    final active = entities.where((e) => e.isActive).length;
    return Column(
      children: [
        EditorToolbar(
          children: [
            for (final (tab, label, count) in [
              (_WorldTab.entities, 'Entities', entities.length),
              (_WorldTab.systems, 'Systems', systems.length),
              (_WorldTab.components, 'Components', null),
            ])
              EditorChip(
                label: label,
                count: count,
                selected: _tab == tab,
                onTap: () {
                  setState(() => _tab = tab);
                  widget.dock.memory?.write('tab', tab.name);
                  _followPlay();
                },
              ),
            const SizedBox(width: 8),
            EditorSearchField(
              hint: 'Filter',
              width: 180,
              onChanged: (v) => setState(() => _query = v),
            ),
            const Spacer(),
            Text(
              '$active active of ${entities.length}',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
            ),
          ],
        ),
        Expanded(
          child: switch (_tab) {
            _WorldTab.entities => _entitiesTable(entities),
            _WorldTab.systems => _systemsTable(systems),
            _WorldTab.components => _componentsTable(entities),
          },
        ),
      ],
    );
  }

  Widget _entitiesTable(List<jge.Entity> entities) {
    String tagOf(jge.Entity e) => e.tags.join(', ');
    String layerOf(jge.Entity e) {
      final layer = e.getComponent<jge.LayerComponent>()?.layer;
      return layer == null ? '' : '$layer';
    }

    final query = _query.trim().toLowerCase();
    final rows = query.isEmpty
        ? entities
        : [
            for (final e in entities)
              if (_searchTextOf(e).contains(query)) e,
          ];
    final selected = widget.scope.sceneState.selectedEntity.value;
    return DockTable<jge.Entity>(
      rows: rows,
      isSelected: (e) => identical(e, selected),
      onTap: (e) => _select([e]),
      empty: const EditorEmptyState(
        icon: Icons.hub_outlined,
        title: 'No entities match',
      ),
      columns: [
        DockColumn(label: 'Name', flex: 3, text: _nameOf),
        DockColumn(
          label: 'Id',
          width: 56,
          numeric: true,
          text: (e) => '${e.id}',
          sortKey: (e) => e.id,
        ),
        DockColumn(label: 'Tag', flex: 2, text: tagOf),
        DockColumn(
          label: 'Layer',
          width: 56,
          numeric: true,
          text: layerOf,
          sortKey: (e) => e.getComponent<jge.LayerComponent>()?.layer ?? -1,
        ),
        DockColumn(
          label: 'Components',
          flex: 5,
          text: (e) => [
            for (final c in e.components)
              '${c.runtimeType}'.replaceAll('Component', ''),
          ].join(', '),
          sortKey: (e) => e.components.length,
        ),
        DockColumn(
          label: 'Active',
          width: 56,
          text: (e) => e.isActive ? 'yes' : 'no',
          color: (e) => e.isActive ? null : EditorTheme.textMuted,
        ),
      ],
    );
  }

  Widget _systemsTable(List<jge.System> systems) {
    final times =
        widget.debugger?.performance.systemTimesMs ?? const <String, double>{};
    final rows = [
      for (final s in systems)
        if (_matches('${s.runtimeType}')) s,
    ];
    return DockTable<jge.System>(
      rows: rows,
      empty: const EditorEmptyState(
        icon: Icons.settings_suggest_outlined,
        title: 'No systems match',
      ),
      columns: [
        // Only the dot switches a system off or back on — until the editor
        // closes; it is a debugging aid, not something a scene saves. A
        // stray click on the row stops nothing.
        DockColumn(
          label: 'On',
          width: 40,
          text: (s) => s.isActive ? '●' : '○',
          color: (s) =>
              s.isActive ? EditorTheme.success : EditorTheme.textMuted,
          sortKey: (s) => s.isActive ? 0 : 1,
          onTap: (s) => setState(() => s.isActive = !s.isActive),
          tooltip: (s) => s.isActive
              ? 'Switch off until the editor closes'
              : 'Switch back on',
        ),
        DockColumn(
          label: 'System',
          flex: 4,
          text: (s) => '${s.runtimeType}',
          color: (s) => s.isActive ? null : EditorTheme.textMuted,
        ),
        DockColumn(
          label: 'Priority',
          width: 70,
          numeric: true,
          text: (s) => '${s.priority}',
          sortKey: (s) => -s.priority,
        ),
        DockColumn(
          label: 'Entities',
          width: 70,
          numeric: true,
          text: (s) => '${s.entities.length}',
          sortKey: (s) => s.entities.length,
        ),
        DockColumn(
          label: 'Last ms',
          width: 80,
          numeric: true,
          text: (s) {
            final ms = times['${s.runtimeType}'];
            return ms == null ? '—' : ms.toStringAsFixed(3);
          },
          sortKey: (s) => -(times['${s.runtimeType}'] ?? 0),
        ),
      ],
    );
  }

  Widget _componentsTable(List<jge.Entity> entities) {
    final carriers = <String, List<jge.Entity>>{};
    for (final e in entities) {
      for (final c in e.components) {
        (carriers['${c.runtimeType}'] ??= []).add(e);
      }
    }
    final rows = [
      for (final type in carriers.keys)
        if (_matches(type)) type,
    ];
    return DockTable<String>(
      rows: rows,
      // Everything that carries it, selected at once.
      onTap: (type) => _select(carriers[type]!),
      empty: const EditorEmptyState(
        icon: Icons.extension_outlined,
        title: 'No component types match',
      ),
      columns: [
        DockColumn(label: 'Component', flex: 4, text: (t) => t),
        DockColumn(
          label: 'Entities',
          width: 80,
          numeric: true,
          text: (t) => '${carriers[t]!.length}',
          sortKey: (t) => -carriers[t]!.length,
        ),
        DockColumn(
          label: 'On',
          flex: 5,
          text: (t) {
            final names = carriers[t]!.take(6).map(_nameOf).join(', ');
            return carriers[t]!.length > 6 ? '$names, …' : names;
          },
        ),
      ],
    );
  }
}
