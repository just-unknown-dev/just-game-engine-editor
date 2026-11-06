part of 'scene_tree_panel.dart';

/// The scene tree's filter: its bar and chips.
extension _SceneTreeFilter on _SceneTreePanelState {
  // ── The filter bar ───────────────────────────────────────────────────

  /// What is in the scene to filter by, gathered from the scene itself:
  /// the component types it actually uses, the tags and layers it
  /// actually has. A list of everything the editor *could* show would be
  /// longer and less use.
  Set<String> _componentTypes() => {
    for (final entity in _world.entities)
      if (entity.isAlive)
        for (final component in entity.components)
          component.runtimeType.toString(),
  };

  Set<String> _tags() => _world.tagsInUse;

  Set<String> _layers() => {
    for (final entity in _world.entities)
      if (entity.isAlive)
        if (entity.getComponent<jge.LayerComponent>()?.layerId case final id?)
          if (id.isNotEmpty) id,
  };

  Widget _filterChips(TreeFilter filter) {
    // Only what this scene can answer: a Tag chip over a scene with no
    // tags opens an empty menu and takes a row up saying nothing.
    final types = _componentTypes();
    final tags = _tags();
    final layers = _layers();
    final scene = _sceneState.activeScene.value;
    if (!identical(scene, _problemsScene)) {
      _problemsScene = scene;
      _problemCount = null;
    }
    final problemCount = _problemCount ??= ProblemScan.of(
      widget.scope,
    ).problems.length;
    final chips = <Widget>[
      _FilterChip(
        label: filter.componentType.isEmpty
            ? 'Component'
            : filter.componentType,
        on: filter.componentType.isNotEmpty,
        count: filter.componentType.isEmpty ? types.length : null,
        onPressed: (at) => _pickFilter(
          at,
          types,
          'Any component',
          (value) => _tree.filter.value = filter.copyWith(componentType: value),
        ),
      ),
      if (tags.isNotEmpty || filter.wantedTags.isNotEmpty)
        _FilterChip(
          label: switch (filter.wantedTags.toList()) {
            [] => 'Tag',
            [final only] => '#$only',
            [final first, ...final rest] => '#$first +${rest.length}',
          },
          on: filter.wantedTags.isNotEmpty,
          count: filter.wantedTags.isEmpty ? tags.length : null,
          onPressed: (at) => _pickTags(at, tags, filter),
        ),
      if (layers.isNotEmpty || filter.layer.isNotEmpty)
        _FilterChip(
          label: filter.layer.isEmpty ? 'Layer' : filter.layer,
          on: filter.layer.isNotEmpty,
          count: filter.layer.isEmpty ? layers.length : null,
          onPressed: (at) => _pickFilter(
            at,
            layers,
            'Any layer',
            (value) => _tree.filter.value = filter.copyWith(layer: value),
          ),
        ),
      if (problemCount > 0 || filter.problems)
        _FilterChip(
          label: 'Problems',
          on: filter.problems,
          count: problemCount,
          isMenu: false,
          onPressed: (_) =>
              _tree.filter.value = filter.copyWith(problems: !filter.problems),
        ),
      if (!filter.isEmpty)
        _FilterChip(
          label: 'Clear',
          on: false,
          isMenu: false,
          onPressed: (_) {
            _search.clear();
            _tree.filter.value = TreeFilter.none;
          },
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      child: Wrap(spacing: 4, runSpacing: 4, children: chips),
    );
  }

  /// One of [options], or [anyLabel] for no filter at all.
  Future<void> _pickFilter(
    Offset at,
    Set<String> options,
    String anyLabel,
    void Function(String value) apply,
  ) async {
    final sorted = options.toList()..sort();
    final chosen = await showEditorMenu<String>(context, at, [
      editorMenuItem('', anyLabel),
      if (sorted.isNotEmpty) editorMenuDivider(),
      for (final option in sorted) editorMenuItem(option, option),
    ]);
    if (chosen == null) return;
    apply(chosen);
  }

  /// Tags to narrow the tree to — any of several, each ticked on or off.
  Future<void> _pickTags(
    Offset at,
    Set<String> inScene,
    TreeFilter filter,
  ) async {
    final wanted = filter.wantedTags;
    final sorted = {...inScene, ...wanted}.toList()..sort();
    final tags = widget.scope.tags;
    final chosen = await showEditorMenu<String>(context, at, [
      editorMenuItem('', 'Any tag', iconSlot: true),
      if (sorted.isNotEmpty) editorMenuDivider(),
      for (final tag in sorted)
        editorMenuItem(
          tag,
          tag,
          icon: wanted.contains(tag) ? Icons.check_rounded : Icons.circle,
          iconColor: wanted.contains(tag) ? null : tags.colorOf(tag),
        ),
    ]);
    if (chosen == null) return;
    _tree.filter.value = filter.copyWith(
      tag: '',
      tags: chosen.isEmpty
          ? const {}
          : wanted.contains(chosen)
          ? (wanted..remove(chosen))
          : {...wanted, chosen},
    );
  }
}
