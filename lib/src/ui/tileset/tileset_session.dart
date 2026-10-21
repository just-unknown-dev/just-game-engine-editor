import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:ui' show Offset, Rect;

import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';

/// Reads a project-relative file as text.
typedef TilesetTextReader = Future<String> Function(String path);

/// Writes text to a project-relative file.
typedef TilesetTextWriter = Future<void> Function(String path, String text);

/// Loads a project-relative image. Whether the image it hands back is the
/// caller's to dispose is the loader's to say: see
/// [SpriteAssetLoader.callerDisposesImages], and the `disposesImages`
/// argument of the sessions and views that take one.
typedef TilesetImageLoader = Future<ui.Image> Function(String path);

/// One tileset being edited: its data, what is selected, and its own undo.
///
/// The tileset is a document of its own, not part of the scene, so its
/// undo is its own too: Ctrl+Z in the Tileset Editor takes back a
/// collision shape, not the last tile painted in the level. Maps see the
/// tileset as it was last saved; saving tells them to read it again.
class TilesetSession {
  /// A session over [data]. [disposesImages] says whether the images
  /// [loadImage] hands back are the session's to dispose — clones, as the
  /// bundle's loader gives — rather than ones a loader keeps and shares;
  /// by default, only when the session uses the bundle's loader itself.
  TilesetSession(
    TilesetData data, {
    this.path,
    required this.root,
    TilesetImageLoader? loadImage,
    TilesetTextWriter? writeText,
    MapCollisionKinds? collisionKinds,
    bool? disposesImages,
  }) : collisionKinds = collisionKinds ?? MapCollisionKinds.builtIn,
       _data = data,
       _ownsImages = disposesImages ?? loadImage == null,
       _loadImage = loadImage ?? BundleSpriteAssetLoader().loadImage,
       _writeText = writeText {
    _current = jsonEncode(data.toJson());
    _saved = _current;
    reloadImage();
  }

  /// Opens the `.tileset.json` at [path].
  static Future<TilesetSession> open(
    String path, {
    required String root,
    TilesetTextReader? readText,
    TilesetImageLoader? loadImage,
    TilesetTextWriter? writeText,
    MapCollisionKinds? collisionKinds,
    bool? disposesImages,
  }) async {
    if (BuiltInTilesets.isBuiltIn(path)) {
      throw StateError(
        'it is built into the engine: its tiles are drawn in code, and '
        'cannot be edited',
      );
    }
    final text = await (readText ?? _reader(root))(path);
    return TilesetSession(
      TilesetData.fromJson(jsonDecode(text) as Map<String, dynamic>),
      path: path,
      root: root,
      loadImage: loadImage,
      writeText: writeText,
      collisionKinds: collisionKinds,
      disposesImages: disposesImages,
    );
  }

  /// A new, unsaved tileset cutting [image] into tiles. Its size is read
  /// from the image unless [imageWidth] and [imageHeight] say it — what a
  /// form that has shown the image already knows.
  static Future<TilesetSession> create({
    required String image,
    required String name,
    required int tileWidth,
    required int tileHeight,
    int margin = 0,
    int spacing = 0,
    required String root,
    TilesetImageLoader? loadImage,
    TilesetTextWriter? writeText,
    MapCollisionKinds? collisionKinds,
    bool? disposesImages,
    int? imageWidth,
    int? imageHeight,
  }) async {
    final owns = disposesImages ?? loadImage == null;
    final load = loadImage ?? BundleSpriteAssetLoader().loadImage;
    var width = imageWidth, height = imageHeight;
    if (width == null || height == null) {
      // Read for its size only: the session loads its own to draw.
      final picture = await load(image);
      width = picture.width;
      height = picture.height;
      if (owns) picture.dispose();
    }
    final data = TilesetData.fromImage(
      name: name,
      image: image,
      imageWidth: width,
      imageHeight: height,
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      margin: margin,
      spacing: spacing,
    );
    final session = TilesetSession(
      data,
      root: root,
      loadImage: load,
      writeText: writeText,
      collisionKinds: collisionKinds,
      disposesImages: owns,
    );
    // New, so unsaved even though nothing has been done to it yet.
    session._saved = '';
    return session;
  }

