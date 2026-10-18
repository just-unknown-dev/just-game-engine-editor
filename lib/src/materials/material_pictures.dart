import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:just_game_engine/graphics_3d.dart';

import 'material_preview.dart';

/// Pictures of material files, for the Assets dock and the material
/// workspace's preview: rendered off screen with the 3-D renderer — no
/// engine, no scene — one at a time.
///
/// A picture is kept until its file, or a map, layer or parent it uses,
/// changes ([forget]). Meshes, maps and the reflections of each lighting
/// are kept for every picture after, so dragging a slider redraws at once.
///
/// Where there is no GPU (a test, the web) every picture is null and the
/// dock shows the material's icon.
final class MaterialPictures {
  /// Pictures [size] pixels square of materials under [root].
  MaterialPictures({
    required this.root,
    this.size = 128,
    this.cacheFolder,
    GpuDevice? device,
  }) : _device = device;

  /// The project folder material paths are under.
  final String root;

  /// Where pictures are kept between sessions (PNG files named after the
  /// material and when it changed), or null to keep them in memory only.
  final String? cacheFolder;

  /// Width and height of each picture, in pixels.
  final int size;

  GpuDevice? _device;
  Future<Renderer3D?>? _renderer;
  Future<void> _queue = Future.value();
  final Map<String, Future<ui.Image?>> _pictures = {};
  final Map<String, ui.Image?> _done = {};
  // What each picture's material uses: a change to one makes it stale.
  final Map<String, Set<String>> _uses = {};
  final Map<(PreviewShape, bool), GpuPrimitive> _meshes = {};
  final Map<(String, bool), Future<GpuTexture?>> _textures = {};
  final Map<PreviewLighting, Future<GpuEnvironmentMap?>> _maps = {};
  final Map<String, MaterialFile> _files = {};
  bool _disposed = false;

  /// Bumped when a picture is ready or goes stale; what a view listens to.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// The picture of the material at [path] (project-relative) as it was
  /// at [modified], if it is ready; asking starts it.
  ui.Image? peek(String path, {DateTime? modified}) {
    final key = _key(path, modified);
    if (_done.containsKey(key)) return _done[key];
    of(path, modified: modified);
    return null;
  }

  static String _key(String path, DateTime? modified) =>
      '$path@${modified?.millisecondsSinceEpoch}';

  /// The picture of the material at [path] as it was at [modified]: null
  /// without a GPU or when the file can't be read as a material.
  Future<ui.Image?> of(String path, {DateTime? modified}) {
    final key = _key(path, modified);
    return _pictures.putIfAbsent(key, () {
      final done = Completer<ui.Image?>();
      // One at a time: each holds the GPU until its frame is back.
      _queue = _queue.then((_) async {
        ui.Image? image;
        try {
          // Without a GPU there is nothing to draw: the file isn't read.
          if (await renderer() != null) {
            final file = await _read(path);
            final resolved = await resolve(file);
            _uses[key] = {path, ...file.paths, ...resolved.paths};
            final cached = _cacheFile(path, modified);
            image = cached != null && cached.existsSync()
                ? await _decode(await cached.readAsBytes())
                : null;
            if (image == null) {
              image = await render(resolved);
              if (image != null && cached != null) {
                await _store(cached, image);
              }
            }
          }
        } on Object catch (error) {
          debugPrint('just_material_editor: no picture of "$path": $error');
        }
        if (_disposed) {
          image?.dispose();
          done.complete(null);
          return;
        }
        _done[key] = image;
        done.complete(image);
        revision.value++;
      });
      return done.future;
    });
  }

  /// [path] changed on disk: a material, or a map, layer or parent one
  /// uses. Pictures that show it are drawn again when next asked for.
  void forget(String path) {
    _files.remove(path);
    _textures.removeWhere((k, _) => k.$1 == path);
    final stale = [
      for (final MapEntry(:key, :value) in _uses.entries)
        if (value.contains(path)) key,
    ];
    if (stale.isEmpty) return;
    for (final key in stale) {
      _uses.remove(key);
      _pictures.remove(key);
      // Not disposed: a view may still be showing it until it rebuilds.
      _done.remove(key);
      final at = key.lastIndexOf('@');
      final ms = int.tryParse(key.substring(at + 1));
      final cached = ms == null
          ? null
          : _cacheFile(
              key.substring(0, at),
              DateTime.fromMillisecondsSinceEpoch(ms),
            );
      if (cached != null && cached.existsSync()) cached.deleteSync();
    }
    if (!_disposed) revision.value++;
  }

  /// The renderer the pictures are made with (shadows off); null without
  /// a GPU.
  Future<Renderer3D?> renderer() => _renderer ??= () async {
    final device = _device ??= createGpuDevice();
    if (device == null) return null;
    final renderer = await Renderer3D.create(device);
    renderer.shadows.enabled = false;
    return renderer;
  }();

  /// [file] with its parents laid under it, read from the project (a
  /// parent that can't be read is passed over: the defaults show).
  Future<MaterialFile> resolve(MaterialFile file) async {
    if (!file.isVariant) return file;
    final parents = <String, MaterialFile>{};
    var at = file.parent;
    while (at.isNotEmpty &&
        !parents.containsKey(at) &&
        parents.length < MaterialChain.maxDepth) {
      final MaterialFile parent;
      try {
        parent = await _read(at);
      } on Object {
        break;
      }
      parents[at] = parent;
      at = parent.parent;
    }
    const self = '\u0000';
    return MaterialChain.resolve3D(
      self,
      (p) => p == self ? file : parents[p],
    ).value;
  }

