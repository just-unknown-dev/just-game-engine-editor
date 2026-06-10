import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' hide Animation;
import '../theme/editor_theme.dart';

import '../../core/registry/component_registry.dart';
import '../../core/state/editor_scene_state.dart';

/// An expandable in-place panel that lets the user search for and add a
/// component to the currently selected entity.
///
/// Place this at the bottom of the inspector.  It expands downward when the
/// user taps "+ Add Component".
class AddComponentPicker extends StatefulWidget {
  const AddComponentPicker({
    super.key,
    required this.entity,
    required this.sceneState,
  });

  final Entity entity;
  final EditorSceneState sceneState;

  @override
  State<AddComponentPicker> createState() => _AddComponentPickerState();
}

class _AddComponentPickerState extends State<AddComponentPicker>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  late final AnimationController _animCtrl;
  late final Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
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
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animCtrl.forward();
    } else {
      _animCtrl.reverse();
      _searchCtrl.clear();
    }
  }

  /// Returns the runtime types of components already attached to the entity so
  /// we can grey out duplicates.
  Set<String> get _existingTypes =>
      widget.entity.components.map((c) => c.runtimeType.toString()).toSet();

  List<ComponentEntry> get _filtered {
    if (_query.isEmpty) return kComponentRegistry;
    return kComponentRegistry
        .where(
          (e) =>
              e.name.toLowerCase().contains(_query) ||
              e.group.toLowerCase().contains(_query) ||
              e.description.toLowerCase().contains(_query),
        )
        .toList();
  }

  void _addComponent(ComponentEntry entry) {
    final component = entry.factory();
    widget.entity.addComponent(component);
    widget.sceneState.markDirty();
    widget.sceneState.refresh(); // rebuild inspector to show new component
    _toggle(); // collapse picker
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── Toggle button ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
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
                  const Expanded(
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
                    duration: const Duration(milliseconds: 160),
                    child: const Icon(
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

        // ── Expandable list ───────────────────────────────────────────────
        SizeTransition(
          sizeFactor: _heightFactor,
          axisAlignment: -1,
          child: _PickerList(
            searchCtrl: _searchCtrl,
            filtered: _filtered,
            existingTypes: _existingTypes,
            onAdd: _addComponent,
          ),
        ),
      ],
    );
  }
}

// ── Picker list (search field + grouped results) ──────────────────────────────

class _PickerList extends StatelessWidget {
  const _PickerList({
    required this.searchCtrl,
    required this.filtered,
    required this.existingTypes,
    required this.onAdd,
  });

  final TextEditingController searchCtrl;
  final List<ComponentEntry> filtered;
  final Set<String> existingTypes;
  final void Function(ComponentEntry) onAdd;

  @override
  Widget build(BuildContext context) {
    // Group filtered entries
    final Map<String, List<ComponentEntry>> grouped = {};
    for (final entry in filtered) {
      grouped.putIfAbsent(entry.group, () => []).add(entry);
    }
    // Sort groups in canonical order
    final orderedGroups = kComponentGroups
        .where((g) => grouped.containsKey(g))
        .toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceDarkest,
        border: Border.all(color: EditorTheme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: <Widget>[
          // Search field
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: searchCtrl,
              autofocus: true,
              style: const TextStyle(
                color: EditorTheme.textPrimary,
                fontSize: 12,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search components…',
                hintStyle: const TextStyle(
                  color: EditorTheme.primaryMuted,
                  fontSize: 12,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: EditorTheme.primaryMuted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                filled: true,
                fillColor: EditorTheme.inputBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: EditorTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: EditorTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(
                    color: EditorTheme.primaryActive,
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: EditorTheme.surfaceBg),
          // Results
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: filtered.isEmpty
                ? const Padding(
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

  // We render group headers + component rows in a flat list — compute the
  // total item count for the builder.
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
        final alreadyAdded = existingTypes.contains(typeKey);
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
        style: const TextStyle(
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
                          ? EditorTheme.hoverBgAlt
                          : EditorTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    entry.description,
                    style: TextStyle(
                      color: alreadyAdded
                          ? EditorTheme.hoverBg
                          : EditorTheme.primaryMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (alreadyAdded)
              const Text(
                'added',
                style: TextStyle(
                  color: EditorTheme.hoverBgAlt,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              const Icon(
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
