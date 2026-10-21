import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart' show PackageAssetPaths;

/// A map's picture for its slot: small, and how big the image really is.
final class MapPicture {
  const MapPicture(this.image, this.width, this.height);

  /// The image, at most [MapPictures.size] pixels across.
  final ui.Image image;

  /// The image file's own size, in pixels.
  final int width, height;
}

/// Small pictures of the images a material's maps name, read from the
/// project (or a package, for its asset keys) once each and kept until
/// [forget].
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
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      // A project path, or a package's asset key.
      final bytes = await File(
        PackageAssetPaths.of(root).absolute(path),
      ).readAsBytes();
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      codec = await descriptor.instantiateCodec(
        targetWidth: w >= h ? (w < size ? w : size) : null,
        targetHeight: h > w ? (h < size ? h : size) : null,
      );
      final frame = await codec.getNextFrame();
      picture = MapPicture(frame.image, w, h);
    } on Object catch (error) {
      debugPrint('just_game_engine_editor: no picture of map "$path": $error');
    } finally {
      // Let go however it went: a broken image throws halfway.
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
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
    final reading = _reading.remove(path) != null;
    final done = _done.containsKey(path);
    // A slot showing it has its own handle on it (RawImage clones it).
    _done.remove(path)?.image.dispose();
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
