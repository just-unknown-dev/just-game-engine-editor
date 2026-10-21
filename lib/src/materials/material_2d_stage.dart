import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart' show PackageAssetPaths;
import 'package:just_game_engine/just_game_engine.dart';

import 'material_2d_samples.dart';
import 'material_2d_users.dart';

/// What a sprite material is previewed on.
enum Material2DSubject {
  /// What fits the material: the game's own sprite or shape drawn with it
  /// ([Material2DUsers]), else a sample picked by its effects
  /// ([Material2DAuto]).
  auto('Auto'),

  /// A textured disc: a clear round edge and a few flat colours.
  sample('Sample'),

  /// The sprite selected in the scene.
  selected('Selected'),

  /// A row of tiles, as a Level Map layer draws them.
  tiles('Tiles');

  const Material2DSubject(this.label);

  /// Its name in the editor.
  final String label;
}

/// What [Material2DSubject.auto] shows a material on.
enum Material2DAuto {
  /// Something of the game's drawn with it.
  user,

  /// A patch of plain stone tiles the size of its normal map.
  stone,

  /// A patch of tiles, for what moves across them (a wave, scrolling).
  tiles,

  /// The sample sprite.
  sample;

  /// What [file] is shown on when nothing of the game's is drawn with it:
  /// tiles for a normal map, a wave or scrolling, else the sample sprite.
  static Material2DAuto of(Material2DFile file) {
    if (file.isOn('normalMap')) return stone;
    if (file.isOn('wave') || file.isOn('scroll')) return tiles;
    return sample;
  }

  /// Whether [file] is best seen lit: a normal map, or a glow, shows only
  /// under a light.
  static bool lit(Material2DFile file) =>
      file.isOn('normalMap') || file.isOn('emissive');
}

/// A small world of its own that a 2-D material is drawn in, through the
/// engine's own render system, lighting and screen passes — the way the
/// game will draw it: a sprite (or a row of tiles, or a whole scene for a
/// screen material) with the material, and a light that can be moved
/// over it.
///
/// Files are read from the project (or a package, for its asset keys): the
/// material, its parents and the images its effects name. [library] shows
/// unsaved edits ([Material2DLibrary.preview]); nothing of it reaches the
/// game's world.
final class Material2DStage {
  /// A stage reading the project at [root] — or, when [filesFrom] is given,
  /// reading its files and images through that stage's [library], so the
  /// two draw the same material from one copy of its images (a stage that
  /// draws the same subject without the material, to compare).
  Material2DStage({required this.root, Material2DStage? filesFrom})
    : _filesFrom = filesFrom {
    world.context.material2DText = (path) => _fileOf(path).readAsString();
    world.context.sprites = _reader = _ProjectImages(root, _failedImages);
    world.addSystem(_render);
  }

  /// The project folder.
  final String root;

  final Material2DStage? _filesFrom;
  late final _ProjectImages _reader;

  // The images that could not be read, by path: what is drawn without
  // them is as ready as it will be.
  final Set<String> _failedImages = {};

  File _fileOf(String path) => File(PackageAssetPaths.of(root).absolute(path));

  /// The stage's own world.
  final World world = World()..initialize();

  late final RenderSystem _render = RenderSystem(
    passes: const [],
    clock: () => time,
  );

  /// Lights the stage when [lit].
  late final Lighting2DPass lighting = Lighting2DPass(
    () => world,
    clock: () => time,
  );

  /// Draws a screen material over the stage.
  late final ScreenMaterialPass screen = ScreenMaterialPass(
    () => world,
    clock: () => time,
  );

  /// The library the stage reads its material through: the files, parents
  /// and images, and unsaved edits shown in place of a file. The stage's
  /// own, or [filesFrom]'s.
  Material2DLibrary get library => _filesFrom?.library ?? _own;

  // The library of the stage's own world: the shaders it draws through.
  Material2DLibrary get _own => Material2DLibrary.of(world.context);

  /// Seconds into the preview: what moves in a material (a wave, a
  /// shine) moves with it.
  double time = 0;

  /// What the stage is cleared to.
  Color background = const Color(0xFF2A2E35);

