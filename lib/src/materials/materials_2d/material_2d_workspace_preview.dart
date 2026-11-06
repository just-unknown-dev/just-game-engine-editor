part of 'material_2d_workspace.dart';

/// The 2-D material window's preview: what it is drawn on, and how.
extension Material2DWorkspacePreview on Material2DWorkspaceState {
  Widget _previewPane() {
    final screen = shown.kind == Material2DKind.screen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(screen),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _view(screen)),
              Positioned(left: 10, right: 10, bottom: 8, child: _chips(screen)),
              if (_lightSettingsOpen && !screen)
                Positioned(
                  top: 8,
                  right: 10,
                  child: ValueListenableBuilder<int>(
                    valueListenable: _lightMoved,
                    builder: (context, _, _) => _lightSettings(),
                  ),
                ),
            ],
          ),
        ),
        if (stage.moving) _timeBar(),
      ],
    );
  }

  Widget _toolbar(bool screen) {
    final left = <Widget>[
      if (!screen)
        for (final s in Material2DSubject.values)
          EditorChip(
            label: s.label,
            icon: Material2DWorkspaceState._subjectIcons[s],
            tooltip: Material2DWorkspaceState._subjectTips[s],
            selected: _subject == s,
            onTap: () => setSubject(s),
          ),
      if (!screen && _subject == Material2DSubject.auto && _users.isNotEmpty)
        _usersChip(),
    ];
    final right = <Widget>[
      if (!screen) ...[
        EditorIconButton(
          icon: Icons.grid_on,
          tooltip: 'Tile 3 × 3: check the seams (T)',
          isActive: stage.tiled,
          onTap: () => setTiled(!stage.tiled),
        ),
        EditorIconButton(
          icon: Icons.terrain_outlined,
          tooltip: 'Normals: as the light sees them (N)',
          isActive: stage.showNormals,
          onTap: () => setShowNormals(!stage.showNormals),
        ),
      ],
      EditorIconButton(
        icon: Icons.compare,
        tooltip: 'Compare with and without the material (C; hold Space)',
        isActive: _compareAt != null,
        onTap: () => setCompare(_compareAt == null ? 0.5 : null),
      ),
      if (!screen) ...[
        const ToolSeparator(),
        EditorIconButton(
          icon: Icons.light_mode_outlined,
          tooltip: _lit ? 'Light on (L)' : 'Light off (L)',
          isActive: _lit,
          onTap: () => setLit(!_lit),
        ),
        EditorIconButton(
          icon: Icons.tune,
          tooltip: 'Light settings',
          isActive: _lightSettingsOpen,
          onTap: () => setLightSettingsOpen(!_lightSettingsOpen),
        ),
      ],
      const ToolSeparator(),
      // Its own size: in a wrap it would take the whole line.
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EditorSegmented<bool>(
            value: _lightBackground,
            options: const [(false, 'Dark'), (true, 'Bright')],
            tooltips: const {
              false: 'A dark background (B)',
              true: 'A light background (B)',
            },
            onChanged: setLightBackground,
          ),
        ],
      ),
      const ToolSeparator(),
      ValueListenableBuilder<int>(
        valueListenable: _framing,
        builder: (context, _, _) => ZoomControls(
          label: ValueListenableBuilder<double>(
            valueListenable: _drawnScale,
            builder: (context, scale, _) => Text(
              stage.zoom == null
                  ? 'Fit · ${(scale * 100).round()}%'
                  : '${(scale * 100).round()}%',
              textAlign: TextAlign.center,
              style: _label,
            ),
          ),
          onZoomOut: () => zoomBy(-1),
          onZoomIn: () => zoomBy(1),
          steps: [
            for (final (label, zoom, tip) in const [
              ('Fit', null, 'Fit it to the preview (F; double-click)'),
              ('1:1', 1.0, 'A pixel of it a pixel of the screen (1)'),
              ('2×', 2.0, 'Twice as big (2)'),
              ('4×', 4.0, 'Four times as big (4)'),
            ])
              ZoomStep(
                label,
                tip,
                selected: zoom == null
                    ? stage.zoom == null
                    : stage.zoom == zoom,
                onTap: () => zoom == null ? fit() : setZoom(zoom),
              ),
          ],
        ),
      ),
      WorkspaceToolButtons(view: _extensionView),
      const ToolSeparator(),
      ShortcutsHint(Material2DWorkspaceState.shortcuts),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 6,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: left,
          ),
          Wrap(
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: right,
          ),
        ],
      ),
    );
  }

  // Which of the game's sprites and shapes Auto shows it on.
  Widget _usersChip() {
    final user = _user;
    final more = _users.length > 1;
    return Builder(
      builder: (context) => Tooltip(
        message: more
            ? 'Shown on this; pick another drawn with the material'
            : 'Drawn with the material in the project',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: !more
              ? null
              : () async {
                  final picked = await showEditorMenuBelow<Material2DUser>(
                    context,
                    [
                      for (final u in _users)
                        editorMenuItem(
                          u,
                          u.count > 1 ? '${u.label}  × ${u.count}' : u.label,
                          icon: u.spritePath != null
                              ? Icons.image_outlined
                              : Icons.category_outlined,
                          color: identical(u, user) ? EditorTheme.accent : null,
                        ),
                    ],
                  );
                  if (picked != null) await pickUser(picked);
                },
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 3, 6, 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: EditorTheme.textPrimary.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  user?.spritePath != null
                      ? Icons.image_outlined
                      : Icons.category_outlined,
                  size: 12,
                  color: EditorTheme.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  user == null ? 'Nothing of the game' : 'On ${user.label}',
                  style: TextStyle(
                    color: EditorTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
                if (user != null && user.count > 1)
                  Text('  × ${user.count}', style: _label),
                if (more)
                  Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: EditorTheme.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // The light's settings, over the preview's corner.
  Widget _lightSettings() {
    Widget slider(
      String label,
      double value,
      double min,
      double max,
      void Function(double v) set,
    ) => _row(
      label,
      EditorSlider(
        value: value.clamp(min, max).toDouble(),
        min: min,
        max: max,
        step: (max - min) / 100,
        decimals: 2,
        onChanged: set,
        onChangeEnd: set,
      ),
    );

    return Container(
      width: 300,
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: EditorTheme.panelBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EditorTheme.border),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
            child: Row(
              children: [
                Icon(
                  Icons.light_mode_outlined,
                  size: 14,
                  color: EditorTheme.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  'The light',
                  style: TextStyle(
                    color: EditorTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                EditorIconButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  iconSize: 14,
                  size: 22,
                  onTap: () => setLightSettingsOpen(false),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final MapEntry(key: name, value: (at, height))
                    in Material2DWorkspaceState.lightPresets.entries)
                  EditorChip(
                    label: name,
                    selected: stage.light == at && stage.lightHeight == height,
                    onTap: () {
                      if (!_lit) setLit(true);
                      setLight(at: at, height: height);
                    },
                  ),
              ],
            ),
          ),
          _row(
            'Colour',
            Align(
              alignment: Alignment.centerLeft,
              child: MiniColorField(
                key: ValueKey('light:${stage.lightColor.toARGB32()}'),
                color: stage.lightColor,
                title: 'The light: colour',
                onPreview: (c) => setLight(color: c),
                onPreviewEnd: () {},
                onChanged: (c) => setLight(color: c),
              ),
            ),
          ),
          slider(
            'Height',
            stage.lightHeight,
            0.02,
            1,
            (v) => setLight(height: v),
          ),
          slider('Reach', stage.lightReach, 0.1, 2, (v) => setLight(reach: v)),
          slider(
            'Strength',
            stage.lightStrength,
            0,
            4,
            (v) => setLight(strength: v),
          ),
        ],
      ),
    );
  }

  // Play, pause, speed and where it is, for what moves.
  Widget _timeBar() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
    child: Row(
      children: [
        EditorIconButton(
          icon: _playing ? Icons.pause : Icons.play_arrow,
          tooltip: _playing ? 'Pause (P)' : 'Play (P)',
          onTap: () => setPlaying(!_playing),
        ),
        const SizedBox(width: 6),
        EditorSegmented<double>(
          value: _speed,
          options: const [(0.25, '¼×'), (0.5, '½×'), (1.0, '1×'), (2.0, '2×')],
          onChanged: setSpeed,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: _clock,
            builder: (context, t, _) => EditorSlider(
              value: t,
              min: 0,
              max: Material2DWorkspaceState.loop,
              step: 0.01,
              decimals: 2,
              unit: 's',
              onChanged: scrub,
              onChangeEnd: scrub,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _view(bool screen) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final lit = !screen && (_lit || stage.showNormals);
      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
            zoomBy(
              e.scrollDelta.dy < 0 ? 1 : -1,
              around: e.localPosition,
              size: size,
            );
          }
        },
        child: GestureDetector(
          onPanUpdate: (d) => panBy(d.delta),
          onDoubleTap: fit,
          // Built again as the compare line is dragged; the window is not.
          child: ValueListenableBuilder<int>(
            valueListenable: _compareLine,
            builder: (context, _, _) => _previewStack(size, lit: lit),
          ),
        ),
      );
    },
  );

  // The stage's picture, the compare line, the light's handle and what
  // modules lay over it.
  Widget _previewStack(Size size, {required bool lit}) {
    final split = _compareAt;
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: CustomPaint(
              size: size,
              painter: _StagePainter(
                stage,
                plainStage,
                () => _holdingPlain ? 1.0 : _compareAt,
                MediaQuery.devicePixelRatioOf(context),
                _repaint,
                onDrawn: (scale) {
                  if (scale == _drawnScale.value) return;
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _drawnScale.value = scale;
                  });
                },
              ),
            ),
          ),
        ),
        if (split != null && !_holdingPlain) ...[
          Positioned(
            left: split * size.width - 12,
            top: 0,
            bottom: 0,
            width: 24,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (d) =>
                    setCompare((split * size.width + d.delta.dx) / size.width),
                child: Center(
                  child: Container(
                    width: 2,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: size.width * (1 - split) + 10,
            child: PreviewChip('Without', icon: Icons.chevron_left),
          ),
          Positioned(
            top: 8,
            left: split * size.width + 10,
            child: PreviewChip('With', icon: Icons.chevron_right),
          ),
        ],
        if (lit)
          ValueListenableBuilder<int>(
            valueListenable: _lightMoved,
            builder: (context, _, _) => _lightHandle(size),
          ),
        ...workspaceOverlays(_extensionView, size),
      ],
    );
  }

  // The light: a sun to drag.
  Widget _lightHandle(Size size) {
    final at = stage.lightPosition(size);
    return Positioned(
      left: at.dx - 14,
      top: at.dy - 14,
      child: Tooltip(
        message: 'The light: drag it',
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: GestureDetector(
            onPanUpdate: (d) {
              final next = stage.lightPosition(size) + d.delta;
              setLight(at: Offset(next.dx / size.width, next.dy / size.height));
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.55),
                border: Border.all(color: EditorTheme.accent, width: 1.5),
              ),
              child: Icon(Icons.wb_sunny, size: 16, color: stage.lightColor),
            ),
          ),
        ),
      ),
    );
  }
}
