import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:just_game_engine/just_game_engine.dart';

/// Reads sprites from the project's files instead of the asset bundle.
///
/// The bundle is a snapshot from when the app was built: a sheet a tool saved
/// a moment ago is not in it, and one that was re-saved is there in its old
/// form. While the editor runs, the engine's sprite systems load through this
/// — paths resolve against the project root — and fall back to the bundle for
/// anything that is not a file there (a package's own assets).
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

  final Map<String, Future<ui.Image>> _images = {};
  final Map<String, Future<SpriteAtlas>> _atlases = {};

  File _file(String path) => File('$root/${path.replaceAll(r'\', '/')}');

  /// Loads once per path. A failure is not remembered: the file may appear.
  Future<T> _once<T>(
    Map<String, Future<T>> cache,
    String path,
    Future<T> Function(String path) read,
  ) {
    final cached = cache[path];
    if (cached != null) return cached;
    final loading = read(path);
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
  Future<ui.Image> loadImage(String path) => _once(_images, path, _readImage);

  Future<ui.Image> _readImage(String path) async {
    final file = _file(path);
    if (!await file.exists()) return _fallback.loadImage(path);
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    return (await codec.getNextFrame()).image;
  }

  @override
  Future<SpriteAtlas> loadAtlas(String path) =>
      _once(_atlases, path, _readAtlas);

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
  Future<AnimatorGraph> loadGraph(String path) async {
    final file = _file(path);
    if (!await file.exists()) {
      return AnimatorGraph.parse(await _bundle.loadString(path));
    }
    return AnimatorGraph.parse(await file.readAsString());
  }

  /// A timeline, from the project's files; the timeline system keeps what
  /// it loads until told to reload.
  Future<TimelineAsset> loadTimeline(String path) async {
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

  /// A text file — a tileset, a tile map, a Tiled map — from the project's
  /// files, or the bundle when it is not one of them. What `TileAssets`
  /// reads through while the editor runs.
  Future<String> readText(String path) async {
    final file = _file(path);
    if (!await file.exists()) return _bundle.loadString(path, cache: false);
    return file.readAsString();
  }

  /// Forgets [path] — and, for an atlas, the sheet beside it, which was
  /// re-exported with it.
  @override
  void evict(String path) {
    _atlases.remove(path);
    _images.remove(path);
    final dot = path.lastIndexOf('.');
    if (dot > 0) _images.remove('${path.substring(0, dot)}.png');
  }

  /// Forgets everything.
  void clear() {
    _atlases.clear();
    _images.clear();
  }
}