  static TilesetTextReader _reader(String root) =>
      (path) => PackageAssetPaths.of(root).file(path).readAsString();

  /// The collision kinds its tiles can be given: the edited engine's.
  final MapCollisionKinds collisionKinds;

  /// Where it is saved, project-relative; null until it first is.
  String? path;

  /// The project folder paths are relative to.
  final String root;

  final TilesetImageLoader _loadImage;
  final TilesetTextWriter? _writeText;

  // Whether the images [_loadImage] hands back are this session's to
  // dispose.
  final bool _ownsImages;

  TilesetData _data;

  /// The tileset as it stands.
  TilesetData get data => _data;

  /// Bumped on every change, undo and redo — what the views rebuild on.
  final Signal<int> revision = Signal(0, debugLabel: 'tilesetRevision');

  /// The tileset's image, once loaded.
  final Signal<ui.Image?> image = Signal(null, debugLabel: 'tilesetImage');

  /// Why the image did not load, if it did not.
  String? imageError;

  /// The tiles selected, by id.
  final Signal<Set<int>> selection = Signal(const {}, debugLabel: 'tiles');

  /// A line for the author: what was done, or why not.
  final Signal<String?> message = Signal(null, debugLabel: 'tilesetMessage');

  // The tileset as saved, and as it stands, encoded: kept as edits are
  // made, so asking whether it is dirty — every build of the header — does
  // not encode the whole tileset again.
  late String _saved;
  late String _current;

  bool get isDirty => _current != _saved;

  /// The file's name, or what a tileset not yet saved is called.
  String get fileName => path == null
      ? 'New tileset'
      : path!.substring(path!.lastIndexOf('/') + 1);

  /// [fileName], with a dot while there is work not saved.
  String get title => isDirty ? '$fileName •' : fileName;

  void say(String text) => message.value = text;

  /// The lowest selected tile: the one a single-tile editor shows.
  int? get primary {
    final s = selection.value;
    if (s.isEmpty) return null;
    return s.reduce((a, b) => a < b ? a : b);
  }

  Future<void> reloadImage() async {
    final path = _data.image;
    if (path.isEmpty) return;
    try {
      final loaded = await _loadImage(path);
      if (_disposed) {
        if (_ownsImages) loaded.dispose();
        return;
      }
      _replaceImage(loaded);
      imageError = null;
    } catch (e) {
      if (_disposed) return;
      imageError = '$e';
      _replaceImage(null);
    }
    revision.value++;
  }

  // Shows [next] in place of the image there was, letting that one go when
  // it is the session's own.
  void _replaceImage(ui.Image? next) {
    final previous = image.value;
    image.value = next;
    if (_ownsImages && previous != null && !identical(previous, next)) {
      previous.dispose();
    }
  }

  bool _disposed = false;

  // ── Undo ─────────────────────────────────────────────────────────────────

  final List<_Step> _undo = [];
  final List<_Step> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Makes [change] to the tileset as one undo step. Steps with the same
  /// [mergeKey] one after another fold into one — the moves of one drag,
  /// keyed by its [newGesture].
  ///
  /// A change that leaves the tileset something that cannot be saved — a
  /// number that is not finite — or that throws is taken back whole, and
  /// said in [message].
  void apply(
    String label,
    void Function(TilesetData ts) change, {
    Object? mergeKey,
  }) {
    final before = _data.toJson();
    final String encoded;
    final Map<String, dynamic> after;
    try {
      change(_data);
      for (final id in _data.tiles.keys.toList()) {
        _data.prune(id);
      }
      _data.touch();
      after = _data.toJson();
      encoded = jsonEncode(after);
    } catch (e) {
      final revisionBefore = _data.revision;
      _data = TilesetData.fromJson(before)..revision = revisionBefore + 1;
      say('Not changed: $e');
      revision.value++;
      return;
    }
    if (encoded == _current) {
      revision.value++;
      return;
    }
    _current = encoded;
    final last = _undo.isEmpty ? null : _undo.last;
    if (mergeKey != null && last != null && last.mergeKey == mergeKey) {
      last.after = after;
    } else {
      _undo.add(_Step(label, before, after, mergeKey));
    }
    _redo.clear();
    revision.value++;
  }

