import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'image_pixels.dart';

/// How a normal map is made from a picture.
final class NormalMapOptions {
  const NormalMapOptions({
    this.strength = 2,
    this.bevel = 0,
    this.tiles = false,
    this.invert = false,
  });

  /// For a sprite: rounded edges [bevel] pixels wide, from where it is
  /// clear, and nothing where it is clear.
  const NormalMapOptions.sprite({
    this.strength = 2,
    this.bevel = 4,
    this.invert = false,
  }) : tiles = false;

  /// For a texture that repeats: its edges meet, nothing is clear.
  const NormalMapOptions.tiling({this.strength = 2, this.invert = false})
    : bevel = 0,
      tiles = true;

  /// How steep the bumps are.
  final double strength;

  /// How many pixels in from a clear edge the surface rounds off; 0 for
  /// no rounding.
  final int bevel;

  /// Whether the picture repeats: its left edge meets its right, its top
  /// its bottom.
  final bool tiles;

  /// Whether dark is high (light is high otherwise).
  final bool invert;
}

/// Normal maps made from a picture: its brightness taken as height
/// (light high, unless inverted), rounded at a sprite's clear edges, the
/// slope of that turned into each pixel's normal.
///
/// OpenGL-style, as the engine reads them in 2-D and 3-D: red is right,
/// green is up, blue is out of the picture. Where the picture is clear,
/// the map is clear too.
abstract final class NormalMaps {
  /// The normal map of [picture].
  static Pixels of(
    Pixels picture, {
    NormalMapOptions options = const NormalMapOptions(),
  }) {
    final w = picture.width, h = picture.height;
    final height = Float32List(w * h);
    final src = picture.rgba;
    for (var i = 0; i < w * h; i++) {
      final r = src[i * 4], g = src[i * 4 + 1], b = src[i * 4 + 2];
      final a = src[i * 4 + 3] / 255;
      var lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
      if (options.invert) lum = 1 - lum;
      height[i] = options.tiles ? lum : lum * a;
    }
    if (options.bevel > 0 && !options.tiles) {
      final rounded = _bevel(picture, options.bevel);
      for (var i = 0; i < w * h; i++) {
        // Half the picture's own bumps, half the rounded edge.
        height[i] = height[i] * 0.5 + rounded[i] * 0.5;
      }
    }
    double at(int x, int y) {
      if (options.tiles) {
        x %= w;
        y %= h;
        if (x < 0) x += w;
        if (y < 0) y += h;
      } else {
        x = x.clamp(0, w - 1);
        y = y.clamp(0, h - 1);
      }
      return height[y * w + x];
    }

    final out = Pixels(w, h);
    final dst = out.rgba;
    final s = options.strength;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        // Sobel: the slope across and down, smoothed.
        final dx =
            (at(x + 1, y - 1) + 2 * at(x + 1, y) + at(x + 1, y + 1)) -
            (at(x - 1, y - 1) + 2 * at(x - 1, y) + at(x - 1, y + 1));
        final dy =
            (at(x - 1, y + 1) + 2 * at(x, y + 1) + at(x + 1, y + 1)) -
            (at(x - 1, y - 1) + 2 * at(x, y - 1) + at(x + 1, y - 1));
        // Up is against the picture's rows: higher below, the normal
        // leans up.
        var nx = -dx * s, ny = dy * s;
        const nz = 1.0;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        nx /= len;
        ny /= len;
        final i = (y * w + x) * 4;
        dst[i] = ((nx * 0.5 + 0.5) * 255).round();
        dst[i + 1] = ((ny * 0.5 + 0.5) * 255).round();
        dst[i + 2] = ((nz / len * 0.5 + 0.5) * 255).round();
        dst[i + 3] = options.tiles ? 255 : src[i + 3];
      }
    }
    return out;
  }

  /// How far in from a clear edge each pixel is, as a height rising from
  /// 0 at the edge to 1 at [width] pixels in (eased, so it rounds).
  static Float32List _bevel(Pixels picture, int width) {
    final w = picture.width, h = picture.height;
    // Distance to the nearest clear pixel, by two passes (a chamfer).
    const far = 1 << 20;
    final d = Int32List(w * h);
    for (var i = 0; i < w * h; i++) {
      d[i] = picture.rgba[i * 4 + 3] < 128 ? 0 : far;
    }
    int get(int x, int y) =>
        x < 0 || y < 0 || x >= w || y >= h ? 0 : d[y * w + x];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (d[i] == 0) continue;
        d[i] = math.min(
          d[i],
          math.min(
            math.min(get(x - 1, y) + 2, get(x, y - 1) + 2),
            math.min(get(x - 1, y - 1) + 3, get(x + 1, y - 1) + 3),
          ),
        );
      }
    }
    for (var y = h - 1; y >= 0; y--) {
      for (var x = w - 1; x >= 0; x--) {
        final i = y * w + x;
        if (d[i] == 0) continue;
        d[i] = math.min(
          d[i],
          math.min(
            math.min(get(x + 1, y) + 2, get(x, y + 1) + 2),
            math.min(get(x + 1, y + 1) + 3, get(x - 1, y + 1) + 3),
          ),
        );
      }
    }
    final out = Float32List(w * h);
    for (var i = 0; i < w * h; i++) {
      final t = (d[i] / 2 / width).clamp(0.0, 1.0);
      // A quarter circle: steep at the edge, flat on top.
      out[i] = math.sqrt(1 - (1 - t) * (1 - t));
    }
    return out;
  }

  /// Makes the normal map of the image at [path] (project-relative) under
  /// [root], beside it — `<name>_normal.png`, `_2` and on when that is
  /// taken — and gives its path.
  static Future<String> generate(
    String root,
    String path, {
    NormalMapOptions options = const NormalMapOptions(),
  }) async {
    final map = of(await Pixels.read('$root/$path'), options: options);
    final dot = path.lastIndexOf('.');
    final stem = dot <= path.lastIndexOf('/') ? path : path.substring(0, dot);
    var n = 1;
    String out() => '${stem}_normal${n == 1 ? '' : '_$n'}.png';
    while (File('$root/${out()}').existsSync()) {
      n++;
    }
    final made = out();
    await map.writePng('$root/$made');
    return made;
  }

  /// [map], a DirectX-style normal map (green down), as an OpenGL-style
  /// one: its green turned over.
  static Pixels flipGreen(Pixels map) {
    final out = Pixels(map.width, map.height, Uint8List.fromList(map.rgba));
    for (var i = 1; i < out.rgba.length; i += 4) {
      out.rgba[i] = 255 - out.rgba[i];
    }
    return out;
  }
}
