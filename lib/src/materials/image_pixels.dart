import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart' show ProjectFiles;

/// An image's pixels: [width] × [height] RGBA, 8 bits a channel, alpha
/// not multiplied in, rows top to bottom.
final class Pixels {
  /// [width] × [height] pixels: [rgba] when given (its length must be
  /// `width * height * 4`), else all clear black.
  Pixels(this.width, this.height, [Uint8List? rgba])
    : rgba = rgba ?? Uint8List(width * height * 4);

  /// The image's size, in pixels.
  final int width, height;

  /// The pixels, four bytes each — red, green, blue, alpha — row by row
  /// from the top left.
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
    // The engine takes raw pixels with their alpha multiplied in: worked
    // out off the UI's isolate, as a big image takes a while.
    final premultiplied = await compute(_premultiplied, rgba);
    final buffer = await ui.ImmutableBuffer.fromUint8List(premultiplied);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      codec = await descriptor.instantiateCodec();
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      // Let go however it went.
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  static Uint8List _premultiplied(Uint8List rgba) {
    final out = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i += 4) {
      final a = rgba[i + 3];
      out
        ..[i] = (rgba[i] * a / 255).round()
        ..[i + 1] = (rgba[i + 1] * a / 255).round()
        ..[i + 2] = (rgba[i + 2] * a / 255).round()
        ..[i + 3] = a;
    }
    return out;
  }

  /// Writes these pixels to [path] as a PNG file, whole or not at all
  /// (its folder made when missing).
  Future<void> writePng(String path) async =>
      ProjectFiles.writeBytes(path, await png());
}
