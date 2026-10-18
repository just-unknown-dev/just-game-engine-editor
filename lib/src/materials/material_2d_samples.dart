import 'dart:math' as math;
import 'dart:ui' as ui;

/// The pictures a 2-D material is previewed on when nothing of the game's
/// is chosen, drawn once and kept: a textured disc (clear edges for
/// outlines and glows, a few flat colours for palette swaps), a slime for a
/// screen material's scene, a tile, and a sky.
abstract final class Material2DSamples {
  static ui.Image? _sprite, _slime, _tile, _sky, _coin;
  static final Map<(int, int), ui.Image> _stones = {};

  /// The colours [sprite] is drawn in, darkest first: what a palette swap
  /// is tried on.
  static const List<int> spriteColours = [
    0xFFB94A46, // the rim
    0xFFF6736E, // the engine's coral
    0xFFFCE8DE, // cream
    0xFFFFFFFF, // the shine
  ];

  /// A disc 96 across, drawn three times as fine, on a clear background:
  /// what a sprite material is shown on when nothing of the game's is. A
  /// coral and cream checkerboard — a texture whose waves, scrolling and
  /// swapped colours show — inside a darker rim (a clean edge for outlines
  /// and glows), with a shine; every colour flat ([spriteColours]).
  static ui.Image get sprite => _sprite ??= _draw(96, 96, scale: 3, (c) {
    const centre = ui.Offset(48, 48), radius = 44.0, cell = 12.0;
    c
      ..save()
      ..clipPath(
        ui.Path()..addOval(ui.Rect.fromCircle(center: centre, radius: radius)),
      )
      ..drawRect(const ui.Rect.fromLTWH(0, 0, 96, 96), _fill(spriteColours[2]));
    final coral = _fill(spriteColours[1]);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        if ((x + y).isOdd) continue;
        c.drawRect(ui.Rect.fromLTWH(x * cell, y * cell, cell, cell), coral);
      }
    }
    c
      ..restore()
      ..drawCircle(
        centre,
        radius - 2,
        ui.Paint()
          ..color = ui.Color(spriteColours[0])
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 4,
      )
      ..save()
      ..translate(32, 28)
      ..rotate(-0.6)
      ..drawOval(
        const ui.Rect.fromLTWH(-11, -5, 22, 10),
        _fill(spriteColours[3]),
      )
      ..restore();
  });

  static const List<int> _slimeColours = [
    0xFF1B3A2A,
    0xFF2E7D32,
    0xFF4CAF50,
    0xFFA5D6A7,
    0xFFFFFFFF,
  ];

  /// A slime, 96 × 80 drawn three times as fine, on a clear background: the
  /// character of a screen material's scene.
  static ui.Image get slime => _slime ??= _draw(96, 80, scale: 3, (c) {
    final body = ui.Path()
      ..moveTo(8, 72)
      ..cubicTo(4, 40, 24, 10, 48, 10)
      ..cubicTo(72, 10, 92, 40, 88, 72)
      ..close();
    c
      ..drawPath(body, _fill(_slimeColours[0]))
      ..save()
      ..translate(48, 44)
      ..scale(0.9, 0.88)
      ..translate(-48, -44)
      ..drawPath(body, _fill(_slimeColours[1]))
      ..restore()
      ..save()
      ..translate(48, 40)
      ..scale(0.78, 0.74)
      ..translate(-48, -40)
      ..drawPath(body, _fill(_slimeColours[2]))
      ..restore()
      ..drawOval(
        const ui.Rect.fromLTWH(26, 22, 18, 10),
        _fill(_slimeColours[3]),
      )
      ..drawOval(
        const ui.Rect.fromLTWH(32, 38, 12, 16),
        _fill(_slimeColours[4]),
      )
      ..drawOval(
        const ui.Rect.fromLTWH(54, 38, 12, 16),
        _fill(_slimeColours[4]),
      )
      ..drawOval(const ui.Rect.fromLTWH(37, 44, 6, 8), _fill(_slimeColours[0]))
      ..drawOval(const ui.Rect.fromLTWH(59, 44, 6, 8), _fill(_slimeColours[0]));
  });

  /// A stone block with grass on top, 64 × 64 drawn twice as fine: what
  /// tiles are tried on.
  static ui.Image get tile => _tile ??= _draw(64, 64, scale: 2, (c) {
    c.drawRect(const ui.Rect.fromLTWH(0, 0, 64, 64), _fill(0xFF6E5E4E));
    final mortar = _fill(0xFF4A3F35);
    for (final r in const [
      ui.Rect.fromLTWH(0, 30, 64, 3),
      ui.Rect.fromLTWH(0, 47, 64, 3),
      ui.Rect.fromLTWH(30, 14, 3, 16),
      ui.Rect.fromLTWH(14, 33, 3, 14),
      ui.Rect.fromLTWH(46, 33, 3, 14),
      ui.Rect.fromLTWH(30, 50, 3, 14),
    ]) {
      c.drawRect(r, mortar);
    }
    c
      ..drawRect(const ui.Rect.fromLTWH(0, 0, 64, 14), _fill(0xFF5DAA4A))
      ..drawRect(const ui.Rect.fromLTWH(0, 10, 64, 4), _fill(0xFF3F8A33));
    for (var x = 2; x < 64; x += 8) {
      c.drawRect(ui.Rect.fromLTWH(x.toDouble(), 14, 4, 3), _fill(0xFF3F8A33));
    }
  });

  /// A plain stone tile [width] × [height]: one even colour, so a normal
  /// map's bumps are all there is to see on it.
  static ui.Image stone(int width, int height) =>
      _stones[(width, height)] ??= _draw(width, height, (c) {
        c.drawRect(
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          _fill(0xFF8A8D94),
        );
      });

  /// A coin, 32 × 32 drawn twice as fine.
  static ui.Image get coin => _coin ??= _draw(32, 32, scale: 2, (c) {
    c
      ..drawCircle(const ui.Offset(16, 16), 15, _fill(0xFF9C6B10))
      ..drawCircle(const ui.Offset(16, 16), 12, _fill(0xFFFFC83D))
      ..drawRect(const ui.Rect.fromLTWH(14, 9, 4, 14), _fill(0xFFFFE9A0));
  });

  /// A dusk sky with a sun and hills, 256 × 160 drawn three times as
  /// fine: a screen material's scene.
  static ui.Image get sky => _sky ??= _draw(256, 160, scale: 3, (c) {
    const rect = ui.Rect.fromLTWH(0, 0, 256, 160);
    c
      ..drawRect(
        rect,
        ui.Paint()
          ..shader = ui.Gradient.linear(
            ui.Offset.zero,
            const ui.Offset(0, 160),
            const [ui.Color(0xFF243B6B), ui.Color(0xFFF2A65A)],
          ),
      )
      ..drawCircle(const ui.Offset(176, 92), 26, _fill(0xFFFFE3A3));
    final hills = ui.Path()..moveTo(0, 160);
    for (var x = 0; x <= 256; x += 8) {
      hills.lineTo(x.toDouble(), 118 - 14 * math.sin(x / 34));
    }
    hills
      ..lineTo(256, 160)
      ..close();
    c.drawPath(hills, _fill(0xFF3B2E4A));
  });

  /// How big [image] — one of these samples — is at a scale of 1, in
  /// logical pixels: they are drawn finer than that. Any other image, its
  /// own size.
  static ui.Size sizeOf(ui.Image image) {
    if (identical(image, _sprite)) return const ui.Size(96, 96);
    if (identical(image, _slime)) return const ui.Size(96, 80);
    if (identical(image, _tile)) return const ui.Size(64, 64);
    if (identical(image, _coin)) return const ui.Size(32, 32);
    if (identical(image, _sky)) return const ui.Size(256, 160);
    return ui.Size(image.width.toDouble(), image.height.toDouble());
  }

  static ui.Paint _fill(int argb) => ui.Paint()..color = ui.Color(argb);

  // Drawn at [w] by [h], [scale] times as many pixels each way.
  static ui.Image _draw(
    int w,
    int h,
    void Function(ui.Canvas c) paint, {
    int scale = 1,
  }) {
    final recorder = ui.PictureRecorder();
    paint(ui.Canvas(recorder)..scale(scale.toDouble()));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w * scale, h * scale);
    picture.dispose();
    return image;
  }
}