  int _gesture = 0;

  /// A key no edit has merged under yet: one per drag or stroke, handed to
  /// [apply] as its `mergeKey` (with whatever else tells the drag apart), so
  /// the moves of one gesture are one undo step and two gestures are two.
  int newGesture() => ++_gesture;

  void undo() {
    if (_undo.isEmpty) return;
    final step = _undo.removeLast();
    _redo.add(step);
    _restore(step.before);
    say('Undid ${step.label.toLowerCase()}');
  }

  void redo() {
    if (_redo.isEmpty) return;
    final step = _redo.removeLast();
    _undo.add(step);
    _restore(step.after);
    say('Redid ${step.label.toLowerCase()}');
  }

  void _restore(Map<String, dynamic> json) {
    final revisionBefore = _data.revision;
    _data = TilesetData.fromJson(json)..revision = revisionBefore + 1;
    _current = jsonEncode(_data.toJson());
    selection.value = {
      for (final id in selection.value)
        if (_data.contains(id)) id,
    };
    revision.value++;
  }

  // ── Saving ───────────────────────────────────────────────────────────────

  /// Whether [key] can be saved to: inside the project, and not in pub's
  /// shared cache — a package's tileset there is every project's.
  bool canSaveTo(String key) =>
      _writeText != null ||
      (ProjectFiles.isContained(key) &&
          PackageAssetPaths.of(root).isWritable(key));

  Future<String>? _saving;