  String _path = '';
  Material2DKind _kind = Material2DKind.sprite;
  Material2DSubject _subject = Material2DSubject.sample;
  ui.Image? _image;
  Rect? _source;
  Material2DUser? _user;
  bool _mapLaidOut = false;
  Material2DAuto? _autoLaidOut;
  final Map<String, Future<ui.Image?>> _loaded = {};
  // What [loadImage] read, by path; and images read before a path was
  // forgotten, let go once what is laid out no longer draws them.
  final Map<String, ui.Image> _loadedImages = {};
  final List<ui.Image> _retired = [];
  // The plain stone Auto shows a normal map on: the map's size.
  ui.Image? _stone;
  // The engine's shaders asked after, and those that could not be loaded.
  final Set<String> _shadersAsked = {}, _shadersFailed = {};
  bool _lit = false;
  FilterQuality _quality = FilterQuality.medium;
  Size? _laidOut;
  final List<Entity> _entities = [];
  Entity? _light;
  final List<ui.Image> _frames = [], _oldFrames = [];

  // ── How it is viewed ────────────────────────────────────────────────

  /// How many logical pixels a pixel of what is shown is drawn: null fits
  /// it to the stage ([scale] then says what that came to).
  double? get zoom => _zoom;
  double? _zoom;
  set zoom(double? value) {
    if (value == _zoom) return;
    _zoom = value;
    _laidOut = null;
  }

  /// The scale it was last drawn at: [zoom], or what fitting it came to.
  double get scale => _scale;
  double _scale = 1;

  /// How far what is shown is moved from the stage's middle, in logical
  /// pixels.
  Offset get pan => _pan;
  Offset _pan = Offset.zero;
  set pan(Offset value) {
    if (value == _pan) return;
    _pan = value;
    _laidOut = null;
  }

  /// Whether a sprite or shape is repeated three by three, side by side:
  /// how a tiling material's seams show. (A patch of tiles always is.)
  bool get tiled => _tiled;
  bool _tiled = false;
  set tiled(bool value) {
    if (value == _tiled) return;
    _tiled = value;
    _laidOut = null;
  }

  /// Whether what is shown is drawn without the material: what it looks
  /// like as it is, to compare with.
  bool get plain => _plain;
  bool _plain = false;
  set plain(bool value) {
    if (value == _plain) return;
    _plain = value;
    _laidOut = null;
  }

  /// Whether the normals the light sees are drawn instead of the lit
  /// result — as a normal map draws them, flat (0.5, 0.5, 1). Lights the
  /// stage, as only the lighting has them.
  bool get showNormals => _showNormals;
  bool _showNormals = false;
  set showNormals(bool value) {
    if (value == _showNormals) return;
    _showNormals = value;
    lighting.showNormals = value;
    _laidOut = null;
  }

  // ── The light ───────────────────────────────────────────────────────

  /// The light's colour.
  Color get lightColour => _lightColour;
  Color _lightColour = const Color(0xFFFFFFFF);
  set lightColour(Color value) {
    _lightColour = value;
    _applyLight();
  }

  /// How high the light is over the stage, a share of its shorter side:
  /// low lights graze the bumps, high ones light them evenly.
  double get lightHeight => _lightHeight;
  double _lightHeight = 0.2;
  set lightHeight(double value) {
    _lightHeight = value;
    _applyLight();
  }

  /// How far the light reaches, a share of the stage's longer side.
  double get lightReach => _lightReach;
  double _lightReach = 0.75;
  set lightReach(double value) {
    _lightReach = value;
    _applyLight();
  }

  /// How bright the light is.
  double get lightStrength => _lightStrength;
  double _lightStrength = 1.4;
  set lightStrength(double value) {
    _lightStrength = value;
    _applyLight();
  }

  /// Where the light is on a stage of [size], in logical pixels.
  Offset lightPosition(Size size) =>
      Offset(_lightAt.dx * size.width, _lightAt.dy * size.height);

  void _applyLight() {
    final size = _laidOut;
    final light = _light?.getComponent<Light2D>();
    if (size == null || light == null) return;
    light
      ..colour = _lightColour
      ..intensity = _lightStrength
      ..radius = math.max(size.width, size.height) * _lightReach
      ..height = math.min(size.width, size.height) * _lightHeight;
  }

  /// Where the light is, as a fraction of the stage across and down.
  Offset get light => _lightAt;
  Offset _lightAt = const Offset(0.3, 0.3);
  set light(Offset fraction) {
    _lightAt = Offset(fraction.dx.clamp(0.0, 1.0), fraction.dy.clamp(0.0, 1.0));
    final size = _laidOut;
    final t = _light?.getComponent<TransformComponent>();
    if (size != null && t != null) {
      t.position = Vector3(
        _lightAt.dx * size.width,
        _lightAt.dy * size.height,
        0,
      );
    }
  }

