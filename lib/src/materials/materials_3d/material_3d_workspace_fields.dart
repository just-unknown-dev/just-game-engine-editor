part of 'material_3d_workspace.dart';

/// The 3-D material window's fields: the cards and rows that edit the
/// material.
extension Material3DWorkspaceFields on Material3DWorkspaceState {
  // ── Fields ────────────────────────────────────────────────────────────

  TextStyle get _label => TextStyle(color: EditorTheme.textMuted, fontSize: 11);

  Widget _note(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
    child: Text(
      text,
      style: color == null ? _label : TextStyle(color: color, fontSize: 11),
    ),
  );

  /// A field's row: its label, the field, and — in a variant — whether
  /// the value is the variant's own (with a way back to the parent's) or
  /// its parent's. [key] is the material key it edits.
  Widget _row(String label, Widget field, {String? key}) {
    final own = key != null && _isOwn(key);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: InspectorField.labelWidth,
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
          if (key != null && material.isVariant) _inherit(key),
        ],
      ),
    );
  }

  /// Whether [key] is the variant's own value.
  bool _isOwn(String key) =>
      material.isVariant && material.overrides.contains(key);

  /// In a variant: a way back to the parent's [key], or a sign that it is
  /// the parent's.
  Widget _inherit(String key) => SizedBox(
    width: 24,
    child: _isOwn(key)
        ? EditorIconButton(
            icon: Icons.undo,
            tooltip: "Its own: back to the parent's",
            iconSize: 14,
            size: 22,
            onTap: () => revert(key),
          )
        : Tooltip(
            message: "The parent's",
            child: Icon(Icons.link, size: 12, color: EditorTheme.textMuted),
          ),
  );

  Widget _color(
    String label,
    int argb,
    Material3DFile Function(Material3DFile m, int argb) set, {
    String? key,
  }) => _row(
    key: key,
    label,
    Align(
      alignment: Alignment.centerLeft,
      child: MiniColorField(
        key: ValueKey('$label:$argb'),
        color: Color(argb),
        title: label,
        onPreview: (c) => preview((m) => set(m, c.toARGB32())),
        onPreviewEnd: endPreview,
        onChanged: (c) => change((m) => set(m, c.toARGB32())),
      ),
    ),
  );

  Widget _slider(
    String label,
    double value,
    double max,
    Material3DFile Function(Material3DFile m, double v) set, {
    double min = 0,
    double? step,
    int decimals = 2,
    String unit = '',
    String? key,
  }) => _row(
    key: key,
    label,
    EditorSlider(
      value: value.clamp(min, max).toDouble(),
      min: min,
      max: max,
      step: step ?? (max - min) / 100,
      decimals: decimals,
      unit: unit,
      onChanged: (v) => preview((m) => set(m, v), rebuild: false),
      onChangeEnd: (v) => change((m) => set(m, v)),
    ),
  );

  Widget _number(
    String label,
    double value,
    Material3DFile Function(Material3DFile m, double v) set, {
    bool positive = false,
    String? key,
  }) => _row(
    key: key,
    label,
    MiniNumberField(
      key: ValueKey('$label:$value'),
      value: value,
      fractionDigits: 2,
      onSubmitted: (v) {
        if (!v.isFinite || (positive && v <= 0)) return;
        change((m) => set(m, v));
      },
    ),
  );

  Widget _toggle(
    String label,
    String text,
    bool value,
    Material3DFile Function(Material3DFile m, bool v) set, {
    String? key,
  }) => _row(
    key: key,
    label,
    Row(
      children: [
        EditorToggle(
          value: value,
          label: text,
          onChanged: (v) => change((m) => set(m, v)),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: _label)),
      ],
    ),
  );

  /// A map's slot: its image picked from the project's, its picture and
  /// size beside it, and a way to clear it.
  Widget _map(
    String label,
    String path,
    Material3DFile Function(Material3DFile m, String path) set, {
    String? key,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _padded(
        Row(
          children: [
            Expanded(
              child: AssetRefFieldRow(
                label: label,
                value: path,
                extensions: const ['png', 'jpg', 'jpeg', 'webp'],
                onChanged: (p) => change((m) => set(m, p)),
              ),
            ),
            if (key != null && material.isVariant) _inherit(key),
          ],
        ),
      ),
      if (path.isNotEmpty)
        ValueListenableBuilder<int>(
          valueListenable: _maps.revision,
          builder: (context, _, _) {
            final picture = _maps.peek(path);
            final failed = _maps.failed(path);
            return _slotDetail(
              picture: picture == null
                  ? null
                  : RawImage(image: picture.image, fit: BoxFit.contain),
              text: failed
                  ? "Can't be read"
                  : picture == null
                  ? 'Reading…'
                  : '${picture.width} × ${picture.height}',
              warn: failed,
              onClear: () => change((m) => set(m, '')),
            );
          },
        ),
    ],
  );

  Widget _slotDetail({
    required Widget? picture,
    required String text,
    bool warn = false,
    required VoidCallback onClear,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(
      12 + InspectorField.labelWidth,
      2,
      12,
      4,
    ),
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
          child:
              picture ??
              Icon(
                warn ? Icons.broken_image_outlined : Icons.image_outlined,
                size: 16,
                color: warn ? EditorTheme.warning : EditorTheme.textMuted,
              ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: warn
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

  Widget _padded(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    child: child,
  );

  /// A layer's slot: another material, pictured on its ball.
  Widget _layer(int i, String path) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _padded(
        AssetRefFieldRow(
          label:
              'Layer ${i + 1} (${const ['red', 'green', 'blue', 'alpha'][i]})',
          value: path,
          extensions: const ['material.json'],
          onChanged: (p) =>
              change((m) => Material3DWorkspaceState._withLayer(m, i, p)),
        ),
      ),
      if (path.isNotEmpty)
        ValueListenableBuilder<int>(
          valueListenable: widget.pictures.revision,
          builder: (context, _, _) {
            // One look at the file: whether it is there, and when it changed.
            final stat = FileStat.statSync(_fileOf(path).path);
            final there = stat.type != FileSystemEntityType.notFound;
            final image = there
                ? widget.pictures.peek(path, modified: stat.modified)
                : null;
            return _slotDetail(
              picture: image == null
                  ? null
                  : RawImage(image: image, fit: BoxFit.contain),
              text: there ? Material3DWorkspaceState._nameOf(path) : 'Missing',
              warn: !there,
              onClear: () =>
                  change((m) => Material3DWorkspaceState._withLayer(m, i, '')),
            );
          },
        ),
    ],
  );

  Widget _variant() {
    final m = material;
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
                      'Variant of ${Material3DWorkspaceState._nameOf(m.parent)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: EditorTheme.textPrimary,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      m.overrides.isEmpty
                          ? 'Everything from its parent'
                          : '${m.overrides.length} of its own, the rest from '
                                'its parent',
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
          if (m.overrides.isNotEmpty)
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

  Widget _presets() => _row(
    'Preset',
    EditorDropdown<String>(
      value: null,
      hint: 'Start from…',
      tooltip: 'Sets a few values at once, as one undo step',
      options: [
        for (final p in Material3DPreset.all)
          EditorDropdownOption(value: p.id, label: p.label, detail: p.detail),
      ],
      onChanged: (id) {
        final preset = Material3DPreset.byId(id);
        if (preset != null) change(preset.apply);
      },
    ),
  );

  /// Whether the card [card] holds anything but the defaults (in a
  /// variant: anything of its own).
  bool cardChanged(String card) {
    final keys = Material3DWorkspaceState.cardKeys[card]!;
    final m = material;
    if (m.isVariant) return keys.any(m.overrides.contains);
    // Saved, a material keeps only what differs from the defaults.
    final saved = m.toJson();
    return keys.any(saved.containsKey);
  }

  /// The card [card]'s values back to the defaults — in a variant, to its
  /// parent's — as one undo step.
  void resetCard(String card) {
    final keys = Material3DWorkspaceState.cardKeys[card]!;
    final m = material;
    if (m.isVariant) {
      edit(m.copyWith(overrides: {...m.overrides}..removeAll(keys)));
      return;
    }
    edit(
      Material3DFile.fromJson(
        m.toJson()..removeWhere((k, _) => keys.contains(k)),
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
    final m = _live ?? shown;
    final layered = m.kind == Material3DKind.layered;
    final problems = material.validate();
    return ListView(
      children: [
        if (_error != null) _note('$_error', color: EditorTheme.warning),
        if (material.isVariant) _variant(),
        const SizedBox(height: 6),
        _presets(),
        _row(
          key: 'kind',
          'Kind',
          EditorSegmented<Material3DKind>(
            value: m.kind,
            options: const [
              (Material3DKind.lit, 'Lit'),
              (Material3DKind.layered, 'Layered'),
            ],
            tooltips: const {
              Material3DKind.lit: 'A colour, how metal and how rough, and maps',
              Material3DKind.layered:
                  "Up to four materials blended by a mesh's vertex colours — "
                  'terrain',
            },
            onChanged: (k) => change((x) => x.copyWith(kind: k)),
          ),
        ),
        const SizedBox(height: 4),
        if (!layered) ...[
          _card('surface', [
            _color(
              'Colour',
              key: 'color',
              m.color,
              (x, v) => x.copyWith(color: v),
            ),
            _slider(
              'Metallic',
              key: 'metallic',
              m.metallic,
              1,
              (x, v) => x.copyWith(metallic: v),
            ),
            _slider(
              'Roughness',
              key: 'roughness',
              m.roughness,
              1,
              (x, v) => x.copyWith(roughness: v),
            ),
            _color(
              'Glow',
              key: 'emission',
              m.emission,
              (x, v) => x.copyWith(emission: v),
            ),
            _slider(
              'Glow strength',
              key: 'emissionStrength',
              m.emissionStrength,
              20,
              (x, v) => x.copyWith(emissionStrength: v),
            ),
            _toggle(
              'Unlit',
              key: 'unlit',
              'Ignore lights',
              m.unlit,
              (x, v) => x.copyWith(unlit: v),
            ),
            _toggle(
              'Two-sided',
              key: 'doubleSided',
              'Both faces',
              m.doubleSided,
              (x, v) => x.copyWith(doubleSided: v),
            ),
          ]),
          _card('transparency', [
            _row(
              key: 'alpha',
              'Mode',
              EditorSegmented<Material3DAlpha>(
                value: m.alpha,
                options: const [
                  (Material3DAlpha.opaque, 'Opaque'),
                  (Material3DAlpha.cutout, 'Cutout'),
                  (Material3DAlpha.blend, 'Blend'),
                ],
                tooltips: const {
                  Material3DAlpha.opaque: 'Solid: nothing shows through',
                  Material3DAlpha.cutout:
                      "Holes where the colour map's alpha is below the cutoff "
                      '— leaves, fences',
                  Material3DAlpha.blend:
                      'See-through by its opacity — glass, water',
                },
                onChanged: (a) => change((x) => x.copyWith(alpha: a)),
              ),
            ),
            if (m.alpha == Material3DAlpha.cutout)
              _slider(
                'Cutoff',
                key: 'alphaCutoff',
                m.alphaCutoff,
                1,
                (x, v) => x.copyWith(alphaCutoff: v),
              ),
            if (m.alpha == Material3DAlpha.blend)
              _slider(
                'Opacity',
                key: 'opacity',
                m.opacity,
                1,
                (x, v) => x.copyWith(opacity: v),
              ),
          ]),
          _card('maps', [
            _map(
              'Colour',
              key: 'colorMap',
              m.colorMap,
              (x, p) => x.copyWith(colorMap: p),
            ),
            _map(
              'Metal & rough',
              key: 'metalRoughMap',
              m.metalRoughMap,
              (x, p) => x.copyWith(metalRoughMap: p),
            ),
            _map(
              'Normal',
              key: 'normalMap',
              m.normalMap,
              (x, p) => x.copyWith(normalMap: p),
            ),
            if (m.normalMap.isNotEmpty)
              _slider(
                'Normal strength',
                key: 'normalScale',
                m.normalScale,
                2,
                (x, v) => x.copyWith(normalScale: v),
              ),
            _map(
              'Occlusion',
              key: 'occlusionMap',
              m.occlusionMap,
              (x, p) => x.copyWith(occlusionMap: p),
            ),
            if (m.occlusionMap.isNotEmpty)
              _slider(
                'Occlusion strength',
                key: 'occlusionStrength',
                m.occlusionStrength,
                1,
                (x, v) => x.copyWith(occlusionStrength: v),
              ),
            _map(
              'Glow',
              key: 'emissionMap',
              m.emissionMap,
              (x, p) => x.copyWith(emissionMap: p),
            ),
          ]),
        ] else
          _card('layers', [
            for (var i = 0; i < Material3DFile.maxLayers; i++)
              _layer(i, i < m.layers.length ? m.layers[i] : ''),
          ]),
        _card('layout', [
          _row(
            key: 'uv',
            'How',
            EditorSegmented<Material3DUv>(
              value: m.uv,
              options: const [
                (Material3DUv.natural, 'Mesh'),
                (Material3DUv.metres, 'Metres'),
                (Material3DUv.world, 'World'),
              ],
              tooltips: const {
                Material3DUv.natural: "As the mesh's own coordinates say",
                Material3DUv.metres:
                    'Repeated per metre along the mesh, at any size',
                Material3DUv.world:
                    'Projected from the world: no seams between pieces side '
                    'by side',
              },
              onChanged: (v) => change((x) => x.copyWith(uv: v)),
            ),
          ),
          _number(
            m.uv == Material3DUv.natural ? 'Repeat across' : 'Repeat per m',
            key: 'tiling',
            m.tilingX,
            (x, v) => x.copyWith(tilingX: v),
            positive: true,
          ),
          _number(
            m.uv == Material3DUv.natural
                ? 'Repeat down'
                : 'Repeat per m (down)',
            key: 'tiling',
            m.tilingY,
            (x, v) => x.copyWith(tilingY: v),
            positive: true,
          ),
          _number(
            'Shift across',
            key: 'offset',
            m.offsetX,
            (x, v) => x.copyWith(offsetX: v),
          ),
          _number(
            'Shift down',
            key: 'offset',
            m.offsetY,
            (x, v) => x.copyWith(offsetY: v),
          ),
          _slider(
            'Turn',
            key: 'rotation',
            m.rotation,
            180,
            (x, v) => x.copyWith(rotation: v),
            min: -180,
            step: 1,
            decimals: 0,
            unit: '°',
          ),
        ]),
        for (final problem in problems)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              problem,
              style: TextStyle(color: EditorTheme.warning, fontSize: 11),
            ),
          ),
        WorkspaceSections(view: _extensionView),
        const SizedBox(height: 16),
      ],
    );
  }
}
