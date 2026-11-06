part of 'material_2d_workspace.dart';

/// The 2-D material window's fields and effect cards.
extension Material2DWorkspaceFields on Material2DWorkspaceState {
  // ── Fields ────────────────────────────────────────────────────────────

  TextStyle get _label => TextStyle(color: EditorTheme.textMuted, fontSize: 11);

  Widget _note(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
    child: Text(
      text,
      style: color == null ? _label : TextStyle(color: color, fontSize: 11),
    ),
  );

  /// A value's row: its label, the field, and — in a variant — whether
  /// the value is the variant's own (with a way back to the parent's) or
  /// its parent's. [key] is the value it edits (`effect.name`).
  Widget _row(String label, Widget field, {double indent = 0, String? key}) {
    final own = key != null && _isOwnValue(key);
    return Padding(
      padding: EdgeInsets.fromLTRB(12 + indent, 4, 12, 4),
      child: Row(
        children: [
          SizedBox(
            width: InspectorField.labelWidth - indent,
            child: Text(
              label,
              style: own
                  ? InspectorField.labelStyle.copyWith(
                      color: EditorTheme.accent,
                    )
                  : InspectorField.labelStyle,
            ),
          ),
          Expanded(child: field),
          if (key != null && material.isVariant) _inheritValue(key),
        ],
      ),
    );
  }

  /// Whether the variant gives [key] (`effect.name`) itself.
  bool _isOwnValue(String key) =>
      material.isVariant && material.values.containsKey(key);

  /// Whether the variant switches effect [id] itself, or gives any of its
  /// values.
  bool _isOwnEffect(String id) =>
      material.isVariant &&
      (material.effects.containsKey(id) ||
          material.values.keys.any((k) => k.startsWith('$id.')));

  Widget _inheritValue(String key) => _inherit(
    own: _isOwnValue(key),
    onRevert: () => edit(material.withoutValue(key)),
  );

  Widget _inheritEffect(String id) => _inherit(
    own: _isOwnEffect(id),
    onRevert: () => edit(material.withoutEffectOverride(id)),
  );

  Widget _inherit({required bool own, required VoidCallback onRevert}) =>
      SizedBox(
        width: 24,
        child: own
            ? EditorIconButton(
                icon: Icons.undo,
                tooltip: "Its own: back to the parent's",
                iconSize: 14,
                size: 22,
                onTap: onRevert,
              )
            : Tooltip(
                message: "The parent's",
                child: Icon(Icons.link, size: 12, color: EditorTheme.textMuted),
              ),
      );