  /// Whether a sprite material is lit: the scene's lighting on, with a
  /// light at [light] (over a dim ambient light). A screen material is
  /// never lit.
  bool get lit => _lit;

  /// Shows the material at [path] (of [kind]) on [subject] — [image] (and
  /// the part of it, [source]) for [Material2DSubject.selected], or for
  /// [Material2DSubject.auto] the image of [user]'s sprite (a shape [user]
  /// is drawn from what it saves), drawn at [quality] — [lit] or not.
  void show(
    String path, {
    required Material2DKind kind,
    Material2DSubject subject = Material2DSubject.sample,
    ui.Image? image,
    Rect? source,
    Material2DUser? user,
    FilterQuality quality = FilterQuality.medium,
    bool lit = false,
  }) {
    if (path == _path &&
        kind == _kind &&
        subject == _subject &&
        identical(image, _image) &&
        source == _source &&
        identical(user, _user) &&
        quality == _quality &&
        lit == _lit) {
      return;
    }
    _path = path;
    _kind = kind;
    _subject = subject;
    _image = image;
    _source = source;
    _user = user;
    _quality = quality;
    _lit = lit;
    _laidOut = null;
  }

  /// What [Material2DSubject.auto] is showing now; null for another
  /// subject, or a screen material.
  Material2DAuto? get autoShows {
    if (_subject != Material2DSubject.auto || _kind == Material2DKind.screen) {
      return null;
    }
    final user = _user;
    if (user != null && (user.shape != null || _image != null)) {
      return Material2DAuto.user;
    }
    final file = _path.isEmpty ? null : library.fileOf(_path);
    return file == null ? Material2DAuto.sample : Material2DAuto.of(file);
  }

  /// [path] changed on disk: [loadImage] reads it again. The image read
  /// before is let go once what is laid out no longer draws it — the next
  /// [show] of another image.
  void forgetImage(String path) {
    _loaded.remove(path);
    final old = _loadedImages.remove(path);
    if (old != null) _retired.add(old);
  }

  /// The project's image at [path], read once and kept while the stage is
  /// (until [forgetImage] or [releaseImages]); null when it can't be read.
  Future<ui.Image?> loadImage(String path) {
    late final Future<ui.Image?> loading;
    return loading = _loaded.putIfAbsent(path, () async {
      try {
        final image = await _reader.loadImage(path);
        // Forgotten or let go meanwhile: not this stage's any more.
        if (!identical(_loaded[path], loading)) {
          image.dispose();
          return null;
        }
        _loadedImages[path] = image;
        return image;
      } on Object {
        return null;
      }
    });
  }

  /// Whether what [show] asked for can be drawn yet: the file read, the
  /// shader loaded and its images read — or each found missing, or failing
  /// to load: drawn without them, it is as ready as it will be.
  bool get ready {
    if (_path.isEmpty) return true;
    final library = this.library;
    final file = library.fileOf(_path);
    if (file == null) return library.errorOf(_path) != null;
    // The shaders are the stage's own world's: what it draws through.
    final own = _own;
    final screen = _kind == Material2DKind.screen;
    final program = screen ? own.screenProgram : own.program;
    if (_lit || _showNormals) {
      own.normalsProgram;
      if (own.lightingProgram == null &&
          !_shaderFailed(Material2DShader.lightingAsset)) {
        return false;
      }
    }
    if (program == null &&
        !_shaderFailed(
          screen ? Material2DShader.screenAsset : Material2DShader.asset,
        )) {
      return false;
    }
    return file.paths.every(
      (p) =>
          Material2DFile.isMaterial2DPath(p) ||
          library.imageOf(p) != null ||
          _imageFailed(p),
    );
  }

  // Whether the image at [path] could not be read for the library.
  bool _imageFailed(String path) =>
      (_filesFrom ?? this)._failedImages.contains(path);

  // Whether the engine's shader [asset] could not be loaded. The library
  // says so for none but one, so it is asked once here; a shader loaded
  // already is not loaded again (Flutter keeps it).
  bool _shaderFailed(String asset) {
    if (_shadersAsked.add(asset)) {
      unawaited(
        Material2DLibrary.loadProgram(
          asset,
        ).then<void>((_) {}, onError: (Object _) => _shadersFailed.add(asset)),
      );
    }
    return _shadersFailed.contains(asset);
  }

