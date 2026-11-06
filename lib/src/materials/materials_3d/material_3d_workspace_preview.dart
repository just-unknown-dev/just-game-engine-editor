part of 'material_3d_workspace.dart';

/// The 3-D material window's preview: the shape, its light and
/// backdrop.
extension Material3DWorkspacePreview on Material3DWorkspaceState {
  Widget _previewPane() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _toolbar(),
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(child: _view()),
            Positioned(left: 10, right: 10, bottom: 8, child: _chips()),
          ],
        ),
      ),
    ],
  );

  Widget _toolbar() {
    final hasScene = sceneLighting != null;
    final left = <Widget>[
      for (final s in PreviewShape.values)
        EditorChip(
          label: s.label,
          icon: Material3DWorkspaceState._shapeLooks[s]!.$1,
          tooltip: Material3DWorkspaceState._shapeLooks[s]!.$2,
          selected: _shape == s,
          onTap: () => setShape(s),
        ),
    ];
    final right = <Widget>[
      EditorIconButton(
        icon: Icons.compare,
        tooltip: 'Compare with a plain grey material (C; hold Space)',
        isActive: _compareAt != null,
        onTap: () => setCompare(_compareAt == null ? 0.5 : null),
      ),
      const ToolSeparator(),
      SizedBox(
        width: 120,
        child: EditorDropdown<PreviewLighting>(
          value: _lighting,
          tooltip: 'The light the preview is drawn in',
          options: [
            for (final l in PreviewLighting.values)
              EditorDropdownOption(
                value: l,
                label: l.label,
                detail: l == PreviewLighting.scene && !hasScene
                    ? 'No 3-D scene open: studio light'
                    : null,
              ),
          ],
          onChanged: setLighting,
        ),
      ),
      const ToolSeparator(),
      // Its own size: in a wrap it would take the whole line.
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EditorSegmented<PreviewBackdrop>(
            value: _backdrop,
            options: [for (final b in PreviewBackdrop.values) (b, b.label)],
            tooltips: const {
              PreviewBackdrop.sky: "The light's own sky behind it (B)",
              PreviewBackdrop.dark: 'A dark background (B)',
              PreviewBackdrop.bright: 'A light background (B)',
            },
            onChanged: setBackdrop,
          ),
        ],
      ),
      const ToolSeparator(),
      ValueListenableBuilder<int>(
        valueListenable: _framing,
        builder: (context, _, _) => ZoomControls(
          label: Text('${(zoom * 100).round()}%', style: _label),
          onZoomOut: () => zoomBy(-1),
          onZoomIn: () => zoomBy(1),
          steps: [
            ZoomStep(
              'Fit',
              'Face it again, as it started (F; double-click)',
              selected: atStart,
              onTap: fit,
            ),
          ],
        ),
      ),
      WorkspaceToolButtons(view: _extensionView),
      const ToolSeparator(),
      ShortcutsHint(Material3DWorkspaceState.shortcuts),
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

  // What the preview says: in chips over its foot.
  Widget _chips() => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      if (_holdingPlain)
        const PreviewChip('A plain grey in its place', icon: Icons.compare),
      if (_drawError case final error?)
        PreviewChip('$error', icon: Icons.warning_amber_rounded, warn: true),
      if (_lighting == PreviewLighting.scene && sceneLighting == null)
        const PreviewChip(
          'No 3-D scene open: studio light',
          icon: Icons.info_outline,
        ),
      const PreviewChip(
        'Drag to turn · scroll to zoom · double-click to face it again',
        icon: Icons.threed_rotation,
      ),
    ],
  );

  Widget _picture(ui.Image? image) => Center(
    child: image == null
        ? Text(_noGpu ? 'No GPU for a preview.' : 'Loading…', style: _label)
        : RawImage(image: image, fit: BoxFit.contain),
  );

  Widget _view() => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      // The surfaces are kept, and resized as they are drawn into: one
      // made for every size a dragged panel went through held GPU memory
      // until the card was full.
      if (size != _size && size.width > 0 && size.height > 0) {
        _size = size;
        _resized?.cancel();
        if (_image == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _redraw());
        } else {
          // While a panel is dragged the picture is scaled to fit, and
          // drawn again once its size stops changing: each size drawn at
          // took fresh textures.
          _resized = Timer(Material3DWorkspaceState.resizeSettle, _redraw);
        }
      }
      return Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) return;
          _zoomTo(_zoom * math.pow(0.999, event.scrollDelta.dy));
        },
        child: GestureDetector(
          onPanUpdate: (d) {
            _yaw += d.delta.dx * 0.01;
            _pitch = (_pitch - d.delta.dy * 0.01).clamp(-1.5, 1.5);
            _turned();
          },
          onDoubleTap: fit,
          // Built again as the compare line is dragged; the window is not.
          child: ValueListenableBuilder<int>(
            valueListenable: _compareLine,
            builder: (context, _, _) => _previewStack(size),
          ),
        ),
      );
    },
  );

  // The preview's pictures, the compare line and what modules lay over it.
  Widget _previewStack(Size size) {
    final split = _holdingPlain ? 1.0 : _compareAt;
    return Stack(
      children: [
        Positioned.fill(
          child: ValueListenableBuilder<int>(
            valueListenable: _pictures,
            builder: (context, _, _) {
              final plain = _plainImage;
              return ColoredBox(
                color: const Color(0xFF15181D),
                child: split == null || plain == null
                    ? _picture(_image)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRect(
                            clipper: _Side(split, left: true),
                            child: _picture(plain),
                          ),
                          if (split < 1)
                            ClipRect(
                              clipper: _Side(split, left: false),
                              child: _picture(_image),
                            ),
                        ],
                      ),
              );
            },
          ),
        ),
        if (_compareAt case final at? when !_holdingPlain) ...[
          Positioned(
            left: at * size.width - 12,
            top: 0,
            bottom: 0,
            width: 24,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (d) =>
                    setCompare((at * size.width + d.delta.dx) / size.width),
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
            right: size.width * (1 - at) + 10,
            child: const PreviewChip('Plain', icon: Icons.chevron_left),
          ),
          Positioned(
            top: 8,
            left: at * size.width + 10,
            child: const PreviewChip('With', icon: Icons.chevron_right),
          ),
        ],
        ...workspaceOverlays(_extensionView, size),
      ],
    );
  }
}
