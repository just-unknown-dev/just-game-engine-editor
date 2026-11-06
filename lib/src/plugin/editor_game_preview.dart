part of 'just_game_editor_plugin.dart';

/// The game camera's preview: where its panel sits and how it is drawn.
extension PluginGamePreview on JustGameEditorPlugin {
  /// A small view through the game's live camera, in a panel that matches
  /// the play toolbar it hangs below.
  ///
  /// The world is rendered a second time with the output camera briefly
  /// showing what the brain wants, then handed back exactly as it was — so
  /// the author sees the shot they are composing without leaving the view
  /// they are composing it from.
  void _paintGamePreview(Canvas canvas, Size size, OutputCamera camera) {
    if (!showGamePreview.value || !isAuthoring.value) return;
    // Under a workspace the level is dimmed and covered: nobody sees it.
    if (scope.activeWorkspace.value != null) return;
    final brain = scope.cameraBrain;
    final shot = brain?.liveState;
    final live = brain?.liveCamera;
    if (brain == null || shot == null || live == null) return;

    final style = gamePreviewStyle;
    final panel = JustGameEditorPlugin.gamePreviewRect(
      size,
      origin: gamePreviewOrigin,
      style: style,
      bottomReserve: gamePreviewBottomReserve,
    );
    final frame = RRect.fromRectAndRadius(
      panel,
      Radius.circular(style.cornerRadius),
    );
    // The toolbar's frame: same fill, same border, same corners.
    canvas
      ..drawRRect(frame, Paint()..color = EditorTheme.statusBadgeBg)
      ..drawRRect(
        frame.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = style.borderColor ?? EditorTheme.accent,
      );

    final viewRect = JustGameEditorPlugin.gamePreviewViewRect(
      panel,
      style: style,
    );
    final viewFrame = RRect.fromRectAndRadius(
      viewRect,
      Radius.circular((style.cornerRadius - style.padding).clamp(2.0, 12.0)),
    );
    final view = camera.state;
    canvas
      ..save()
      ..clipRRect(viewFrame)
      ..drawRect(viewRect, Paint()..color = const Color(0xFF0E1216))
      ..translate(viewRect.left, viewRect.top);
    camera.apply(shot);
    try {
      // A 3-D backend's image first, as the game draws it — in space made
      // at the panel's own size (it has the canvas's shape), not a second
      // full-size picture scaled down every frame, as the split panes do.
      final renderers = engine.rendering.sceneRenderers;
      if (renderers.isNotEmpty) {
        final frame = _previewFrame
          ..update(
            camera,
            viewRect.size,
            interpolation: engine.rendering.interpolation,
          );
        if (frame.isPlanar) {
          frame.update(
            camera,
            size,
            interpolation: engine.rendering.interpolation,
          );
          canvas
            ..save()
            ..scale(viewRect.width / size.width);
        }
        for (final renderer in renderers) {
          if (renderer.enabled) renderer.render(canvas, frame);
        }
        if (frame.isPlanar) canvas.restore();
      }
      // Drawn straight into the frame. Recorded into a picture of its own
      // and replayed, a lit, material-heavy level filled the GPU's memory
      // (the 2-D materials make fresh images every flush) and Impeller
      // aborted.
      canvas.scale(viewRect.width / size.width);
      engine.world.render(canvas, size);
    } finally {
      camera
        ..apply(view)
        ..viewportSize = size;
      canvas.restore();
    }
    canvas.drawRRect(
      viewFrame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = EditorTheme.border,
    );

    _paintGamePreviewHeader(
      canvas,
      Rect.fromLTWH(
        viewRect.left,
        panel.top + style.padding,
        viewRect.width,
        JustGameEditorPlugin.gamePreviewHeaderHeight,
      ),
      name: live.name ?? 'camera',
      isSolo: brain.soloEntity == live.id,
      isBlending: brain.activeBlend != null,
    );
  }

  /// `● LIVE  MainCamera` — the toolbar's status chip, then the camera.
  void _paintGamePreviewHeader(
    Canvas canvas,
    Rect row, {
    required String name,
    required bool isSolo,
    required bool isBlending,
  }) {
    const accent = CameraRigPainter.live;
    TextPainter text(String value, TextStyle style, double maxWidth) =>
        TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: maxWidth < 0 ? 0 : maxWidth);

    final state = text(
      isSolo ? 'SOLO' : 'LIVE',
      const TextStyle(
        color: accent,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
      row.width,
    );
    // The chip: a pill with a dot, as on the toolbar while playing.
    final chip = Rect.fromLTWH(
      row.left,
      row.top + (row.height - 16) / 2 - 2,
      7 + 6 + 5 + state.width + 7,
      16,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(chip, const Radius.circular(10)),
        Paint()..color = accent.withValues(alpha: 0.14),
      )
      ..drawCircle(
        Offset(chip.left + 10, chip.center.dy),
        3,
        Paint()..color = accent,
      );
    state.paint(
      canvas,
      Offset(chip.left + 18, chip.center.dy - state.height / 2),
    );

    final blending = isBlending
        ? text(
            'blending',
            TextStyle(
              color: EditorTheme.textMuted,
              fontSize: 9,
              fontStyle: FontStyle.italic,
            ),
            row.width,
          )
        : null;
    final label = text(
      name,
      TextStyle(
        color: EditorTheme.textBright,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
      row.right - chip.right - 8 - (blending == null ? 0 : blending.width + 8),
    );
    label.paint(
      canvas,
      Offset(chip.right + 8, chip.center.dy - label.height / 2),
    );
    blending?.paint(
      canvas,
      Offset(row.right - blending.width, chip.center.dy - blending.height / 2),
    );
    // Laid out every frame the preview shows: their paragraphs are native
    // memory, let go of now rather than when the collector gets to them.
    state.dispose();
    label.dispose();
    blending?.dispose();
  }
}
