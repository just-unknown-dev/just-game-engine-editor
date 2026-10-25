import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/graphics_3d.dart';

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

  /// Bumped when a picture is ready; what a view listens to.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// The picture of the model at [path] (project-relative) as it was at
  /// [modified], if it is ready; asking starts it.
  ui.Image? peek(String path, {DateTime? modified}) {
    final key = '$path@${modified?.millisecondsSinceEpoch}';
    if (_done.containsKey(key)) return _done[key];
    of(path, modified: modified);
    return null;
  }

  /// The picture of the model at [path] as it was at [modified]: null
  /// without a GPU or when the file can't be read as a model.
  Future<ui.Image?> of(String path, {DateTime? modified}) {
    final key = '$path@${modified?.millisecondsSinceEpoch}';
    return _pictures.putIfAbsent(key, () {
      final done = Completer<ui.Image?>();
      // One at a time: each holds the GPU until its frame is back.
      _queue = _queue.then((_) async {
        ui.Image? image;
        try {
          final cached = _cacheFile(path, modified);
          image = cached != null && cached.existsSync()
              ? await _decode(await cached.readAsBytes())
              : null;
          if (image == null) {
            image = await _render(path);
            if (image != null && cached != null) await _store(cached, image);
          }
        } on Object catch (error) {
          debugPrint(
            'just_game_engine_editor: no thumbnail for "$path": $error',
          );
        }
        _done[key] = image;
        done.complete(image);
        revision.value++;
      });
      return done.future;
    });
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
    final file = File('$root/$path');
    final folder = file.parent.path;
    final data = await loadModelData(
      await file.readAsBytes(),
      name: path,
      fetch: (uri) => File('$folder/$uri').readAsBytes(),
    );
    final model = await gpu.uploader.upload(data);
    final scene = RenderScene()..addModel(model, Matrix4.identity());
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
  static RenderView frameModel(ModelData data, int size) {
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
  static RenderView frameBounds(
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
    final view = RenderView()
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

  /// Lets the pictures go.
  void dispose() {
    for (final image in _done.values) {
      image?.dispose();
    }
    _done.clear();
    _pictures.clear();
    revision.dispose();
  }
}