  /// Writes the tileset to [to], or where it was opened from. Returns the
  /// path written.
  ///
  /// The file is written whole or not at all, saves follow one another,
  /// and a path outside the project or in pub's shared cache is refused
  /// (a [StateError]).
  Future<String> save({String? to}) {
    final previous = _saving;
    final saving = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // That save said what went wrong; this one is its own.
        }
      }
      return _save(to);
    }();
    _saving = saving;
    return saving;
  }

  Future<String> _save(String? to) async {
    final target = to ?? path;
    if (target == null) throw StateError('No path to save to');
    if (!canSaveTo(target)) {
      throw StateError(
        '$target is outside the project or in pub\'s shared cache, which '
        'is read-only',
      );
    }
    final json = _data.toJson();
    final text = const JsonEncoder.withIndent('  ').convert(json);
    final write = _writeText;
    if (write != null) {
      await write(target, text);
    } else {
      await ProjectFiles.writeString(
        PackageAssetPaths.of(root).absolute(target),
        '$text\n',
      );
    }
    path = target;
    _saved = jsonEncode(json);
    revision.value++;
    say('Saved $target');
    return target;
  }

  // ── Edits on the selection ───────────────────────────────────────────────

  Iterable<int> get _selected => selection.value.where(_data.contains);

  void setClass(String className) => apply('Tile class', (ts) {
    for (final id in _selected) {
      ts.tileOrNew(id).className = className;
    }
  });

  /// Whether [value] is a number a tileset can hold; says so when not.
  bool _finite(double value, String what) {
    if (value.isFinite) return true;
    say('$what must be a number');
    return false;
  }

  void setProbability(double probability) {
    if (!_finite(probability, 'Probability')) return;
    apply('Tile probability', (ts) {
      for (final id in _selected) {
        ts.tileOrNew(id).probability = probability < 0 ? 0 : probability;
      }
    });
  }

  /// Gives every selected tile [shapes] (or no collision, when null) of
  /// [kind].
  void setCollision(List<TileShape>? shapes, {String? kind}) => apply(
    shapes == null ? 'Remove collision' : 'Tile collision',
    (ts) {
      for (final id in _selected) {
        final def = ts.tileOrNew(id);
        def.collision = shapes == null
            ? null
            : TileCollision(
                kind: kind ?? def.collision?.kind ?? MapCollisionKinds.solid.id,
                shapes: [...shapes],
              );
      }
    },
  );

  /// Changes the kind of every selected tile that collides.
  void setCollisionKind(String kind) => apply('Collision kind', (ts) {
    for (final id in _selected) {
      ts.tile(id)?.collision?.kind = kind;
    }
  });

  /// Replaces tile [id]'s shapes: an edit in the shape editor.
  void setShapes(int id, List<TileShape> shapes, {Object? mergeKey}) =>
      apply('Edit collision shape', (ts) {
        final def = ts.tileOrNew(id);
        if (shapes.isEmpty) {
          def.collision = null;
        } else {
          (def.collision ??= TileCollision()).shapes = [...shapes];
        }
      }, mergeKey: mergeKey);

  void setAnimation(int id, List<TileFrame> frames, {Object? mergeKey}) =>
      apply(
        frames.isEmpty ? 'Remove animation' : 'Tile animation',
        (ts) => ts.tileOrNew(id).animation = [...frames],
        mergeKey: mergeKey,
      );

  /// Animates the lowest selected tile through every selected tile, in
  /// order, [durationMs] each.
  void animateSelection({int durationMs = 120}) {
    final ids = _selected.toList()..sort();
    if (ids.length < 2) {
      say('Select the frames first: two tiles or more');
      return;
    }
    setAnimation(ids.first, [for (final id in ids) TileFrame(id, durationMs)]);
    selection.value = {ids.first};
    say('Tile ${ids.first} plays ${ids.length} frames');
  }

  void setProperty(String name, Object? value, TilePropertyType type) {
    if (value is double && !_finite(value, name)) return;
    apply('Tile property', (ts) {
      for (final id in _selected) {
        ts.tileOrNew(id).properties.set(name, value, type);
      }
    });
  }

  void removeProperty(String name) => apply('Remove tile property', (ts) {
    for (final id in _selected) {
      ts.tile(id)?.properties.remove(name);
    }
  });

  // ── The tileset itself ───────────────────────────────────────────────────

  void rename(String name) => apply('Rename tileset', (ts) => ts.name = name);

  void setTileOffset(double x, double y) {
    if (!_finite(x, 'The offset') || !_finite(y, 'The offset')) return;
    apply('Tile offset', (ts) {
      ts.tileOffsetX = x;
      ts.tileOffsetY = y;
    });
  }

  // ── Terrains ─────────────────────────────────────────────────────────────

  /// Palette colours new terrains take, in turn.
  static const List<int> terrainColors = [
    0xFF4CAF50,
    0xFF8D6E63,
    0xFF42A5F5,
    0xFFFFCA28,
    0xFFAB47BC,
    0xFFEF5350,
    0xFF26A69A,
    0xFFBDBDBD,
  ];

  /// Adds a terrain set with one terrain; returns its index.
  int addWangSet({String? name, WangType type = WangType.corner}) {
    var index = -1;
    apply('Add terrain set', (ts) {
      ts.wangSets.add(
        WangSetData(
          name: name ?? 'Terrains ${ts.wangSets.length + 1}',
          type: type,
          colors: [WangColorData(name: 'Terrain 1', color: terrainColors[0])],
        ),
      );
      index = ts.wangSets.length - 1;
    });
    return index;
  }

  void renameWangSet(int set, String name) =>
      apply('Rename terrain set', (ts) => ts.wangSets[set].name = name);

  /// Changes what [set] matches by. Slots the new type does not use are
  /// cleared, so a corner set turned edge set has no stray corners.
  void setWangType(int set, WangType type) => apply('Terrain set type', (ts) {
    final w = ts.wangSets[set]..type = type;
    final used = w.slots.toSet();
    for (final id in w.wangIds.values) {
      for (var i = 0; i < 8; i++) {
        if (!used.contains(i)) id[i] = 0;
      }
    }
    w.wangIds.removeWhere((_, id) => id.every((c) => c == 0));
  });

  /// Adds a terrain to [set]; returns its colour number (from 1).
  int addWangColor(int set) {
    var color = 0;
    apply('Add terrain', (ts) {
      final w = ts.wangSets[set];
      w.colors.add(
        WangColorData(
          name: 'Terrain ${w.colors.length + 1}',
          color: terrainColors[w.colors.length % terrainColors.length],
        ),
      );
      color = w.colors.length;
    });
    return color;
  }

  /// Removes terrain [color] (from 1): its corners and edges become none,
  /// and the terrains after it move down one.
  void removeWangColor(int set, int color) => apply('Remove terrain', (ts) {
    final w = ts.wangSets[set];
    if (color < 1 || color > w.colors.length) return;
    w.colors.removeAt(color - 1);
    for (final id in w.wangIds.values) {
      for (var i = 0; i < 8; i++) {
        if (id[i] == color) {
          id[i] = 0;
        } else if (id[i] > color) {
          id[i]--;
        }
      }
    }
    w.wangIds.removeWhere((_, id) => id.every((c) => c == 0));
  });

  /// Changes terrain [color] (from 1) of [set]. Each change is its own
  /// undo step: a name typed, then a colour picked, are two.
  void editWangColor(
    int set,
    int color, {
    String? name,
    int? argb,
    double? probability,
  }) {
    if (probability != null && !_finite(probability, 'Probability')) return;
    apply('Edit terrain', (ts) {
      final c = ts.wangSets[set].colors[color - 1];
      if (name != null) c.name = name;
      if (argb != null) c.color = argb;
      if (probability != null) {
        c.probability = probability < 0 ? 0 : probability;
      }
    });
  }

  /// Sets slot [slot] of [tile]'s Wang id in [set] to [color] (0 clears
  /// it). [mergeKey] folds a stroke across several tiles into one step.
  void setWangSlot(
    int set,
    int tile,
    int slot,
    int color, {
    Object? mergeKey,
  }) => apply(color == 0 ? 'Clear terrain' : 'Paint terrain', (ts) {
    final w = ts.wangSets[set];
    final id = w.wangIds.putIfAbsent(tile, () => List.filled(8, 0));
    id[slot] = color;
    if (id.every((c) => c == 0)) w.wangIds.remove(tile);
  }, mergeKey: mergeKey);

  /// Every slot of [set]'s type on [tiles] to [color]: a tile that is all
  /// one terrain.
  void fillWangIds(int set, Iterable<int> tiles, int color) =>
      apply(color == 0 ? 'Clear terrain' : 'Paint terrain', (ts) {
        final w = ts.wangSets[set];
        for (final tile in tiles) {
          final id = w.wangIds.putIfAbsent(tile, () => List.filled(8, 0));
          for (final slot in w.slots) {
            id[slot] = color;
          }
          if (id.every((c) => c == 0)) w.wangIds.remove(tile);
        }
      });

  /// Lays [template] over the tiles from [firstTile]: every id in one step.
  void applyTemplate(int set, WangTemplate template, int firstTile) {
    var assigned = 0;
    apply('Terrain template', (ts) {
      assigned = template.applyTo(
        ts.wangSets[set],
        firstTile: firstTile,
        tilesetColumns: ts.columns,
        tileCountLimit: ts.tileCount,
      );
    });
    say('${template.name}: gave $assigned tiles their terrain');
  }

  /// How much of [set] is drawn: the tiles that have a Wang id, and — for
  /// corner and edge sets — how many of the possible combinations of its
  /// terrains they cover.
  ({int tiles, int combinations, int? possible}) coverage(int set) {
    final w = _data.wangSets[set];
    final seen = <String>{
      for (final id in w.wangIds.values)
        [for (final slot in w.slots) id[slot]].join(','),
    };
    final n = w.colors.length;
    int? possible;
    if (w.type != WangType.mixed && n > 0) {
      possible = 1;
      for (var i = 0; i < 4; i++) {
        possible = possible! * n;
      }
    }
    return (
      tiles: w.wangIds.length,
      combinations: seen.length,
      possible: possible,
    );
  }

  /// Whether the image on disk is no longer the size the tileset was cut
  /// from — its tiles would be numbered differently now.
  bool get imageResized {
    final img = image.value;
    return img != null &&
        (img.width != _data.imageWidth || img.height != _data.imageHeight);
  }

  void dispose() {
    _disposed = true;
    final shown = image.value;
    if (_ownsImages && shown != null) shown.dispose();
    for (final s in <Signal<Object?>>[revision, image, selection, message]) {
      s.dispose();
    }
  }
}

