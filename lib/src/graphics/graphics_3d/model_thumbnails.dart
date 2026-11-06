import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart' show PackageAssetPaths;
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show Render3DView, gltfToEngine;

/// Pictures of model files for the Assets dock and the palettes, rendered
/// off screen with the 3-D renderer — no engine, no scene — one at a time,
/// and kept until the file changes.
///
/// Where there is no GPU (a test, the web) every picture is null and the
/// dock shows the file's icon.
final class ModelThumbnails {
  /// Thumbnails [size] pixels square of files under [root].
  ModelThumbnails({
    required this.root,
    this.size = 128,
    this.cacheFolder,
    GpuDevice? device,
  }) : _device = device;

  /// The project folder model paths are under.
  final String root;

  /// Where pictures are kept between sessions (PNG files named after the
  /// model and when it changed), or null to keep them in memory only.
  final String? cacheFolder;

  /// Width and height of each picture, in pixels.
  final int size;

  GpuDevice? _device;
  Future<Renderer3D?>? _renderer;
  Future<void> _queue = Future.value();
  final Map<String, Future<ui.Image?>> _pictures = {};
  final Map<String, ui.Image?> _done = {};

  /// When the model was, in the newest picture asked for, by path: a
  /// model that changed is pictured afresh and its older picture let go.
  final Map<String, DateTime?> _latest = {};
  bool _disposed = false;

  /// Bumped when a picture is ready; what a view listens to.
  final ValueNotifier<int> revision = ValueNotifier(0);

  static String _key(String path, DateTime? modified) =>
      '$path@${modified?.millisecondsSinceEpoch}';

  /// The picture of the model at [path] (an asset key) as it was at
  /// [modified], if it is ready; asking starts it.
  ui.Image? peek(String path, {DateTime? modified}) {
    final key = _key(path, modified);
    if (_done.containsKey(key)) return _done[key];
    of(path, modified: modified);
    return _done[_key(path, _latest[path])];
  }

  /// The picture of the model at [path] as it was at [modified]: null
  /// without a GPU, when the file can't be read as a model, or once
  /// [dispose]d. Asking for a newer one lets go of the one before; asking
  /// for an older one than that gets the newer.
  Future<ui.Image?> of(String path, {DateTime? modified}) {
    if (_disposed) return Future.value();
    if (_latest.containsKey(path)) {
      final newest = _latest[path];
      if (_older(modified, newest)) modified = newest;
    }
    final key = _key(path, modified);
    final known = _pictures[key];
    if (known != null) return known;
    if (_latest.containsKey(path)) _drop(_key(path, _latest[path]));
    _latest[path] = modified;
    final done = Completer<ui.Image?>();
    final picture = _pictures[key] = done.future;
    // Still wanted: not forgotten, superseded or disposed meanwhile.
    bool wanted() => !_disposed && identical(_pictures[key], picture);
    // One at a time: each holds the GPU until its frame is back.
    _queue = _queue.then((_) async {
      ui.Image? image;
      try {
        if (wanted()) {
          final cached = _cacheFile(path, modified);
          image = cached != null && cached.existsSync()
              ? await _decode(await cached.readAsBytes())
              : null;
          if (image == null) {
            image = await _render(path);
            if (image != null && cached != null) await _store(cached, image);
          }
        }
      } on Object catch (error) {
        debugPrint('just_game_engine_editor: no thumbnail for "$path": $error');
      }
      if (!wanted()) {
        image?.dispose();
        done.complete(null);
        return;
      }
      _done[key] = image;
      done.complete(image);
      revision.value++;
    });
    return picture;
  }

  /// How many pictures are kept or being drawn: one per model at most.
  @visibleForTesting
  int get keptPictures => _pictures.length;

  /// The model at [path] changed or went: its picture is let go, and drawn
  /// again when next asked for.
  void forget(String path) {
    if (!_latest.containsKey(path)) return;
    _drop(_key(path, _latest.remove(path)));
  }

