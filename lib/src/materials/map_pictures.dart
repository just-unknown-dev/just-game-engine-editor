import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// A map's picture for its slot: small, and how big the image really is.
final class MapPicture {
  const MapPicture(this.image, this.width, this.height);

  /// The image, at most [MapPictures.size] pixels across.
  final ui.Image image;

  /// The image file's own size, in pixels.
  final int width, height;
}

/// Small pictures of the images a material's maps name, read from the
/// project once each and kept until [forget].
final class MapPictures {
  MapPictures({required this.root});

  /// The project folder map paths are under.
  final String root;

  /// How many pixels across a picture is at most.
  static const int size = 64;

  final Map<String, Object> _reading = {};
  final Map<String, MapPicture?> _done = {};
  bool _disposed = false;

  /// Bumped when a picture is ready or goes stale.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// The picture of the image at [path] if it is ready (null when it
  /// can't be read); asking starts it.
  MapPicture? peek(String path) {
    if (_done.containsKey(path)) return _done[path];
    if (!_reading.containsKey(path)) {
      final token = Object();
      _reading[path] = token;
      _read(path, token);
    }
    return null;
  }

  /// Whether [path] was read and could not be.
  bool failed(String path) => _done.containsKey(path) && _done[path] == null;

  Future<void> _read(String path, Object token) async {
    MapPicture? picture;
    try {
      final bytes = await File('$root/$path').readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      final codec = await descriptor.instantiateCodec(
        targetWidth: w >= h ? (w < size ? w : size) : null,
        targetHeight: h > w ? (h < size ? h : size) : null,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      picture = MapPicture(frame.image, w, h);
    } on Object catch (error) {
      debugPrint('just_material_editor: no picture of map "$path": $error');
    }
    // Forgotten meanwhile (or read again since): this one is stale.
    if (_disposed || !identical(_reading[path], token)) {
      picture?.image.dispose();
      return;
    }
    _reading.remove(path);
    _done[path] = picture;
    revision.value++;
  }

  /// [path] changed on disk: it is read again when next asked for.
  void forget(String path) {
    // Not disposed: a slot may still be showing it until it rebuilds.
    final reading = _reading.remove(path) != null;
    final done = _done.containsKey(path);
    _done.remove(path);
    if ((reading || done) && !_disposed) revision.value++;
  }

  /// Lets the pictures go.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final p in _done.values) {
      p?.image.dispose();
    }
    _done.clear();
    _reading.clear();
    revision.dispose();
  }
}