class _Step {
  _Step(this.label, this.before, this.after, this.mergeKey);

  final String label;
  final Map<String, dynamic> before;
  Map<String, dynamic> after;
  final Object? mergeKey;
}

/// Ready-made collision shapes for a tile, in its own pixels.
enum TileCollisionPreset {
  none('None'),
  full('Full'),
  topHalf('Top half'),
  bottomHalf('Bottom half'),
  slopeUp('45° up'),
  slopeDown('45° down'),
  gentleUpLow('22° up, low'),
  gentleUpHigh('22° up, high'),
  gentleDownHigh('22° down, high'),
  gentleDownLow('22° down, low');

  const TileCollisionPreset(this.label);

  final String label;

  /// The shapes for a [w] × [h] tile; null for none.
  List<TileShape>? shapesFor(num w, num h) {
    final x = w.toDouble();
    final y = h.toDouble();
    List<TileShape> poly(List<Offset> p) => [TilePolygonShape(p)];
    return switch (this) {
      none => null,
      full => [TileRectShape(Rect.fromLTWH(0, 0, x, y))],
      topHalf => [TileRectShape(Rect.fromLTWH(0, 0, x, y / 2))],
      bottomHalf => [TileRectShape(Rect.fromLTWH(0, y / 2, x, y / 2))],
      // Rising to the right: the floor climbs as you walk right.
      slopeUp => poly([Offset(0, y), Offset(x, 0), Offset(x, y)]),
      slopeDown => poly([Offset(0, 0), Offset(x, y), Offset(0, y)]),
      // A gentle slope is two tiles long: the low tile, then the high one.
      gentleUpLow => poly([Offset(0, y), Offset(x, y / 2), Offset(x, y)]),
      gentleUpHigh => poly([
        Offset(0, y / 2),
        Offset(x, 0),
        Offset(x, y),
        Offset(0, y),
      ]),
      gentleDownHigh => poly([
        Offset(0, 0),
        Offset(x, y / 2),
        Offset(x, y),
        Offset(0, y),
      ]),
      gentleDownLow => poly([Offset(0, y / 2), Offset(x, y), Offset(0, y)]),
    };
  }

  /// The preset [collision] matches on a [w] × [h] tile, if any.
  static TileCollisionPreset? of(TileCollision? collision, num w, num h) {
    for (final p in values) {
      final shapes = p.shapesFor(w, h);
      if (shapes == null) {
        if (collision == null || collision.shapes.isEmpty) return p;
        continue;
      }
      if (collision == null || collision.shapes.length != shapes.length) {
        continue;
      }
      var same = true;
      for (var i = 0; i < shapes.length; i++) {
        if (collision.shapes[i] != shapes[i]) same = false;
      }
      if (same) return p;
    }
    return null;
  }
}
