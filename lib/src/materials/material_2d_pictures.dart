import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart' show PackageAssetPaths;
import 'package:just_game_engine/just_game_engine.dart';

import 'material_2d_stage.dart';
import 'material_2d_users.dart';

/// Pictures of 2-D material files for the Assets dock: a sprite material
/// on what fits it ([Material2DSubject.auto]: the game's own sprite drawn
/// with it, else a sample for its effects; lit when it has a normal map or
/// glows), a screen material over the sample scene — drawn
/// through the engine's own shaders on a [Material2DStage] of their own,
/// one at a time, and kept until the file, or a parent or image it uses,
/// changes ([forget]).
///
/// Each picture reads what it is drawn from afresh — the files and the
/// images — and lets the images go once drawn: only the small pictures
/// are kept.
final class Material2DPictures {
  /// Pictures [size] pixels square of materials under [root].
  Material2DPictures({required this.root, this.size = 128});

  /// The project folder.
  final String root;

  /// Width and height of each picture, in pixels.
  final int size;

  late final Material2DStage _stage = Material2DStage(root: root);
  Future<void> _queue = Future.value();
  final Map<String, Future<ui.Image?>> _pictures = {};
  final Map<String, ui.Image?> _done = {};
  final Map<String, Set<String>> _uses = {};
  bool _disposed = false;

  /// Bumped when a picture is ready or goes stale; what a view listens to.
  final ValueNotifier<int> revision = ValueNotifier(0);

  static String _key(String path, DateTime? modified) =>
      '$path@${modified?.millisecondsSinceEpoch}';

  /// The picture of the material at [path] as it was at [modified], if it
  /// is ready; asking starts it.
  ui.Image? peek(String path, {DateTime? modified}) {
    final key = _key(path, modified);
    if (_done.containsKey(key)) return _done[key];
    of(path, modified: modified);
    return null;
  }

  /// The picture of the material at [path] as it was at [modified]: null
  /// when it can't be read.
  Future<ui.Image?> of(String path, {DateTime? modified}) {
    final key = _key(path, modified);
    return _pictures.putIfAbsent(key, () {
      final done = Completer<ui.Image?>();
      bool current() => !_disposed && identical(_pictures[key], done.future);
      // The material itself, until what else it uses is known.
      _uses[key] = {path};
      _queue = _queue.then((_) async {
        ui.Image? image;
        try {
          final file = Material2DFile.parse(await _fileOf(path).readAsString());
          final chain = MaterialChain.resolve2D(
            path,
            (p) => p == path ? file : _read(p),
          );
          final user = await Material2DUsers.find(root, path);
          final sprite = user?.spritePath;
          if (current()) {
            _uses[key] = {
              path,
              ...chain.chain,
              ...chain.value.paths,
              if (user != null) user.file,
              ?sprite,
            };
          }
          _stage.show(
            path,
            kind: chain.value.kind,
            subject: Material2DSubject.auto,
            image: sprite == null ? null : await _stage.loadImage(sprite),
            user: user,
            lit: Material2DAuto.lit(chain.value),
          );
          image = await _stage.picture(size, size);
        } on Object catch (error) {
          debugPrint('just_game_engine_editor: no picture of "$path": $error');
        } finally {
          // Drawn: its sprite, its images and its files are let go, so the
          // next picture reads them as they are then.
          if (!_disposed) _stage.releaseImages();
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

  File _fileOf(String path) => File(PackageAssetPaths.of(root).absolute(path));

  Material2DFile? _read(String path) {
    try {
      return Material2DFile.parse(_fileOf(path).readAsStringSync());
    } on Object {
      return null;
    }
  }

  /// [path] changed on disk: a material, or a parent or image one uses.
  /// Pictures that show it are drawn again when next asked for.
  void forget(String path) {
    if (_disposed) return;
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
    }
    revision.value++;
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
    _queue.whenComplete(_stage.dispose);
  }
}
