import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' hide Animation;

import '../../core/constants/editor_constants.dart';
import '../../core/theme/editor_metrics.dart';
import '../../core/scope/editor_scope.dart';
import '../../core/ecs/registry/component_registry.dart';
import '../../core/state/editor_scene_state.dart';
import '../level_designer/state/editor_history.dart';
import '../level_designer/state/editor_commands.dart';
import '../kit/kit.dart';

/// An expandable in-place panel that lets the user search for and add a
/// component to the currently selected entity.
///
/// Place this at the bottom of the inspector. It expands downward when the
/// user taps "+ Add Component".
class AddComponentPicker extends StatefulWidget {
  const AddComponentPicker({
    super.key,
    required this.entity,
    required this.sceneState,
    required this.scope,
    this.history,
  });

  final Entity entity;

  /// What can be added: the scope's definitions.
  final EditorScope scope;
  final EditorSceneState sceneState;

  /// Where adding is recorded; the scene's history unless given.
  final EditorHistory? history;

  @override
  State<AddComponentPicker> createState() => _AddComponentPickerState();
}

class _AddComponentPickerState extends State<AddComponentPicker>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  late final AnimationController _animCtrl;
  late final Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: EditorMetrics.motionFast,
    );
    _heightFactor = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toggle() {
    // As the motion settings are now, not as they were when it was built.
    _animCtrl.duration = EditorMetrics.motionFast;
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animCtrl.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    } else {
      _animCtrl.reverse();
      _searchCtrl.clear();
    }
  }

  Set<String> get _existingTypes =>
      widget.entity.components.map((c) => c.runtimeType.toString()).toSet();

  List<ComponentEntry> get _filtered {
    final allEntries = getComponentRegistryEntries(widget.scope);
    if (_query.isEmpty) return allEntries;
    return allEntries
        .where(
          (e) =>
              e.name.toLowerCase().contains(_query) ||
              e.group.toLowerCase().contains(_query) ||
              e.description.toLowerCase().contains(_query),
        )
        .toList();
  }

  void _addComponent(ComponentEntry entry) {
    // Through the history, so an added component can be undone.
    (widget.history ?? widget.scope.history).push(
      AddComponentCommand(
        entity: widget.entity,
        component: entry.factory(),
        sceneState: widget.sceneState,
      ),
    );
    _toggle();
  }

  bool _addable(ComponentEntry entry) =>
      entry.allowMultiple ||
      !_existingTypes.contains(entry.componentTypeName ?? entry.name);

  /// Enter in the search: the first match that can be added.
  void _addFirst() {
    for (final entry in _filtered) {
      if (_addable(entry)) return _addComponent(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── Add Component button ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(6),
            child: AnimatedContainer(
              duration: EditorMetrics.motionFast,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _expanded
                    ? EditorTheme.selectionBg
                    : EditorTheme.surfaceDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _expanded
                      ? EditorTheme.primaryActive
                      : EditorTheme.border,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    _expanded ? Icons.remove_rounded : Icons.add_rounded,
                    size: 16,
                    color: EditorTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add Component',
                      style: TextStyle(
                        color: EditorTheme.primaryBright,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: EditorMetrics.motionFast,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: EditorTheme.primaryMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Expandable list ────────────────────────────────────────────────
        SizeTransition(
          sizeFactor: _heightFactor,
          child: _PickerList(
            searchCtrl: _searchCtrl,
            searchFocus: _searchFocus,
            filtered: _filtered,
            existingTypes: _existingTypes,
            onAdd: _addComponent,
            onSubmit: _addFirst,
            onEscape: _toggle,
          ),
        ),
      ],
    );
  }
}

// ── Picker list ───────────────────────────────────────────────────────────────

class _PickerList extends StatelessWidget {
  const _PickerList({
    required this.searchCtrl,
    required this.searchFocus,
    required this.filtered,
    required this.existingTypes,
    required this.onAdd,
    required this.onSubmit,
    required this.onEscape,
  });

  final TextEditingController searchCtrl;
  final FocusNode searchFocus;
  final List<ComponentEntry> filtered;
  final Set<String> existingTypes;
  final void Function(ComponentEntry) onAdd;

  /// Enter: add the first match.
  final VoidCallback onSubmit;

  /// Esc: fold the picker away.
  final VoidCallback onEscape;

  @override
  Widget build(BuildContext context) {
    final Map<String, List<ComponentEntry>> grouped = {};
    for (final entry in filtered) {
      grouped.putIfAbsent(entry.group, () => []).add(entry);
    }
    // kComponentGroups orders the sections it names; anything else follows,
    // alphabetically. Treating it as a whitelist — which it used to be — made
    // a project's own component group invisible here, search included.
    final known = kComponentGroups.where(grouped.containsKey);
    final extra =
        grouped.keys.where((g) => !kComponentGroups.contains(g)).toList()
          ..sort();
    final orderedGroups = [...known, ...extra];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceDarkest,
        border: Border.all(color: EditorTheme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): onEscape,
              },
              child: TextField(
                controller: searchCtrl,
                focusNode: searchFocus,
                cursorColor: EditorTheme.primaryBright,
                style: TextStyle(color: EditorTheme.textPrimary, fontSize: 12),
                // Enter adds the first match, Esc folds the list away.
                onSubmitted: (_) => onSubmit(),
                decoration: editorFieldDecoration(
                  hint: 'Search components — Enter adds the first',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 15,
                    color: EditorTheme.textMuted,
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: EditorTheme.surfaceBg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: filtered.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No components match your search.',
                      style: TextStyle(
                        color: EditorTheme.primaryMuted,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 4),
                    itemCount: _countItems(orderedGroups, grouped),
                    itemBuilder: (context, index) =>
                        _buildItem(index, orderedGroups, grouped),
                  ),
          ),
        ],
      ),
    );
  }

  int _countItems(
    List<String> groups,
    Map<String, List<ComponentEntry>> grouped,
  ) {
    return groups.fold(0, (sum, g) => sum + 1 + (grouped[g]?.length ?? 0));
  }

  Widget _buildItem(
    int index,
    List<String> groups,
    Map<String, List<ComponentEntry>> grouped,
  ) {
    int cursor = 0;
    for (final group in groups) {
      if (index == cursor) return _GroupHeader(label: group);
      cursor++;
      final entries = grouped[group]!;
      final localIndex = index - cursor;
      if (localIndex < entries.length) {
        final entry = entries[localIndex];
        final typeKey = entry.componentTypeName ?? entry.name;
        // A type that allows several copies is never "already added".
        final alreadyAdded =
            !entry.allowMultiple && existingTypes.contains(typeKey);
        return _ComponentRow(
          entry: entry,
          alreadyAdded: alreadyAdded,
          onTap: alreadyAdded ? null : () => onAdd(entry),
        );
      }
      cursor += entries.length;
    }
    return const SizedBox.shrink();
  }
}

// ── Group header ──────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: EditorTheme.primaryBright,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ── Component row ─────────────────────────────────────────────────────────────

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.entry,
    required this.alreadyAdded,
    required this.onTap,
  });

  final ComponentEntry entry;
  final bool alreadyAdded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.name,
                    style: TextStyle(
                      color: alreadyAdded
                          ? EditorTheme.textMuted.withValues(alpha: 0.6)
                          : EditorTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    entry.description,
                    style: TextStyle(
                      color: alreadyAdded
                          ? EditorTheme.textMuted.withValues(alpha: 0.45)
                          : EditorTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (alreadyAdded)
              Text(
                'added',
                style: TextStyle(
                  color: EditorTheme.textMuted,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Icon(
                Icons.add_rounded,
                size: 14,
                color: EditorTheme.primaryMuted,
              ),
          ],
        ),
      ),
    );
  }
}