  /// Whether what is shown moves, so the preview should be drawn every
  /// frame: a wave, scrolling or a shine.
  bool get moving {
    if (_path.isEmpty) return false;
    final file = library.fileOf(_path);
    if (file == null) return false;
    return file.isOn('wave') || file.isOn('scroll') || file.isOn('shine');
  }

  void _layout(Size size) {
    for (final e in _entities) {
      if (e.isAlive) world.destroyEntity(e);
    }
    _entities.clear();
    _light = null;
    // Images forgotten since: drawn by nothing now, but the one still shown.
    _retired.removeWhere((image) {
      if (identical(image, _image)) return false;
      image.dispose();
      return true;
    });
    _laidOut = size;
    _autoLaidOut = autoShows;
    if (_path.isEmpty || size.isEmpty) return;
    final w = size.width, h = size.height;
    final middle = Offset(w / 2, h / 2);

    Entity sprite(
      ui.Image image,
      Offset at,
      Size drawn, {
      Rect? source,
      bool material = true,
      int z = 0,
      FilterQuality quality = FilterQuality.medium,
    }) {
      final e = world.createEntityWithComponents([
        TransformComponent(position: Vector3(at.dx, at.dy, 0)),
        RenderableComponent(
          renderable: Sprite(
            image: image,
            sourceRect: source,
            renderSize: drawn,
          )..filterQuality = quality,
        ),
        LayerComponent(zOrder: z),
        if (material && !_plain) Material2D(material: _path),
      ]);
      _entities.add(e);
      return e;
    }

    Size fit(Size image, double share) {
      final scale =
          math.min(w, h) * share / math.max(image.width, image.height);
      return Size(image.width * scale, image.height * scale);
    }

    if (_kind == Material2DKind.screen) {
      // A little scene for the frame: sky, ground, the slime and coins.
      sprite(Material2DSamples.sky, middle, size, material: false, z: -2);
      final tile = math.max(24.0, h / 6);
      for (var x = tile / 2; x < w + tile; x += tile) {
        sprite(
          Material2DSamples.tile,
          Offset(x, h - tile / 2),
          Size.square(tile),
          material: false,
        );
      }
      final slime = Material2DSamples.slime;
      final body = fit(Size(slime.width * 1.0, slime.height * 1.0), 0.32);
      sprite(
        slime,
        Offset(w * 0.32, h - tile - body.height / 2),
        body,
        material: false,
        z: 1,
      );
      for (var i = 0; i < 3; i++) {
        sprite(
          Material2DSamples.coin,
          Offset(w * (0.55 + i * 0.12), h * 0.45),
          Size.square(math.max(16, h / 9)),
          material: false,
          z: 1,
        );
      }
      if (!_plain) {
        _entities.add(
          world.createEntityWithComponents([ScreenMaterial(material: _path)]),
        );
      }
      return;
    }

    _mapLaidOut = true;
    final subject = _subjectNow();
    if (subject != null) _place(subject, size, sprite);
    if (_lit || _showNormals) {
      _entities.add(
        world.createEntityWithComponents([
          Lighting2D(ambient: const Color(0xFF30303A)),
        ]),
      );
      _light = world.createEntityWithComponents([
        TransformComponent(
          position: Vector3(_lightAt.dx * w, _lightAt.dy * h, 0),
        ),
        Light2D(castsShadows: false),
      ]);
      _entities.add(_light!);
      _applyLight();
    }
  }