  // Whether [a] is before [b]; no time at all is before any.
  static bool _older(DateTime? a, DateTime? b) =>
      b != null && (a == null || a.isBefore(b));

  void _drop(String key) {
    _pictures.remove(key);
    _done.remove(key)?.dispose();
  }

  /// The renderer the pictures are made with (shadows off), shared with
  /// whatever else previews models; null without a GPU.
  Future<Renderer3D?> renderer() => _renderer ??= () async {
    final device = _device ??= createGpuDevice();
    if (device == null) return null;
    final renderer = await Renderer3D.create(device);
    renderer.shadows.enabled = false;
    return renderer;
  }();

  Future<ui.Image?> _render(String path) async {
    final gpu = await renderer();
    if (gpu == null) return null;
    final file = PackageAssetPaths.of(root).file(path);
    final folder = file.parent.path;
    final data = await loadModelData(
      await file.readAsBytes(),
      name: path,
      fetch: (uri) => File('$folder/$uri').readAsBytes(),
    );
    final model = await gpu.uploader.upload(data);
    final scene = Render3DScene()..addModel(model, Matrix4.identity());
    final view = frameModel(data, size);
    final surface = gpu.device.createSurface(size, size);
    if (!await gpu.render(scene, view, surface)) return null;
    return surface.image;
  }

  // The cached picture of [path] as of [modified], or null without a cache.
  File? _cacheFile(String path, DateTime? modified) {
    final folder = cacheFolder;
    if (folder == null || modified == null) return null;
    final safe = path.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('$folder/$safe@${modified.millisecondsSinceEpoch}-$size.png');
  }

  static Future<ui.Image?> _decode(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  static Future<void> _store(File file, ui.Image image) async {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return;
    await file.parent.create(recursive: true);
    // Older pictures of the same model are stale now.
    final name = file.uri.pathSegments.last;
    final stem = name.substring(0, name.lastIndexOf('@') + 1);
    for (final old in file.parent.listSync().whereType<File>()) {
      if (old.uri.pathSegments.last.startsWith(stem)) old.deleteSync();
    }
    await file.writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
  }

  /// A view of [data] from above and to the front-left, far enough back to
  /// see all of it, [size] pixels square.
  static Render3DView frameModel(ModelData data, int size) {
    final box = Aabb3();
    data.bounds.transformInto(gltfToEngine, box);
    if (box.isEmpty) {
      box.setValues(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5);
    }
    // Up is -Y: the eye is above (negative y) and in front (negative z).
    return frameBounds(box, size, size, toward: Vector3(-0.55, -0.5, -0.67));
  }

  /// A view of [box], [width] by [height], far enough back to see all of
  /// it: from [toward] (a direction from its middle to the eye), or — when
  /// that is null — turned [yaw] and tipped [pitch] (radians).
  static Render3DView frameBounds(
    Aabb3 box,
    int width,
    int height, {
    Vector3? toward,
    double yaw = -0.6,
    double pitch = -0.45,
  }) {
    final centre = Vector3.zero();
    box.centerInto(centre);
    final radius = math.max(0.05, box.min.distanceTo(box.max) / 2);
    const fov = math.pi / 4;
    final distance = radius / math.sin(fov / 2) * 1.05;
    final towardEye =
        toward ??
        Vector3(
          -math.cos(pitch) * math.sin(yaw),
          math.sin(pitch),
          -math.cos(pitch) * math.cos(yaw),
        );
    towardEye.normalize();
    final eye = centre + towardEye * distance;
    final view = Render3DView()
      ..width = width
      ..height = height;
    view.lookAt(eye, centre);
    view.projection.setPerspectiveYDown(
      fov,
      width / height,
      math.max(0.01, distance - radius * 2),
      distance + radius * 2,
    );
    return view;
  }

  /// Lets go of the pictures; one still being drawn is let go when it is
  /// done.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final image in _done.values) {
      image?.dispose();
    }
    _done.clear();
    _pictures.clear();
    _latest.clear();
    revision.dispose();
  }
}
