import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'asset_load_counter.dart';
import 'package:just_editor_core/host.dart';

/// Reads sprites from the project's files instead of the asset bundle.
///
/// The bundle is a snapshot from when the app was built: a sheet a tool saved
/// a moment ago is not in it, and one that was re-saved is there in its old
/// form. While the editor runs, the engine's sprite systems load through this
/// — paths resolve against the project root — and fall back to the bundle for
/// anything that is not a file there (a package's own assets).
///
/// Each image is decoded once and kept; every caller gets a clone of it, its
/// own to dispose ([callerDisposesImages]). What is kept is let go — and the
/// loader's own image disposed — when it is [evict]ed or [clear]ed, and when
/// two scenes in a row have opened without asking for it ([loads] restarts
/// as each scene opens): a long session over many levels keeps the sheets
/// of the last two, not of every one.
class FileSpriteAssetLoader extends SpriteAssetLoader {
  /// Reads from [root] (the working directory by default). What is not a
  /// file there comes from [context] — its sprite loader as it is now, so
  /// the context can then be pointed at this one, and its bundle — or from
  /// [fallback] and the app's bundle.
  FileSpriteAssetLoader({
    String? root,
    EngineContext? context,
    SpriteAssetLoader? fallback,
  }) : root = (root ?? Directory.current.path).replaceAll(r'\', '/'),
       _fallback = fallback ?? context?.sprites ?? BundleSpriteAssetLoader(),
       _bundle = context?.bundle ?? rootBundle,
       _trackKinds = context?.trackKinds,
       _migrations = context?.migrations;

  /// The project root asset paths are relative to.
  final String root;
  final SpriteAssetLoader _fallback;
  final AssetBundle _bundle;

  /// The track kinds timelines are read with: the context's, else the
  /// engine's own.
  final TimelineTrackKinds? _trackKinds;

  /// The packages' rules older timelines are migrated with.
  final MigrationHooks? _migrations;

  /// Each image decoded, by path: the loader's own, cloned for callers.
  final Map<String, Future<ui.Image>> _images = {};

  /// Of [_images], those the fallback lent rather than gave (a loader that
  /// keeps and shares its images): never disposed here.
  final Set<String> _lent = {};

  final Map<String, Future<SpriteAtlas>> _atlases = {};

  /// The images and atlases asked for since the scene now open began to
  /// load, and in the scene before it: what a new scene's [loads] restart
  /// keeps.
  Set<String> _asked = {};
  Set<String> _askedBefore = {};

  /// Every read that goes to a file or the bundle, counted: how the scene
  /// loader knows when what a scene shows has arrived. What comes from the
  /// cache is not counted. Restarted as a scene opens, which lets go of
  /// what the two scenes before it did not ask for.
  late final AssetLoadCounter loads = AssetLoadCounter(onRestart: _newScene);

  /// True: [loadImage] hands out a clone of the image it keeps, the
  /// caller's own to dispose; the loader disposes its own when it lets go.
  @override
  bool get callerDisposesImages => true;

  /// The paths of the images kept.
  @visibleForTesting
  Iterable<String> get keptImages => _images.keys;

  /// The image kept for [path] — the loader's own, not a clone.
  @visibleForTesting
  Future<ui.Image>? keptImageOf(String path) => _images[path];

  /// The project file for [path] — a package's own folder for
  /// `packages/<name>/…`, wherever the package is installed.
  File _file(String path) => PackageAssetPaths.of(root).file(path);

  /// Loads once per path. A failure is not remembered: the file may appear.
  Future<T> _once<T>(
    Map<String, Future<T>> cache,
    String path,
    Future<T> Function(String path) read,
  ) {
    final cached = cache[path];
    if (cached != null) return cached;
    final loading = loads.track(read(path));
    cache[path] = loading;
    loading.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(cache[path], loading)) cache.remove(path);
      },
    );
    return loading;
  }

  @override
  Future<ui.Image> loadImage(String path) async {
    _asked.add(path);
    final kept = _once(_images, path, _readImage);
    final image = await kept;
    try {
      return image.clone();
    } on StateError {
      // Let go while it was on its way: read it again.
      if (identical(_images[path], kept)) _images.remove(path);
      return (await _once(_images, path, _readImage)).clone();
    }
  }

  Future<ui.Image> _readImage(String path) async {
    final file = _file(path);
    if (!await file.exists()) {
      final image = await _fallback.loadImage(path);
      if (!_fallback.callerDisposesImages) _lent.add(path);
      return image;
    }
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    try {
      _lent.remove(path);
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  @override
  Future<SpriteAtlas> loadAtlas(String path) {
    _asked.add(path);
    return _once(_atlases, path, _readAtlas);
  }

  Future<SpriteAtlas> _readAtlas(String path) async {
    final file = _file(path);
    if (!await file.exists()) return _fallback.loadAtlas(path);
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final slash = path.lastIndexOf('/');
    return SpriteAtlas.fromJson(
      json,
      basePath: slash < 0 ? '' : path.substring(0, slash + 1),
      jsonPath: path,
      loadImage: loadImage,
    );
  }

  /// An animator graph, from the project's files; never cached here — the
  /// animator system keeps what it loads until told to reload.
  Future<AnimatorGraph> loadGraph(String path) => loads.track(_readGraph(path));

  Future<AnimatorGraph> _readGraph(String path) async {
    final file = _file(path);
    if (!await file.exists()) {
      return AnimatorGraph.parse(await _bundle.loadString(path));
    }
    return AnimatorGraph.parse(await file.readAsString());
  }

  /// A timeline, from the project's files; the timeline system keeps what
  /// it loads until told to reload.
  Future<TimelineAsset> loadTimeline(String path) =>
      loads.track(_readTimeline(path));

  Future<TimelineAsset> _readTimeline(String path) async {
    final file = _file(path);
    if (!await file.exists()) {
      return TimelineAsset.parse(
        await _bundle.loadString(path),
        kinds: _trackKinds,
        migrations: _migrations,
      );
    }
    return TimelineAsset.parse(
      await file.readAsString(),
      kinds: _trackKinds,
      migrations: _migrations,
    );
  }

  /// A prefab file, from the project's files (the bundle when it is not
  /// one of them); the prefab library keeps what it reads until told to
  /// read it again.
  Future<PrefabFile> loadPrefab(String path) => loads.track(_readPrefab(path));

  Future<PrefabFile> _readPrefab(String path) async {
    final file = _file(path);
    if (!await file.exists()) {
      return PrefabFile.parse(await _bundle.loadString(path, cache: false));
    }
    return PrefabFile.parse(await file.readAsString());
  }

  /// A text file — a tileset, a tile map, a Tiled map — from the project's
  /// files, or the bundle when it is not one of them. What `TileAssets`
  /// reads through while the editor runs.
  Future<String> readText(String path) => loads.track(_readText(path));

  Future<String> _readText(String path) async {
    final file = _file(path);
    if (!await file.exists()) return _bundle.loadString(path, cache: false);
    return file.readAsString();
  }

  /// Forgets [path] — and, for an atlas, the sheet beside it, which was
  /// re-exported with it. Its image is disposed: callers hold clones.
  @override
  void evict(String path) {
    _atlases.remove(path);
    _letGo(path);
    final dot = path.lastIndexOf('.');
    if (dot > 0) _letGo('${path.substring(0, dot)}.png');
  }

  /// Forgets everything, disposing the images kept.
  void clear() {
    _atlases.clear();
    _images.keys.toList().forEach(_letGo);
  }

  // A scene is opening: what neither the scene just left nor the one
  // before it asked for goes. An atlas is dropped, not disposed — its
  // pages hold clones of their own, let go with it.
  void _newScene() {
    final keep = {..._asked, ..._askedBefore};
    _atlases.removeWhere((path, _) => !keep.contains(path));
    _images.keys.where((path) => !keep.contains(path)).toList().forEach(_letGo);
    _askedBefore = _asked;
    _asked = {};
  }

  // Forgets the image at [path], disposing it once it has arrived unless
  // the fallback only lent it.
  void _letGo(String path) {
    final image = _images.remove(path);
    final lent = _lent.remove(path);
    if (image == null || lent) return;
    image.then<void>((i) => i.dispose(), onError: (Object _) {});
  }
}