  /// What is shown, by [Material2DSubject] — and for Auto by what fits.
  _Subject? _subjectNow() {
    _Subject sample(ui.Image image, {int columns = 1, int rows = 1}) =>
        _Subject.sprite(
          image,
          Material2DSamples.sizeOf(image),
          columns: columns,
          rows: rows,
        );
    switch (_subject) {
      case Material2DSubject.auto:
        final user = _user;
        switch (autoShows) {
          case Material2DAuto.user when user?.shape != null:
            return _Subject.shape(user!.shape!);
          case Material2DAuto.user:
            final image = _image!;
            return _Subject.sprite(
              image,
              Size(image.width.toDouble(), image.height.toDouble()),
              quality: _quality,
            );
          case Material2DAuto.stone:
            // Stone tiles the size of the normal map, once it is read — or
            // known not to be, or none is named yet: then a 64 one.
            final file = library.fileOf(_path)!;
            final path = file.text('normalMap.map');
            final map = library.imageOf(path);
            _mapLaidOut = map != null || path.isEmpty || _imageFailed(path);
            return sample(
              _stoneOf(map?.width ?? 64, map?.height ?? 64),
              columns: 3,
              rows: 3,
            );
          case Material2DAuto.tiles:
            return sample(Material2DSamples.tile, columns: 3, rows: 3);
          case Material2DAuto.sample:
          case null:
            return sample(Material2DSamples.sprite);
        }
      case Material2DSubject.tiles:
        return sample(Material2DSamples.tile, columns: 5);
      case Material2DSubject.selected when _image != null:
        final image = _image!;
        final part =
            _source ??
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            );
        return _Subject.sprite(
          image,
          part.size,
          source: part,
          quality: _quality,
        );
      case Material2DSubject.sample:
      case Material2DSubject.selected:
        return sample(Material2DSamples.sprite);
    }
  }

  // The plain stone [width] × [height], drawn again only for another size.
  // The one before is let go: what drew it went with the last layout.
  ui.Image _stoneOf(int width, int height) {
    final stone = _stone;
    if (stone != null && stone.width == width && stone.height == height) {
      return stone;
    }
    stone?.dispose();
    return _stone = Material2DSamples.stone(width, height);
  }

  /// [subject] laid out on a stage of [size]: at [zoom] (or fitted), moved
  /// by [pan], three by three when [tiled].
  void _place(
    _Subject subject,
    Size size,
    Entity Function(
      ui.Image image,
      Offset at,
      Size drawn, {
      Rect? source,
      FilterQuality quality,
    })
    sprite,
  ) {
    final w = size.width, h = size.height;
    var columns = subject.columns, rows = subject.rows;
    if (_tiled && columns == 1 && rows == 1) columns = rows = 3;
    final grid = columns * rows > 1;

    // A shape's size is its bounds once read.
    List<Component>? decode() {
      final components = <Component>[];
      for (final saved in subject.shape!) {
        try {
          final c = world.context.definitions.decode(saved);
          if (c != null) components.add(c);
        } on Object {
          // Left out: what can't be read is not drawn.
        }
      }
      final drawn = components.whereType<RenderableComponent>().firstOrNull;
      return drawn == null ? null : components;
    }

    Rect? bounds;
    if (subject.shape != null) {
      final first = decode();
      bounds = first
          ?.whereType<RenderableComponent>()
          .first
          .renderable
          .getBounds();
      if (bounds == null || bounds.isEmpty) return;
    }
    final unit = bounds?.size ?? subject.unit;
    final share = grid ? 0.8 : 0.6;
    final fit = math.min(
      w * share / (unit.width * columns),
      h * share / (unit.height * rows),
    );
    final scale = _scale = _zoom ?? fit;
    final centre = Offset(w / 2, h / 2) + _pan;
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < columns; i++) {
        final at =
            centre +
            Offset(
              (i - (columns - 1) / 2) * unit.width * scale,
              (j - (rows - 1) / 2) * unit.height * scale,
            );
        final image = subject.image;
        if (image != null) {
          sprite(
            image,
            at,
            unit * scale,
            source: subject.source,
            quality: subject.quality,
          );
          continue;
        }
        final components = decode();
        if (components == null) continue;
        final b = bounds!;
        final origin = at - b.center * scale;
        _entities.add(
          world.createEntityWithComponents([
            TransformComponent(
              position: Vector3(origin.dx, origin.dy, 0),
              scale: Vector3(scale, scale, 1),
            ),
            ...components,
            if (!_plain) Material2D(material: _path),
          ]),
        );
      }
    }
  }

  /// Draws the stage [size] logical pixels big on [canvas], [pixelRatio]
  /// device pixels to one.
  void paint(Canvas canvas, Size size, {double pixelRatio = 1}) {
    // Laid out again once the material is read (what Auto shows it on
    // depends on it), and the normal map it sizes its tiles by.
    final auto = autoShows;
    if (auto != _autoLaidOut ||
        (!_mapLaidOut && auto == Material2DAuto.stone)) {
      _laidOut = null;
    }
    if (_laidOut != size) _layout(size);
    for (final f in _oldFrames) {
      f.dispose();
    }
    _oldFrames
      ..clear()
      ..addAll(_frames);
    _frames.clear();
    final background = Paint()..color = this.background;
    final passes = <ScreenPass>[
      if (lighting.active) lighting,
      if (screen.active) screen,
    ];
    if (passes.isEmpty) {
      canvas.drawRect(Offset.zero & size, background);
      world.render(canvas, size);
      return;
    }
    // As the engine draws a frame with screen passes (ScreenPassPlan): into
    // layers the passes that can filter one filter, and into an image for
    // those that draw from one.
    final plan = ScreenPassPlan.of(passes, size, pixelRatio);
    plan.begin(canvas, size);
    if (!plan.needsImage) {
      canvas.drawRect(Offset.zero & size, background);
      world.render(canvas, size);
      plan.end(canvas);
      return;
    }
    final width = (size.width * pixelRatio).ceil().clamp(1, 8192);
    final height = (size.height * pixelRatio).ceil().clamp(1, 8192);
    final recorder = ui.PictureRecorder();
    final first = Canvas(recorder)..scale(pixelRatio);
    first.drawRect(Offset.zero & size, background);
    world.render(first, size);
    final picture = recorder.endRecording();
    final frame = picture.toImageSync(width, height);
    picture.dispose();
    _frames.add(frame);
    plan.paintImages(canvas, frame, size, pixelRatio, keep: _frames.add);
    plan.end(canvas);
  }

  /// A picture of the stage [width] by [height], once it is [ready] (or
  /// after [wait], drawn as far as it is).
  Future<ui.Image> picture(
    int width,
    int height, {
    Duration wait = const Duration(seconds: 2),
  }) async {
    final until = DateTime.now().add(wait);
    while (!ready && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
    final drawn = recorder.endRecording();
    try {
      return await drawn.toImage(width, height);
    } finally {
      drawn.dispose();
    }
  }

  /// Lets go of every image read for the stage — the sprites [loadImage]
  /// read and the images its materials name (with the files themselves) —
  /// and of what was laid out with them: what is shown next reads them
  /// again. For a stage that draws one picture after another, which would
  /// otherwise keep the images of every one.
  void releaseImages() {
    for (final e in _entities) {
      if (e.isAlive) world.destroyEntity(e);
    }
    _entities.clear();
    _light = null;
    _laidOut = null;
    // Shown again only once [show] is told what.
    _path = '';
    _image = null;
    _user = null;
    _letGoOfImages();
    _own.clear();
  }

  void _letGoOfImages() {
    for (final image in [
      ..._frames,
      ..._oldFrames,
      ..._loadedImages.values,
      ..._retired,
      ?_stone,
    ]) {
      image.dispose();
    }
    _frames.clear();
    _oldFrames.clear();
    _loadedImages.clear();
    _retired.clear();
    _stone = null;
    _loaded.clear();
    _failedImages.clear();
  }

  /// Lets the stage go.
  void dispose() {
    lighting.dispose();
    screen.dispose();
    _letGoOfImages();
    // The images its materials name: the world's own dispose leaves its
    // library's to the garbage collector.
    _own.clear();
    world.dispose();
  }
}

