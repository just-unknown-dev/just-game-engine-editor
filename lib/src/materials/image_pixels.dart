import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// An image's pixels: [width] × [height] RGBA, 8 bits a channel, alpha
/// not multiplied in, rows top to bottom.
final class Pixels {
  Pixels(this.width, this.height, [Uint8List? rgba])
    : rgba = rgba ?? Uint8List(width * height * 4);

  final int width, height;
  final Uint8List rgba;

  /// The channel [c] (0 red … 3 alpha) at [x], [y].
  int at(int x, int y, int c) => rgba[(y * width + x) * 4 + c];

  /// The image file at [path], its pixels — scaled to [width] × [height]
  /// when given. Throws when it can't be read as an image.
  static Future<Pixels> read(String path, {int? width, int? height}) async =>
      decode(await File(path).readAsBytes(), width: width, height: height);

  /// [bytes] (PNG, JPEG, …) decoded, scaled to [width] × [height] when
  /// given.
  static Future<Pixels> decode(
    Uint8List bytes, {
    int? width,
    int? height,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final ui.Image image;
    try {
      image = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    try {
      final w = width ?? image.width, h = height ?? image.height;
      if (w == image.width && h == image.height) return await _of(image);
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final scaled = await picture.toImage(w, h);
      picture.dispose();
      try {
        return await _of(scaled);
      } finally {
        scaled.dispose();
      }
    } finally {
      image.dispose();
    }
  }

  static Future<Pixels> _of(ui.Image image) async {
    // Straight alpha: a half-clear pixel keeps its own colour.
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return Pixels(
      image.width,
      image.height,
      Uint8List.fromList(data!.buffer.asUint8List()),
    );
  }

  /// How big the image file at [path] is, without decoding all of it.
  static Future<(int, int)> sizeOf(String path) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await File(path).readAsBytes(),
    );
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      return (descriptor.width, descriptor.height);
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  /// These pixels as a PNG file's bytes.
  Future<Uint8List> png() async {
    // The engine takes raw pixels with their alpha multiplied in.
    final premultiplied = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i += 4) {
      final a = rgba[i + 3];
      premultiplied
        ..[i] = (rgba[i] * a / 255).round()
        ..[i + 1] = (rgba[i + 1] * a / 255).round()
        ..[i + 2] = (rgba[i + 2] * a / 255).round()
        ..[i + 3] = a;
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(premultiplied);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  /// Writes these pixels to [path] as a PNG file.
  Future<void> writePng(String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(await png());
  }
}