  Future<MaterialFile> _read(String path) async => _files[path] ??=
      MaterialFile.parse(await File('$root/$path').readAsString());

  /// A picture of [file] on [shape] in [lighting], [width] by [height]
  /// (the picture size by default), seen turned [yaw] and tipped [pitch]
  /// (radians) from [zoom] times as close as fits it; its parents, maps and
  /// layers read from the project. [scene] is the open scene's drawing, for
  /// [PreviewLighting.scene]. Drawn [into] a surface when given (resized to
  /// fit). Null without a GPU; throws what reading a map or layer throws.
  Future<ui.Image?> render(
    MaterialFile file, {
    int? width,
    int? height,
    double yaw = -0.6,
    double pitch = -0.45,
    double zoom = 1,
    PreviewShape shape = PreviewShape.ball,
    PreviewLighting lighting = PreviewLighting.studio,
    RenderScene? scene,
    GpuSurface? into,
  }) async {
    final gpu = await renderer();
    if (gpu == null) return null;
    final resolved = await resolve(file);
    final metres = resolved.uv == MaterialUv.metres;
    final mesh = _meshes[(shape, metres)] ??= gpu.uploader.uploadPrimitive(
      shape
          .mesh(metres ? const ShapeUv.metresAt(1, 1, 1) : ShapeUv.natural)
          .toPrimitive(),
    );
    final material = await _materialOf(gpu, resolved);
    final stage = RenderScene()
      ..instances.add(MeshInstance(mesh, material, Matrix4.identity()));
    lighting.apply(
      stage,
      map: lighting.gradient == null ? null : await _mapOf(gpu, lighting),
      from: scene,
    );
    final w = width ?? size, h = height ?? size;
    final view = framePreview(
      w,
      h,
      radius: shape.radius,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
    );
    final surface = into ?? gpu.device.createSurface(w, h);
    if (surface.width != w || surface.height != h) surface.resize(w, h);
    if (!await gpu.render(stage, view, surface)) return null;
    return surface.image;
  }

  // [file] (resolved) for the GPU, its maps read once and kept.
  Future<GpuMaterial> _materialOf(Renderer3D gpu, MaterialFile file) async {
    Future<(GpuTexture, GpuSampler)?> map(
      String path, {
      required bool srgb,
    }) async {
      if (path.isEmpty) return null;
      final texture = await _texture(gpu, path, srgb);
      return texture == null ? null : (texture, GpuSampler.linearRepeat);
    }

    final layered = file.kind == MaterialKind.layered;
    final layers = [
      if (layered)
        for (final l in file.layers.take(MaterialFile.maxLayers))
          await resolve(await _read(l)),
    ];
    final maps = layered
        ? [
            for (var i = 0; i < 4; i++)
              i < layers.length
                  ? await map(layers[i].colorMap, srgb: true)
                  : null,
          ]
        : [
            await map(file.colorMap, srgb: true),
            await map(file.metalRoughMap, srgb: false),
            await map(file.normalMap, srgb: false),
            await map(file.occlusionMap, srgb: false),
            await map(file.emissionMap, srgb: true),
          ];
    return gpu.uploader.material(
      MaterialLibrary.dataOf(file, layers: layers),
      maps: maps,
    );
  }

  Future<GpuTexture?> _texture(Renderer3D gpu, String path, bool srgb) {
    final key = (path, srgb);
    return _textures[key] ??= () async {
      try {
        final bytes = await File('$root/$path').readAsBytes();
        return await gpu.uploader.uploadImage(bytes, srgb: srgb);
      } on Object {
        // Read again next time: it may be there by then.
        _textures.remove(key);
        rethrow;
      }
    }();
  }

  Future<GpuEnvironmentMap?> _mapOf(Renderer3D gpu, PreviewLighting lighting) =>
      _maps[lighting] ??= () async {
        final (zenith, horizon, ground) = lighting.gradient!;
        final data = await EnvironmentMapData.fromGradient(
          zenith,
          horizon,
          ground,
        );
        return GpuEnvironmentMap.upload(gpu.device, data);
      }();

  /// How pictures look: bumped when the shape, light or framing they are
  /// drawn with changes, so the ones kept on disk are drawn again.
  static const int look = 1;

  // The cached picture of [path] as of [modified], or null without a cache.
  File? _cacheFile(String path, DateTime? modified) {
    final folder = cacheFolder;
    if (folder == null || modified == null) return null;
    final safe = path.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final ms = modified.millisecondsSinceEpoch;
    return File('$folder/$safe@$ms-$size-v$look.png');
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
    // Older pictures of the same material are stale now.
    final name = file.uri.pathSegments.last;
    final stem = name.substring(0, name.lastIndexOf('@') + 1);
    for (final old in file.parent.listSync().whereType<File>()) {
      if (old.uri.pathSegments.last.startsWith(stem)) old.deleteSync();
    }
    await file.writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
  }

  /// Lets the pictures go; one still being made is dropped when done.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final image in _done.values) {
      image?.dispose();
    }
    _done.clear();
    _pictures.clear();
    _uses.clear();
    revision.dispose();
  }
}