/// The project's images (and packages', by their asset keys), for the
/// images a material's effects name (a normal map).
final class _ProjectImages extends SpriteAssetLoader {
  _ProjectImages(this.root, this.failed);

  final String root;

  /// The paths that could not be read; one read again leaves it.
  final Set<String> failed;

  @override
  Future<ui.Image> loadImage(String path) async {
    failed.remove(path);
    try {
      final codec = await ui.instantiateImageCodec(
        await File(PackageAssetPaths.of(root).absolute(path)).readAsBytes(),
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } on Object {
      failed.add(path);
      rethrow;
    }
  }

  @override
  Future<SpriteAtlas> loadAtlas(String path) =>
      throw UnsupportedError('A material names images, not atlases');
}

/// What the stage shows a material on: an image (or part of it) [unit]
/// logical pixels big at a scale of 1, or a [shape]'s saved components —
/// once, or [columns] × [rows] side by side.
final class _Subject {
  _Subject.sprite(
    ui.Image this.image,
    this.unit, {
    this.source,
    this.quality = FilterQuality.medium,
    this.columns = 1,
    this.rows = 1,
  }) : shape = null;

  _Subject.shape(List<Map<String, dynamic>> this.shape)
    : image = null,
      source = null,
      unit = Size.zero,
      quality = FilterQuality.medium,
      columns = 1,
      rows = 1;

  final ui.Image? image;
  final Rect? source;
  final Size unit;
  final FilterQuality quality;
  final List<Map<String, dynamic>>? shape;
  final int columns, rows;
}
