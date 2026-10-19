import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart'
    show PackageAssetPaths, ProjectFiles;
import 'package:just_game_engine/graphics_3d.dart';

import 'material_preview.dart';
import 'texture_cache.dart';

// A map's texture: its image, whether it is a colour (sRGB), and the most
// pixels across it was made smaller to (null: its own size).
typedef _MapKey = (String path, bool srgb, int? fit);

/// Pictures of material files, for the Assets dock and the material
/// workspace's preview: rendered off screen with the 3-D renderer — no
/// engine, no scene — one at a time.
///
/// A picture is kept until its file, or a map, layer or parent it uses,
/// changes ([forget]). Meshes, maps and the reflections of each lighting
/// are kept for every picture after, so dragging a slider redraws at once.
/// The dock's pictures draw their maps made small ([size] × 2 across at
/// most); the window's preview ([render]) draws them at their own size,
/// let go when it closes ([releaseFullSizeMaps]). What is kept of the maps
/// is held to [textureBudget].
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
  /// material and the files it is drawn from, as they were), or null to
  /// keep them in memory only.
  final String? cacheFolder;

  /// Width and height of each picture, in pixels.
  final int size;

  /// The most bytes the textures of the maps kept between drawings may
  /// hold: the least recently used are let go past it. The maps of the
  /// drawing being made are kept whatever they come to.
  static const int textureBudget = 256 * 1024 * 1024;

  /// How long a picture kept on disk is kept without being drawn again:
  /// older ones (of materials long gone, say) are let go as a session
  /// starts.
  static const Duration cacheKeptFor = Duration(days: 30);

  GpuDevice? _device;
  Future<Renderer3D?>? _renderer;
  Future<void> _queue = Future.value();
  final Map<String, Future<ui.Image?>> _pictures = {};
  final Map<String, ui.Image?> _done = {};
  // What each picture's material uses: a change to one makes it stale.
  final Map<String, Set<String>> _uses = {};
  final Map<(PreviewShape, bool), GpuPrimitive> _meshes = {};
  final TextureCache<_MapKey, GpuTexture> _textures = TextureCache(
    budget: textureBudget,
    sizeOf: _bytesOf,
  );
  final Map<PreviewLighting, Future<GpuEnvironmentMap?>> _maps = {};
  // Each material file read, with its stamp then (when it changed and how
  // big it is): read again once the stamp is another.
  final Map<String, (String, MaterialFile)> _files = {};
  // The names of the pictures kept on disk, listed once a session.
  Future<Set<String>>? _cacheNames;
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
      bool current() => !_disposed && identical(_pictures[key], done.future);
      // The material itself, until what else it uses is known.
      _uses[key] = {path};
      // One at a time: each holds the GPU until its frame is back.
      _queue = _queue.then((_) async {
        ui.Image? image;
        try {
          // Without a GPU there is nothing to draw: the file isn't read.
          if (await renderer() != null) {
            final file = await _read(path);
            final (resolved, uses) = await _resolveWithUses(path, file);
            if (current()) _uses[key] = uses;
            final cached = await _cacheFile(path, uses);
            if (cached != null) image = await _readCached(cached);
            if (image == null) {
              image = await _render(resolved, fit: size * 2);
              if (image != null && cached != null && current()) {
                try {
                  await _store(cached, image);
                } on Object catch (error) {
                  debugPrint(
                    'just_game_engine_editor: the picture of "$path" was not '
                    'kept: $error',
                  );
                }
              }
            }
          }
        } on Object catch (error) {
          debugPrint('just_game_engine_editor: no picture of "$path": $error');
        }
        // Let go meanwhile, or forgotten (something it uses changed): this
        // one is stale.
        if (!current()) {
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
    _textures.removeWhere((k) => k.$1 == path);
    final stale = [
      for (final MapEntry(:key, :value) in _uses.entries)
        if (value.contains(path)) key,
    ];
    if (stale.isEmpty) return;
    for (final key in stale) {
      _uses.remove(key);
      _pictures.remove(key);
      // A view showing it has its own handle on it (RawImage clones it).
      _done.remove(key)?.dispose();
      unawaited(_deleteCached(key.substring(0, key.lastIndexOf('@'))));
    }
    if (!_disposed) revision.value++;
  }

  /// The window that drew at full size closed: the textures of the maps it
  /// drew are let go (the dock's smaller ones are kept).
  void releaseFullSizeMaps() => _textures.removeWhere((k) => k.$3 == null);

  /// The maps kept as textures: each image, whether as a colour, and the
  /// most pixels across it was made smaller to (null: its own size).
  @visibleForTesting
  Iterable<(String, bool, int?)> get keptMaps => _textures.keys;

  /// How many bytes the textures of [keptMaps] hold.
  @visibleForTesting
  int get keptMapBytes => _textures.bytes;

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
  Future<MaterialFile> resolve(MaterialFile file) async =>
      (await _resolve(file)).$1;

  // [file] resolved, and the parents it was resolved over.
  Future<(MaterialFile, List<String>)> _resolve(MaterialFile file) async {
    if (!file.isVariant) return (file, const <String>[]);
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
    final resolved = MaterialChain.resolve3D(
      self,
      (p) => p == self ? file : parents[p],
    ).value;
    return (resolved, parents.keys.toList());
  }

  // [file] (at [path]) resolved, and everything its picture is drawn from:
  // it, its parents, its maps and layers, and each layer's own parents and
  // maps.
  Future<(MaterialFile, Set<String>)> _resolveWithUses(
    String path,
    MaterialFile file,
  ) async {
    final (resolved, parents) = await _resolve(file);
    final uses = {path, ...file.paths, ...parents, ...resolved.paths};
    if (resolved.kind == MaterialKind.layered) {
      for (final l in resolved.layers.take(MaterialFile.maxLayers)) {
        if (l.isEmpty) continue;
        try {
          final layer = await _read(l);
          final (own, theirs) = await _resolve(layer);
          uses
            ..addAll(layer.paths)
            ..addAll(theirs)
            ..addAll(own.paths);
        } on Object {
          // Drawing it says what can't be read.
        }
      }
    }
    return (resolved, uses..remove(''));
  }

  // The file at [path], a project path or a package's asset key.
  File _fileOf(String path) => File(PackageAssetPaths.of(root).absolute(path));

  Future<MaterialFile> _read(String path) async {
    final file = _fileOf(path);
    final stamp = await _stampOf(file.path);
    final known = _files[path];
    if (known != null && known.$1 == stamp) return known.$2;
    final read = MaterialFile.parse(await file.readAsString());
    _files[path] = (stamp, read);
    return read;
  }

  // When the file at [absolute] last changed and how big it is; `-` when
  // it is not there.
  static Future<String> _stampOf(String absolute) async {
    try {
      final stat = await FileStat.stat(absolute);
      if (stat.type == FileSystemEntityType.notFound) return '-';
      return '${stat.modified.microsecondsSinceEpoch}:${stat.size}';
    } on FileSystemException {
      return '-';
    }
  }

  /// A picture of [file] on [shape] in [lighting], [width] by [height]
  /// (the picture size by default), seen turned [yaw] and tipped [pitch]
  /// (radians) from [zoom] times as close as fits it; its parents, maps and
  /// layers read from the project, its maps at their own size. [scene] is
  /// the open scene's drawing, for [PreviewLighting.scene]. In front of
  /// [background] (sRGB) when given, else the light's own sky. Drawn
  /// [into] a surface when given (resized to fit). Null without a GPU;
  /// throws what reading a map or layer throws.
  ///
  /// The picture is the caller's: a new handle on the surface's last
  /// frame, to dispose once it is not shown — held, it keeps that frame's
  /// texture.
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
    int? background,
    GpuSurface? into,
  }) => _render(
    file,
    width: width,
    height: height,
    yaw: yaw,
    pitch: pitch,
    zoom: zoom,
    shape: shape,
    lighting: lighting,
    scene: scene,
    background: background,
    into: into,
  );

  // [render], its maps made at most [fit] pixels across when given.
  Future<ui.Image?> _render(
    MaterialFile file, {
    int? width,
    int? height,
    double yaw = -0.6,
    double pitch = -0.45,
    double zoom = 1,
    PreviewShape shape = PreviewShape.ball,
    PreviewLighting lighting = PreviewLighting.studio,
    RenderScene? scene,
    int? background,
    GpuSurface? into,
    int? fit,
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
    final material = await _materialOf(gpu, resolved, fit);
    final stage = RenderScene()
      ..instances.add(MeshInstance(mesh, material, Matrix4.identity()));
    lighting.apply(
      stage,
      map: lighting.gradient == null ? null : await _mapOf(gpu, lighting),
      from: scene,
    );
    if (background != null) {
      stage.environment
        ..sky = false
        ..skybox = false
        ..clearColor = GraphicsShapes.linear(ui.Color(background));
    }
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
  Future<GpuMaterial> _materialOf(
    Renderer3D gpu,
    MaterialFile file,
    int? fit,
  ) async {
    // This drawing's maps: none is let go to make room for another.
    final used = <_MapKey>{};
    Future<(GpuTexture, GpuSampler)?> map(
      String path, {
      required bool srgb,
    }) async {
      if (path.isEmpty) return null;
      final key = (path, srgb, fit);
      used.add(key);
      final texture = await _textures.get(
        key,
        () => _upload(gpu, path, srgb, fit),
        keep: used,
      );
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

  Future<GpuTexture?> _upload(
    Renderer3D gpu,
    String path,
    bool srgb,
    int? fit,
  ) async {
    var bytes = await _fileOf(path).readAsBytes();
    if (fit != null) bytes = await _shrunk(bytes, fit);
    return gpu.uploader.uploadImage(bytes, srgb: srgb);
  }

  // The image [bytes] as a PNG at most [most] pixels across; as they are
  // when it is no bigger.
  static Future<Uint8List> _shrunk(Uint8List bytes, int most) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      if (w <= most && h <= most) return bytes;
      codec = await descriptor.instantiateCodec(
        targetWidth: w >= h ? most : null,
        targetHeight: h > w ? most : null,
      );
      image = (await codec.getNextFrame()).image;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return bytes;
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  // The bytes a texture holds: four a pixel, a third more with its mips.
  static int _bytesOf(GpuTexture texture) {
    final desc = texture.desc;
    final top = desc.width * desc.height * 4;
    return desc.mipLevels > 1 ? top * 4 ~/ 3 : top;
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
  /// drawn with changes, or how pictures kept on disk are named, so the
  /// ones kept there are drawn again.
  static const int look = 2;

  // The picture of [path] kept on disk, drawn from [uses] as they are now;
  // null without a cache folder.
  Future<File?> _cacheFile(String path, Set<String> uses) async {
    final folder = cacheFolder;
    if (folder == null) return null;
    final stamps = [
      for (final p in uses.toList()..sort())
        '$p=${await _stampOf(PackageAssetPaths.of(root).absolute(p))}',
    ];
    return File(
      '$folder/${_stem(path)}@${_hash(stamps.join('|'))}-$size-v$look.png',
    );
  }

  // A kept picture's name up to its `@`: the material's file name, to read,
  // and a hash of its whole path, so that `a/b` and `a_b` are two.
  static String _stem(String path) {
    final name = path
        .substring(path.lastIndexOf('/') + 1)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${name}_${_hash(path)}';
  }

  // FNV-1a, 32 bits, as eight hex digits: the same in every session.
  static String _hash(String text) {
    var h = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  static String _nameOf(File file) {
    final path = file.path.replaceAll(r'\', '/');
    return path.substring(path.lastIndexOf('/') + 1);
  }

  // The names in the cache folder, listed once a session; what is stale
  // there is let go as it is listed: pictures drawn for another [look],
  // ones half written, and ones not drawn for [cacheKeptFor].
  Future<Set<String>> _names() => _cacheNames ??= () async {
    final names = <String>{};
    final folder = Directory(cacheFolder!);
    try {
      if (!await folder.exists()) return names;
      final oldest = DateTime.now().subtract(cacheKeptFor);
      final current = '-v$look.png';
      await for (final entity in folder.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = _nameOf(entity);
        var keep = name.endsWith(current);
        if (keep) {
          try {
            keep = (await entity.lastModified()).isAfter(oldest);
          } on FileSystemException {
            keep = false;
          }
        }
        if (keep) {
          names.add(name);
        } else {
          await _delete(entity);
        }
      }
    } on FileSystemException {
      // Unreadable: nothing is kept there this session.
    }
    return names;
  }();

  // The picture kept in [file], or null when there is none — or it can't
  // be read (cut short as the editor stopped): then it is let go, to be
  // drawn again.
  Future<ui.Image?> _readCached(File file) async {
    final names = await _names();
    final name = _nameOf(file);
    if (!names.contains(name)) return null;
    try {
      return await _decode(await file.readAsBytes());
    } on Object {
      names.remove(name);
      await _delete(file);
      return null;
    }
  }

  static Future<ui.Image?> _decode(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<void> _store(File file, ui.Image image) async {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return;
    final names = await _names();
    final name = _nameOf(file);
    // Older pictures of the same material are stale now.
    final stem = name.substring(0, name.lastIndexOf('@') + 1);
    for (final old in [
      for (final n in names)
        if (n != name && n.startsWith(stem)) n,
    ]) {
      names.remove(old);
      await _delete(File('${cacheFolder!}/$old'));
    }
    // Whole or not at all: a picture cut short is never read back.
    await ProjectFiles.writeBytes(
      file.path,
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
    names.add(name);
  }

  // The pictures of [path] kept on disk, let go.
  Future<void> _deleteCached(String path) async {
    final folder = cacheFolder;
    if (folder == null) return;
    final names = await _names();
    final stem = '${_stem(path)}@';
    for (final name in [
      for (final n in names)
        if (n.startsWith(stem)) n,
    ]) {
      names.remove(name);
      await _delete(File('$folder/$name'));
    }
  }

  static Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Gone already, or held: the next session lets it go.
    }
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
    _textures.clear();
    _meshes.clear();
    _maps.clear();
    _files.clear();
    revision.dispose();
  }
}