  // In a variant, [child] with the sign of whose [key] is beside it.
  Widget _ownable(String key, Widget child) => !material.isVariant
      ? child
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: child),
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 12),
              child: _inheritValue(key),
            ),
          ],
        );

  /// A switch with its name beside it.
  Widget switchRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    bool strong = false,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      EditorToggle(value: value, label: label, onChanged: onChanged),
      const SizedBox(width: 6),
      Text(
        label,
        style: strong
            ? TextStyle(
                color: EditorTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              )
            : _label,
      ),
    ],
  );

  Widget _variant() {
    final m = material;
    final own = m.effects.length + m.values.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: EditorTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: EditorTheme.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.call_split, size: 14, color: EditorTheme.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Variant of ${Material2DWorkspaceState._nameOf(m.parent)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: EditorTheme.textPrimary,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      own == 0
                          ? 'Everything from its parent'
                          : '$own of its own, the rest from its parent',
                      style: _label,
                    ),
                  ],
                ),
              ),
              EditorButton(
                label: 'Open parent',
                kind: EditorButtonKind.ghost,
                onPressed: () =>
                    widget.workspace.scope.openInWorkspace(m.parent),
              ),
            ],
          ),
          if (own > 0)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                EditorButton(
                  label: 'Revert all',
                  kind: EditorButtonKind.ghost,
                  onPressed: revertAll,
                ),
                EditorButton(
                  label: 'Apply to parent',
                  kind: EditorButtonKind.ghost,
                  onPressed: applyToParent,
                ),
              ],
            ),
          for (final problem in _chainProblems)
            Text(
              problem,
              style: TextStyle(color: EditorTheme.warning, fontSize: 11),
            ),
        ],
      ),
    );
  }

  // Until the file is read — or when it could not be — only that, and a
  // way to read it again: fields over the defaults shown meanwhile would
  // save those over the file.
  Widget _unread() => ListView(
    children: [
      if (_error == null)
        _note('Loading…')
      else ...[
        _note("Can't be read: $_error", color: EditorTheme.warning),
        _note(
          'Nothing is saved over it. Put the file right (it is JSON) and '
          'read it again.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: EditorButton(
              label: 'Read it again',
              icon: Icons.refresh,
              kind: EditorButtonKind.ghost,
              onPressed: load,
            ),
          ),
        ),
      ],
    ],
  );

  Widget _fields() {
    if (!_loaded) return _unread();
    final m = shown;
    final problems = material.validate();
    return ListView(
      children: [
        if (_error != null) _note('$_error', color: EditorTheme.warning),
        if (material.isVariant) _variant(),
        const SizedBox(height: 6),
        _row(
          'Preset',
          EditorDropdown<String>(
            value: null,
            hint: 'Start from…',
            tooltip: 'Switches effects on with values, as one undo step',
            options: [
              for (final p in Material2DPreset.of(m.kind))
                EditorDropdownOption(
                  value: p.id,
                  label: p.label,
                  detail: p.detail,
                ),
            ],
            onChanged: (id) {
              final preset = Material2DPreset.byId(id);
              if (preset != null) change(preset.apply);
            },
          ),
        ),
        _row(
          'Kind',
          EditorSegmented<Material2DKind>(
            value: m.kind,
            options: const [
              (Material2DKind.sprite, 'Sprite'),
              (Material2DKind.screen, 'Screen'),
            ],
            disabled: material.isVariant
                ? const {Material2DKind.sprite, Material2DKind.screen}
                : const {},
            tooltips: const {
              Material2DKind.sprite: 'On sprites, shapes and tile layers',
              Material2DKind.screen: 'Over the whole frame, from the camera',
            },
            onChanged: (k) =>
                change((x) => Material2DWorkspaceState._asKind(x, k)),
          ),
        ),
        WorkspaceSections(view: _extensionView),
        for (final problem in problems)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              problem,
              style: TextStyle(color: EditorTheme.warning, fontSize: 11),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Effects ───────────────────────────────────────────────────────────

  // The effects panel, on the right: the effects that are on, in the order
  // they are applied, each a card; more are added from a menu.
  Widget _effects() {
    final m = shown;
    final on = [
      for (final e in Material2DEffects.forKind(m.kind))
        if (m.isOn(e.id)) e,
    ];
    // In a variant: effects it switches off itself, whatever its parent's.
    final offHere = [
      if (material.isVariant)
        for (final e in Material2DEffects.forKind(m.kind))
          if (material.effects[e.id] == false) e,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorSectionHeader(
          on.isEmpty ? 'Effects' : 'Effects · ${on.length}',
          trailing: Builder(
            builder: (context) => EditorButton(
              label: 'Add effect',
              icon: Icons.add,
              kind: EditorButtonKind.ghost,
              onPressed: _loaded ? () => openAddEffect(context) : null,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            controller: _effectsScroll,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              if (!_loaded)
                _note(_error == null ? 'Loading…' : 'Not read: no effects.')
              else if (on.isEmpty)
                _note('No effect is on yet: add one, or start from a preset.'),
              for (final e in on) _card(e, m),
              if (offHere.isNotEmpty) ...[
                const EditorSectionHeader('Off in this variant'),
                for (final e in offHere) _offRow(e),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // An effect a variant switches off itself, with a way back to its
  // parent's.
  Widget _offRow(Material2DEffect effect) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            effect.label,
            style: TextStyle(color: EditorTheme.textPrimary, fontSize: 12),
          ),
        ),
        _inheritEffect(effect.id),
      ],
    ),
  );

  Widget _param(Material2DEffect effect, Material2DParam p, Material2DFile m) {
    final key = '${effect.id}.${p.name}';
    void set(Object v) => change((x) => x.withValue(key, v));
    void show(Object v) => preview((x) => x.withValue(key, v));
    const indent = 16.0;
    switch (p.type) {
      case Material2DValue.number:
        final min = p.min ?? 0, max = p.max ?? 1;
        return _row(
          p.label,
          EditorSlider(
            value: m.number(key).clamp(min, max).toDouble(),
            min: min,
            max: max,
            step: (max - min) / 200,
            decimals: max - min > 20 ? 0 : 2,
            unit: p.unit,
            onChanged: (v) =>
                preview((x) => x.withValue(key, v), rebuild: false),
            onChangeEnd: set,
          ),
          indent: indent,
          key: key,
        );
      case Material2DValue.color:
        final argb = m.color(key);
        return _row(
          p.label,
          Align(
            alignment: Alignment.centerLeft,
            child: MiniColorField(
              key: ValueKey('$key:$argb'),
              color: Color(argb),
              title: '${effect.label}: ${p.label}',
              onPreview: (c) => show(c.toARGB32()),
              onPreviewEnd: endPreview,
              onChanged: (c) => set(c.toARGB32()),
            ),
          ),
          indent: indent,
          key: key,
        );
      case Material2DValue.toggle:
        return _row(
          p.label,
          Align(
            alignment: Alignment.centerLeft,
            child: EditorToggle(
              value: m.toggle(key),
              label: p.label,
              onChanged: set,
            ),
          ),
          indent: indent,
          key: key,
        );
      case Material2DValue.choice:
        final value = m.text(key);
        return _row(
          p.label,
          EditorSegmented<String>(
            value: value,
            options: [
              for (final c in p.choices)
                (c, Material2DWorkspaceState._title(c)),
            ],
            onChanged: set,
          ),
          indent: indent,
          key: key,
        );
      case Material2DValue.pair:
        final (x, y) = m.pair(key);
        final min = p.min ?? double.negativeInfinity;
        final max = p.max ?? double.infinity;
        Widget field(String axis, double v, List<double> Function(double) to) =>
            Expanded(
              child: Row(
                children: [
                  Text(axis, style: _label),
                  const SizedBox(width: 4),
                  Expanded(
                    child: MiniNumberField(
                      key: ValueKey('$key.$axis:$v'),
                      value: v,
                      fractionDigits: 1,
                      onSubmitted: (n) {
                        if (n.isFinite) set(to(n.clamp(min, max).toDouble()));
                      },
                    ),
                  ),
                ],
              ),
            );
        return _row(
          p.unit.isEmpty ? p.label : '${p.label} (${p.unit})',
          Row(
            children: [
              field('x', x, (n) => [n, y]),
              const SizedBox(width: 8),
              field('y', y, (n) => [x, n]),
            ],
          ),
          indent: indent,
          key: key,
        );
      case Material2DValue.path:
        final path = m.text(key);
        return _ownable(
          key,
          Padding(
            padding: const EdgeInsets.fromLTRB(12 + indent, 2, 12, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AssetRefFieldRow(
                  label: p.label,
                  value: path,
                  extensions: [
                    for (final e in Material2DFile.imageEndings) e.substring(1),
                  ],
                  onGenerate: effect.id == 'normalMap'
                      ? generateNormalMap
                      : null,
                  onChanged: set,
                ),
                if (path.isNotEmpty)
                  ValueListenableBuilder<int>(
                    valueListenable: _maps.revision,
                    builder: (context, _, _) => _mapDetail(path, () => set('')),
                  ),
                if (effect.id == 'normalMap')
                  Padding(
                    padding: const EdgeInsets.only(
                      left: InspectorField.labelWidth,
                      top: 2,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: EditorButton(
                        label: shownSpritePath == null
                            ? 'Make from a sprite…'
                            : 'Make from ${Material2DWorkspaceState._nameOf(shownSpritePath!)}',
                        kind: EditorButtonKind.ghost,
                        onPressed: () async {
                          final made = await generateNormalMap();
                          // The window may have closed meanwhile.
                          if (made != null && mounted) set(made);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      case Material2DValue.stops:
        final stops = m.stops(key);
        List<Object> saved(List<(double, int)> s) => [
          for (final (at, c) in s) [at, c],
        ];
        return _ownable(
          key,
          Padding(
            padding: const EdgeInsets.fromLTRB(12 + indent, 4, 12, 4),
            child: GradientStopsEditor(
              stops: stops,
              maxItems: p.maxItems,
              onPreview: (s) => show(saved(s)),
              onPreviewEnd: endPreview,
              onChanged: (s) => set(saved(s)),
            ),
          ),
        );
      case Material2DValue.swaps:
        final swaps = m.swaps(key);
        List<Object> saved(List<(int, int)> s) => [
          for (final (from, to) in s) [from, to],
        ];
        return _ownable(
          key,
          Padding(
            padding: const EdgeInsets.fromLTRB(12 + indent, 4, 12, 4),
            child: ColorSwapsEditor(
              swaps: swaps,
              maxItems: p.maxItems,
              suggestions:
                  _subject == Material2DSubject.sample ||
                      stage.autoShows == Material2DAuto.sample
                  ? Material2DSamples.spriteColors
                  : const [],
              onPreview: (s) => show(saved(s)),
              onPreviewEnd: endPreview,
              onChanged: (s) => set(saved(s)),
            ),
          ),
        );
    }
  }

  Widget _mapDetail(String path, VoidCallback onClear) {
    final picture = _maps.peek(path);
    final failed = _maps.failed(path);
    return Padding(
      padding: const EdgeInsets.fromLTRB(InspectorField.labelWidth, 2, 0, 2),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF15181D),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: EditorTheme.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: picture != null
                ? RawImage(image: picture.image, fit: BoxFit.contain)
                : Icon(
                    failed ? Icons.broken_image_outlined : Icons.image_outlined,
                    size: 16,
                    color: failed ? EditorTheme.warning : EditorTheme.textMuted,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              failed
                  ? "Can't be read"
                  : picture == null
                  ? 'Reading…'
                  : '${picture.width} × ${picture.height}',
              style: failed
                  ? TextStyle(color: EditorTheme.warning, fontSize: 11)
                  : _label,
            ),
          ),
          EditorButton(
            label: 'Clear',
            kind: EditorButtonKind.ghost,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}
