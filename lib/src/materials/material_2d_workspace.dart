import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'map_pictures.dart';
import 'material_2d_fields.dart';
import 'material_2d_presets.dart';
import 'material_2d_samples.dart';
import 'normal_maps.dart';
import 'material_2d_stage.dart';
import 'material_2d_users.dart';
import 'material_window_kit.dart';

/// A 2-D material file's look (`*.material2d.json`), drawn live as the
/// game will draw it: the workspace a 2-D material opens in.
///
/// The material itself — its preset, kind and parent — is in a panel on
/// the left, as in the 3-D material window; its effects are in a panel on
/// the right, each that is on a card with its values, the rest added from
/// a menu grouped as Colour, Edges, Motion and Light (a screen material's:
/// the frame's — pixelate, an old screen, a colour grade, a vignette — and
/// its colour). Presets start one off. A value being dragged or a colour
/// being picked shows at once and becomes one undo step when let go.
///
/// The preview draws through the engine's own shaders on a world of its
/// own: a sprite material on what fits it (Auto: the game's own sprites and
/// shapes drawn with it, to pick from), a sample, the sprite selected in
/// the scene or a row of tiles — lit by a light whose handle is dragged
/// over it — and a screen material over a little scene. It zooms and pans,
/// repeats the subject three by three, compares it with and without the
/// material, shows the normals the light sees, and plays, pauses and
/// scrubs what moves. Each effect's card says what it does, and has a
/// reset, a solo, a fold and a × that takes the effect out.
///
/// A variant (a material with a parent) shows its parent's effects and
/// values where it has none of its own; whatever is changed becomes its
/// own. Its edits have an undo of their own; Save writes the file, and
/// everything drawn with it changes.
class Material2DWorkspace extends StatefulWidget {
  /// The workspace for the 2-D material at [path] under [root].
  const Material2DWorkspace({
    super.key,
    required this.path,
    required this.root,
    required this.workspace,
    this.maps,
    this.changes,
    this.loadOnStart = true,
  });

  /// The material, project-relative.
  final String path;

  /// The project folder.
  final String root;

  /// The pictures of the images its effects name; its own when null.
  final MapPictures? maps;

  /// Paths of files that changed on disk, as the editor hears of them.
  final Stream<String>? changes;

  /// The editor's handle on the workspace.
  final WorkspaceContext workspace;

  /// Whether it reads the file as it opens; a test calls
  /// [Material2DWorkspaceState.load] itself instead.
  final bool loadOnStart;

  @override
  State<Material2DWorkspace> createState() => Material2DWorkspaceState();
}

/// The state of a [Material2DWorkspace]; public for tests.
class Material2DWorkspaceState extends State<Material2DWorkspace>
    with SingleTickerProviderStateMixin {
  Material2DFile _saved = const Material2DFile();
  final List<Material2DFile> _history = [const Material2DFile()];
  int _at = 0;
  Object? _error;
  bool _loaded = false;

  /// The material as it will be saved: for a variant, its own effects and
  /// values.
  Material2DFile get material => _history[_at];

  /// Whether it differs from the file.
  bool get dirty => material != _saved;

  // A value being dragged or picked: drawn, not yet an undo step.
  Material2DFile? _live;

  /// What is drawn: a [preview], or [material].
  Material2DFile get drawn => _live ?? material;

  Material2DFile? _shownFor;
  Material2DFile _shown = const Material2DFile();
  List<String> _chainProblems = const [];
  final Map<String, Material2DFile?> _parents = {};

  /// What the fields show: what is [drawn], and for a variant its
  /// parents' effects and values where it has none of its own.
  Material2DFile get shown {
    final m = drawn;
    if (!identical(_shownFor, m)) {
      _shownFor = m;
      if (!m.isVariant) {
        _shown = m;
        _chainProblems = const [];
      } else {
        final resolved = MaterialChain.resolve2D(
          widget.path,
          (p) => p == widget.path ? m : _parent(p),
        );
        _shown = resolved.value;
        _chainProblems = resolved.problems;
      }
    }
    return _shown;
  }

  Material2DFile? _parent(String path) => _parents.putIfAbsent(path, () {
    try {
      return Material2DFile.parse(
        File('${widget.root}/$path').readAsStringSync(),
      );
    } on Object {
      return null;
    }
  });

  /// The preview's subject and background, kept for the next material.
  static Material2DSubject _lastSubject = Material2DSubject.auto;
  static bool _lastLight = false;

  /// What a sprite material is shown on.
  Material2DSubject get subject => _subject;
  Material2DSubject _subject = _lastSubject;

  /// What in the project is drawn with the material — what Auto shows it
  /// on — and its sprite's image; null when nothing is (or not found yet).
  Material2DUser? get user => _user;
  Material2DUser? _user;
  ui.Image? _userImage;

  /// Whether the preview is lit by a light that can be dragged over it.
  bool get lit => _lit;
  bool _lit = false;

  /// Whether the preview is drawn on a light background.
  bool get lightBackground => _lightBackground;
  bool _lightBackground = _lastLight;

  /// The material's panel's width (on the left), kept for the next
  /// material.
  static double _lastPanelWidth = 280;
  double get panelWidth => _panelWidth;
  double _panelWidth = _lastPanelWidth;

  /// The effects panel's width (on the right), kept for the next material.
  static double _lastEffectsWidth = 340;
  double get effectsWidth => _effectsWidth;
  double _effectsWidth = _lastEffectsWidth;

  // Each effect's card, to scroll to one just added.
  final Map<String, GlobalKey> _cardKeys = {};
  final ScrollController _effectsScroll = ScrollController();

  /// The same subject drawn without the material, to compare with.
  late final Material2DStage plainStage = Material2DStage(root: widget.root)
    ..plain = true;

  /// Where the compare line is, a share of the preview across: drawn
  /// without the material to its left, with it to its right. Null when not
  /// comparing.
  double? get compareAt => _compareAt;
  double? _compareAt;

  /// Whether Space is held: drawn without the material while it is.
  bool get holdingPlain => _holdingPlain;
  bool _holdingPlain = false;

  /// Whether the light's settings are open over the preview.
  bool get lightSettingsOpen => _lightSettingsOpen;
  bool _lightSettingsOpen = false;

  /// The effect drawn alone in the preview (the rest left out there, not
  /// in the file); null for all of them.
  String? get solo => _solo;
  String? _solo;

  /// Everything in the project drawn with the material: what Auto picks
  /// from.
  List<Material2DUser> get users => _users;
  List<Material2DUser> _users = const [];

  /// Whether what moves (a wave, scrolling, a shine) is playing.
  bool get playing => _playing;
  bool _playing = true;

  /// How fast it plays.
  double get speed => _speed;
  double _speed = 1;

  /// Seconds into the preview, from 0 to [loop].
  double get time => _clock.value;
  final ValueNotifier<double> _clock = ValueNotifier(0);
  Duration _lastTick = Duration.zero;

  // The scale the preview was last drawn at, once it is: what the zoom
  // label says (it is only known once laid out, as it is drawn).
  final ValueNotifier<double> _drawnScale = ValueNotifier(1);

  /// How long the preview plays before starting over, in seconds.
  static const double loop = 10;

  /// What zooming in and out steps through: whole numbers from 1 up, so
  /// pixel art stays crisp.
  static const List<double> zoomSteps = [0.25, 0.5, 1, 2, 3, 4, 6, 8, 12, 16];

  /// What modules adding to the window see of it ([WorkspaceIds.material2D]).
  Material2DWorkspaceView get view => _extensionView;
  late final _Material2DView _extensionView = _Material2DView(this);

  /// The world the preview draws in.
  late final Material2DStage stage = Material2DStage(root: widget.root);
  late final MapPictures _maps = widget.maps ?? MapPictures(root: widget.root);
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  StreamSubscription<String>? _changes;

  File get _file => File('${widget.root}/${widget.path}');

  @override
  void initState() {
    super.initState();
    widget.workspace.setCloseGuard?.call(
      () async => mayLeaveUnsaved(context, dirty: dirty, save: save),
    );
    _changes = widget.changes?.listen(_changed);
    widget.workspace.scope.sceneState.selectedEntity.addListener(_selected);
    _ticker.start();
    if (widget.loadOnStart) load();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final moving = stage.moving;
    if (_playing && moving) {
      _clock.value = (_clock.value + dt * _speed) % loop;
    }
    stage.time = plainStage.time = _clock.value;
    final comparing = _compareAt != null || _holdingPlain;
    if ((moving && _playing) ||
        !stage.ready ||
        (comparing && !plainStage.ready)) {
      _repaint.value++;
    }
  }

  void _selected() {
    if (_subject == Material2DSubject.selected && mounted) {
      setState(() {});
      _sync();
    }
  }

  void _changed(String path) {
    if (path == widget.path) return;
    final parent = _parents.containsKey(path);
    _parents.remove(path);
    if (parent) _shownFor = null;
    _maps.forget(path);
    stage.library.reload(path);
    if (mounted) setState(() {});
    _sync();
  }

  /// Reads the file and shows it.
  Future<void> load() async {
    try {
      final file = Material2DFile.parse(await _file.readAsString());
      if (!mounted) return;
      setState(() {
        _saved = file;
        _history
          ..clear()
          ..add(file);
        _at = 0;
        _loaded = true;
        _error = null;
        _lit = shown.isOn('normalMap') || shown.isOn('emissive');
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
    _sync();
    unawaited(_findUser());
  }

  // What Auto shows the material on: the game's own sprites and shapes
  // drawn with it — the first of them, until another is picked.
  Future<void> _findUser() async {
    final users = await Material2DUsers.findAll(widget.root, widget.path);
    if (!mounted) return;
    setState(() => _users = users);
    await pickUser(users.firstOrNull);
  }

  /// Shows the material on [user] (one of [users]) when Auto is chosen.
  Future<void> pickUser(Material2DUser? user) async {
    final image = switch (user?.spritePath) {
      final path? => await stage.loadImage(path),
      null => null,
    };
    if (!mounted) return;
    setState(() {
      _user = user;
      _userImage = image;
    });
    _sync();
  }

  /// Puts [next] in as the material, one undo step.
  void edit(Material2DFile next) {
    _live = null;
    if (next != material) {
      setState(() {
        _history
          ..removeRange(_at + 1, _history.length)
          ..add(next);
        _at = _history.length - 1;
      });
    } else {
      setState(() {});
    }
    _sync();
  }

  /// Changes the material as [change] says, as one undo step.
  void change(Material2DFile Function(Material2DFile m) change) =>
      edit(change(material));

  /// Shows [change] without making an undo step: a value being dragged or
  /// picked. [change] or [edit] puts it in for good; [endPreview] lets it
  /// go.
  void preview(Material2DFile Function(Material2DFile m) change) {
    setState(() => _live = change(material));
    _sync();
  }

  /// Stops showing a [preview].
  void endPreview() {
    if (_live == null) return;
    setState(() => _live = null);
    _sync();
  }

  /// Steps back through the edits.
  void undo() {
    if (_at == 0) return;
    setState(() {
      _live = null;
      _at--;
    });
    _sync();
  }

  /// Steps forward again.
  void redo() {
    if (_at >= _history.length - 1) return;
    setState(() {
      _live = null;
      _at++;
    });
    _sync();
  }

  /// Writes the file; whether it went through.
  Future<bool> save() async {
    final current = material;
    try {
      await _file.writeAsString(current.encode());
      if (mounted) setState(() => _saved = current);
      _syncScene();
      widget.workspace.reloadAssets?.call(widget.path);
      return true;
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
      return false;
    }
  }

  /// In a variant: every effect and value taken from the parent again, as
  /// one undo step.
  void revertAll() =>
      edit(Material2DFile(kind: material.kind, parent: material.parent));

  /// In a variant: its own effects and values written into its parent's
  /// file — so the parent, and everything made from it, has them — and then
  /// taken from the parent here (one undo step; the parent's file is not
  /// undone with it). Asks first unless [confirm] is false. Whether it went
  /// through.
  Future<bool> applyToParent({bool confirm = true}) async {
    final m = material;
    final own = m.effects.length + m.values.length;
    if (!m.isVariant || own == 0) return false;
    if (confirm &&
        !await showEditorConfirm(
          context,
          title: 'Apply to ${_nameOf(m.parent)}?',
          message:
              'Writes $own of this variant\'s effects and values into '
              '${m.parent} now — that is not undone here — and everything made '
              'from it changes. This variant then takes them from it.',
          confirmLabel: 'Apply',
          danger: false,
        )) {
      return false;
    }
    final file = File('${widget.root}/${m.parent}');
    try {
      var parent = Material2DFile.parse(await file.readAsString());
      for (final MapEntry(:key, :value) in m.effects.entries) {
        parent = parent.withEffect(key, value);
      }
      for (final MapEntry(:key, :value) in m.values.entries) {
        parent = parent.withValue(key, value);
      }
      await file.writeAsString(parent.encode());
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
      return false;
    }
    _parents.remove(m.parent);
    _shownFor = null;
    stage.library.reload(m.parent);
    widget.workspace.reloadAssets?.call(m.parent);
    edit(Material2DFile(kind: m.kind, parent: m.parent));
    return true;
  }

  static bool _lastLiveInScene = true;

  /// Whether unsaved edits show in the open scene as they are made.
  bool get liveInScene => _liveInScene;
  bool _liveInScene = _lastLiveInScene;

  /// Shows unsaved edits in the open scene, or not.
  void setLiveInScene(bool on) {
    setState(() => _liveInScene = _lastLiveInScene = on);
    _syncScene();
  }

  /// The 2-D materials the open scene is drawn with.
  Material2DLibrary? get sceneMaterials {
    final engine = widget.workspace.scope.engine;
    return engine == null ? null : Material2DLibrary.of(engine.context);
  }

  // The open scene draws what is edited — a value being dragged too —
  // until it is saved or put back.
  void _syncScene() {
    final library = sceneMaterials;
    if (library == null) return;
    if (!_liveInScene || !_loaded || drawn == _saved) {
      library.endPreview(widget.path);
    } else {
      library.preview(widget.path, drawn);
    }
  }

  /// Shows a sprite material on [subject].
  void setSubject(Material2DSubject subject) {
    setState(() => _subject = _lastSubject = subject);
    _sync();
  }

  /// Lights the preview, or not.
  void setLit(bool lit) {
    setState(() => _lit = lit);
    _sync();
  }

  /// Draws the preview on a light background, or a dark one.
  void setLightBackground(bool light) {
    setState(() => _lightBackground = _lastLight = light);
    _sync();
  }

  // ── The view ──────────────────────────────────────────────────────────

  // Both stages draw alike: one with the material, one without.
  void _view2(void Function(Material2DStage s) apply) {
    apply(stage);
    apply(plainStage);
    _repaint.value++;
  }

  /// Draws a pixel of what is shown [zoom] logical pixels big; null fits it
  /// to the preview.
  void setZoom(double? zoom) {
    setState(() {});
    _view2((s) => s.zoom = zoom);
  }

  /// One step of [zoomSteps] in (+1) or out (-1), around [around] — a
  /// point of the preview of [size] — or its middle.
  void zoomBy(int steps, {Offset? around, Size? size}) {
    final now = stage.scale;
    final next = steps > 0
        ? zoomSteps.firstWhere(
            (z) => z > now * 1.001,
            orElse: () => zoomSteps.last,
          )
        : zoomSteps.lastWhere(
            (z) => z < now * 0.999,
            orElse: () => zoomSteps.first,
          );
    if (around != null && size != null && now > 0) {
      // What is under the pointer stays there.
      final p = around - size.center(Offset.zero);
      final pan = p - (p - stage.pan) * (next / now);
      _view2((s) => s.pan = pan);
    }
    setZoom(next);
  }

  /// Fits what is shown to the preview again, in its middle.
  void fit() {
    setState(() {});
    _view2(
      (s) => s
        ..zoom = null
        ..pan = Offset.zero,
    );
  }

  /// Moves what is shown by [delta] logical pixels.
  void panBy(Offset delta) => _view2((s) => s.pan = s.pan + delta);

  /// Repeats what is shown three by three, or not.
  void setTiled(bool on) {
    setState(() {});
    _view2((s) => s.tiled = on);
  }

  /// Shows the normals the light sees instead of the lit result, or not.
  void setShowNormals(bool on) {
    setState(() {});
    _view2((s) => s.showNormals = on);
  }

  /// Compares with and without the material — a line across the preview
  /// at [at] (a share of it across) — or stops.
  void setCompare(double? at) {
    setState(() => _compareAt = at?.clamp(0.02, 0.98).toDouble());
    _repaint.value++;
  }

  /// Draws without the material while Space is held.
  void setHoldingPlain(bool on) {
    if (on == _holdingPlain) return;
    setState(() => _holdingPlain = on);
    _repaint.value++;
  }

  /// Draws [effect] alone in the preview, or every effect again (null).
  void setSolo(String? effect) {
    setState(() => _solo = effect);
    _sync();
  }

  /// Plays or pauses what moves.
  void setPlaying(bool on) => setState(() => _playing = on);

  /// Plays what moves [speed] times as fast.
  void setSpeed(double speed) => setState(() => _speed = speed);

  /// Goes to [seconds] into the preview.
  void scrub(double seconds) {
    _clock.value = seconds.clamp(0, loop).toDouble();
    stage.time = plainStage.time = _clock.value;
    _repaint.value++;
  }

  /// Opens the light's settings over the preview, or closes them.
  void setLightSettingsOpen(bool open) =>
      setState(() => _lightSettingsOpen = open);

  /// Sets the light: where it is (a share of the preview across and
  /// down), its colour, how high it is, how far it reaches, how bright.
  void setLight({
    Offset? at,
    Color? colour,
    double? height,
    double? reach,
    double? strength,
  }) {
    setState(() {});
    _view2((s) {
      if (at != null) s.light = at;
      if (colour != null) s.lightColour = colour;
      if (height != null) s.lightHeight = height;
      if (reach != null) s.lightReach = reach;
      if (strength != null) s.lightStrength = strength;
    });
  }

  /// Where a light preset puts the light, and how high: from the top
  /// left, from above, grazing from the side, from behind the top right.
  static const Map<String, (Offset, double)> lightPresets = {
    'Top left': (Offset(0.3, 0.3), 0.2),
    'Above': (Offset(0.5, 0.42), 0.6),
    'Side': (Offset(0.06, 0.5), 0.06),
    'Rim': (Offset(0.86, 0.14), 0.08),
  };

  /// Sizes the material's panel [width] logical pixels wide.
  void setPanelWidth(double width) => setState(
    () => _panelWidth = _lastPanelWidth = width.clamp(220, 560).toDouble(),
  );

  /// Sizes the effects panel [width] logical pixels wide.
  void setEffectsWidth(double width) => setState(
    () => _effectsWidth = _lastEffectsWidth = width.clamp(260, 640).toDouble(),
  );

  /// Switches [effect] on (one undo step) and shows its card, unfolded.
  void addEffect(String effect) {
    MaterialCardFolds.set('2d.$effect', false);
    change((x) => x.withEffect(effect, true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final card = _cardKeys[effect]?.currentContext;
      if (card != null && card.mounted) {
        Scrollable.ensureVisible(card, alignment: 0.1);
      }
    });
  }

  /// Takes [effect] out of the material, as one undo step: switched off
  /// and its values gone. In a variant its own values go, and it is
  /// switched off over its parent's only when the parent has it on.
  void removeEffect(String effect) {
    if (_solo == effect) _solo = null;
    final m = material;
    if (!m.isVariant) {
      edit(resetEffect(m, effect).withEffect(effect, false));
      return;
    }
    final mine = m.withoutEffectOverride(effect);
    final parentHasIt = MaterialChain.resolve2D(
      widget.path,
      (p) => p == widget.path ? mine : _parent(p),
    ).value.isOn(effect);
    edit(parentHasIt ? mine.withEffect(effect, false) : mine);
  }

  /// Opens the menu of the effects that are off below [anchor], grouped
  /// and searched, and switches on the one picked.
  Future<void> openAddEffect(BuildContext anchor) async {
    final m = shown;
    final groups = [
      for (final group in groupsOf(m.kind))
        PickMenuGroup(_groups[group]!, [
          for (final e in Material2DEffects.forKind(m.kind))
            if (e.group == group && !m.isOn(e.id))
              PickMenuItem(e.id, e.label, detail: e.description),
        ]),
    ]..removeWhere((g) => g.items.isEmpty);
    final picked = await showPickMenu<String>(
      anchor,
      groups: groups,
      hint: 'Search effects',
    );
    if (picked != null && mounted) addEffect(picked);
  }

  /// The sprite selected in the scene, if one is: its image and the part
  /// of it it shows.
  Sprite? get selectedSprite {
    final entity = widget.workspace.scope.sceneState.selectedEntity.value;
    final renderable = entity?.getComponent<RenderableComponent>()?.renderable;
    return renderable is Sprite && renderable.image != null ? renderable : null;
  }

  /// The image file of the sprite selected in the scene, if it has one.
  String? get selectedSpritePath {
    final entity = widget.workspace.scope.sceneState.selectedEntity.value;
    final path = entity?.getComponent<SpriteComponent>()?.spritePath ?? '';
    return path.isEmpty ? null : path;
  }

  String? _generateNote;

  /// The image of the sprite the preview shows, when it is one of the
  /// game's: the selected sprite's (Selected), or the sprite Auto picked.
  String? get shownSpritePath => switch (_subject) {
    Material2DSubject.selected => selectedSpritePath,
    Material2DSubject.auto => _user?.spritePath,
    _ => null,
  };

  /// Makes a normal map of the image of the sprite the preview shows
  /// ([shownSpritePath]) beside it — its brightness the height, rounded at
  /// its edges — and gives its path; null (saying why) when it shows none
  /// of the game's.
  Future<String?> generateNormalMap() async {
    final source = shownSpritePath;
    if (source == null) {
      setState(
        () => _generateNote =
            'Show a sprite of the game — Auto on one drawn with it, or '
            'Selected — to make a normal map of its image.',
      );
      return null;
    }
    try {
      final made = await NormalMaps.generate(
        widget.root,
        source,
        options: const NormalMapOptions.sprite(),
      );
      widget.workspace.reloadAssets?.call(made);
      if (mounted) setState(() => _generateNote = 'Made $made from $source.');
      return made;
    } on Object catch (error) {
      if (mounted) setState(() => _generateNote = '$error');
      return null;
    }
  }

  /// [m] with every effect but [solo] left out: what the preview draws
  /// while one is soloed.
  Material2DFile _soloed(Material2DFile m) {
    var file = m;
    for (final e in Material2DEffects.forKind(shown.kind)) {
      if (e.id != _solo && shown.isOn(e.id)) {
        file = file.withEffect(e.id, false);
      }
    }
    return file;
  }

  // The stage shows what the workspace does.
  void _sync() {
    if (!_loaded) return;
    _syncScene();
    stage.library.preview(widget.path, _solo == null ? drawn : _soloed(drawn));
    plainStage.library.preview(widget.path, drawn);
    final sprite = _subject == Material2DSubject.selected
        ? selectedSprite
        : null;
    final auto = _subject == Material2DSubject.auto;
    final quality = auto
        ? ((_user?.pixelArt ?? false)
              ? FilterQuality.none
              : FilterQuality.medium)
        : (sprite?.filterQuality ?? FilterQuality.medium);
    for (final s in [stage, plainStage]) {
      s
        ..background = _lightBackground
            ? const Color(0xFFD9DDE3)
            : const Color(0xFF2A2E35)
        ..show(
          widget.path,
          kind: shown.kind,
          subject: _subject,
          image: auto ? _userImage : sprite?.image,
          source: sprite?.sourceRect,
          user: auto ? _user : null,
          quality: quality,
          lit: _lit && shown.kind == Material2DKind.sprite,
        );
    }
    _repaint.value++;
    _extensionView.changed();
  }

  @override
  void dispose() {
    // Put back: the scene draws the file again.
    sceneMaterials?.endPreview(widget.path);
    _ticker.dispose();
    _changes?.cancel();
    widget.workspace.scope.sceneState.selectedEntity.removeListener(_selected);
    if (widget.maps == null) _maps.dispose();
    stage.dispose();
    plainStage.dispose();
    _repaint.dispose();
    _effectsScroll.dispose();
    _clock.dispose();
    _drawnScale.dispose();
    _extensionView.dispose();
    super.dispose();
  }

  /// The preview's keys, as its shortcut list says them.
  static const String shortcuts =
      'F  fit      1 / 2 / 4  zoom      + / −  zoom in, out\n'
      'Wheel  zoom      Drag  pan      Double-click  fit\n'
      'C  compare      Hold Space  without the material\n'
      'B  background      L  light      N  normals\n'
      'T  tile 3 × 3      P  play or pause\n'
      'Ctrl+S  save      Ctrl+Z / Ctrl+Y  undo, redo';

  KeyEventResult _onKey(KeyEvent event) {
    final screen = shown.kind == Material2DKind.screen;
    // Space held shows the subject without the material.
    if (event.logicalKey == LogicalKeyboardKey.space &&
        !WorkspaceKeyScope.isTyping) {
      if (event is KeyDownEvent) setHoldingPlain(true);
      if (event is KeyUpEvent) setHoldingPlain(false);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (!ctrl) {
      if (WorkspaceKeyScope.isTyping) return KeyEventResult.ignored;
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyF:
          fit();
        case LogicalKeyboardKey.digit1:
          setZoom(1);
        case LogicalKeyboardKey.digit2:
          setZoom(2);
        case LogicalKeyboardKey.digit4:
          setZoom(4);
        case LogicalKeyboardKey.equal:
        case LogicalKeyboardKey.numpadAdd:
          zoomBy(1);
        case LogicalKeyboardKey.minus:
        case LogicalKeyboardKey.numpadSubtract:
          zoomBy(-1);
        case LogicalKeyboardKey.keyL when !screen:
          setLit(!_lit);
        case LogicalKeyboardKey.keyN when !screen:
          setShowNormals(!stage.showNormals);
        case LogicalKeyboardKey.keyT when !screen:
          setTiled(!stage.tiled);
        case LogicalKeyboardKey.keyC:
          setCompare(_compareAt == null ? 0.5 : null);
        case LogicalKeyboardKey.keyB:
          setLightBackground(!_lightBackground);
        case LogicalKeyboardKey.keyP:
          setPlaying(!_playing);
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyZ when shift:
      case LogicalKeyboardKey.keyY:
        redo();
      case LogicalKeyboardKey.keyZ:
        undo();
      case LogicalKeyboardKey.keyS:
        save();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.path.substring(widget.path.lastIndexOf('/') + 1);
    final screen = shown.kind == Material2DKind.screen;
    return WorkspaceKeyScope(
      onKey: _onKey,
      child: ColoredBox(
        color: EditorTheme.panelBg,
        child: Column(
          children: [
            WorkspaceHeader(
              icon: screen ? Icons.filter_frames_outlined : Icons.auto_awesome,
              title: screen ? 'Screen material' : '2D material',
              file: name,
              dirty: dirty,
              onSave: save,
              onUndo: _at > 0 ? undo : null,
              onRedo: _at < _history.length - 1 ? redo : null,
              tools: [
                Tooltip(
                  message:
                      'Unsaved edits show in the open scene as they are made',
                  child: switchRow(
                    'In the scene',
                    _liveInScene,
                    setLiveInScene,
                  ),
                ),
              ],
              fullScreen: widget.workspace.fullScreen,
              onToggleFullScreen: widget.workspace.onToggleFullScreen,
              onClose: widget.workspace.onClose,
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: _panelWidth, child: _fields()),
                  PanelResizeHandle(
                    onDrag: (dx) => setPanelWidth(_panelWidth + dx),
                  ),
                  Expanded(child: _previewPane()),
                  PanelResizeHandle(
                    onDrag: (dx) => setEffectsWidth(_effectsWidth - dx),
                  ),
                  SizedBox(width: _effectsWidth, child: _effects()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Fields ────────────────────────────────────────────────────────────

  TextStyle get _label => TextStyle(color: EditorTheme.textMuted, fontSize: 11);

  Widget _note(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
    child: Text(
      text,
      style: color == null ? _label : TextStyle(color: color, fontSize: 11),
    ),
  );

  /// A value's row: its label, the field, and — in a variant — whether
  /// the value is the variant's own (with a way back to the parent's) or
  /// its parent's. [key] is the value it edits (`effect.name`).
  Widget _row(String label, Widget field, {double indent = 0, String? key}) {
    final own = key != null && _isOwnValue(key);
    return Padding(
      padding: EdgeInsets.fromLTRB(12 + indent, 4, 12, 4),
      child: Row(
        children: [
          SizedBox(
            width: InspectorField.labelWidth - indent,
            child: Text(
              label,
              style: own
                  ? InspectorField.labelStyle.copyWith(
                      color: EditorTheme.accent,
                    )
                  : InspectorField.labelStyle,
            ),
          ),
          Expanded(child: field),
          if (key != null && material.isVariant) _inheritValue(key),
        ],
      ),
    );
  }

  /// Whether the variant gives [key] (`effect.name`) itself.
  bool _isOwnValue(String key) =>
      material.isVariant && material.values.containsKey(key);

  /// Whether the variant switches effect [id] itself, or gives any of its
  /// values.
  bool _isOwnEffect(String id) =>
      material.isVariant &&
      (material.effects.containsKey(id) ||
          material.values.keys.any((k) => k.startsWith('$id.')));

  Widget _inheritValue(String key) => _inherit(
    own: _isOwnValue(key),
    onRevert: () => edit(material.withoutValue(key)),
  );

  Widget _inheritEffect(String id) => _inherit(
    own: _isOwnEffect(id),
    onRevert: () => edit(material.withoutEffectOverride(id)),
  );

  Widget _inherit({required bool own, required VoidCallback onRevert}) =>
      SizedBox(
        width: 24,
        child: own
            ? EditorIconButton(
                icon: Icons.undo,
                tooltip: "Its own: back to the parent's",
                iconSize: 14,
                size: 22,
                onTap: onRevert,
              )
            : Tooltip(
                message: "The parent's",
                child: Icon(Icons.link, size: 12, color: EditorTheme.textMuted),
              ),
      );

  // In a variant, [child] with the sign of whose [key] is beside it.
  Widget _ownable(String key, Widget child) => !material.isVariant
      ? child
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: child),
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 12),
              child: _inheritValue(key),
            ),
          ],
        );

  /// A switch with its name beside it.
  Widget switchRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    bool strong = false,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      EditorToggle(value: value, label: label, onChanged: onChanged),
      const SizedBox(width: 6),
      Text(
        label,
        style: strong
            ? TextStyle(
                color: EditorTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              )
            : _label,
      ),
    ],
  );

  static String _nameOf(String path) =>
      path.substring(path.lastIndexOf('/') + 1);

  static const Map<String, String> _groups = {
    'colour': 'Colour',
    'edges': 'Edges',
    'motion': 'Motion',
    'light': 'Light',
    'screen': 'The frame',
  };

  /// The groups [kind]'s effects are shown in, in order.
  static List<String> groupsOf(Material2DKind kind) =>
      kind == Material2DKind.screen
      ? const ['screen', 'colour']
      : const ['colour', 'edges', 'motion', 'light'];

  Widget _variant() {
    final m = material;
    final own = m.effects.length + m.values.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: EditorTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: EditorTheme.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.call_split, size: 14, color: EditorTheme.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Variant of ${_nameOf(m.parent)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: EditorTheme.textPrimary,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      own == 0
                          ? 'Everything from its parent'
                          : '$own of its own, the rest from its parent',
                      style: _label,
                    ),
                  ],
                ),
              ),
              EditorButton(
                label: 'Open parent',
                kind: EditorButtonKind.ghost,
                onPressed: () =>
                    widget.workspace.scope.openInWorkspace(m.parent),
              ),
            ],
          ),
          if (own > 0)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                EditorButton(
                  label: 'Revert all',
                  kind: EditorButtonKind.ghost,
                  onPressed: revertAll,
                ),
                EditorButton(
                  label: 'Apply to parent',
                  kind: EditorButtonKind.ghost,
                  onPressed: applyToParent,
                ),
              ],
            ),
          for (final problem in _chainProblems)
            Text(
              problem,
              style: TextStyle(color: EditorTheme.warning, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _fields() {
    final m = shown;
    final problems = material.validate();
    return ListView(
      children: [
        if (!_loaded && _error == null) _note('Loading…'),
        if (_error != null) _note('$_error', color: EditorTheme.warning),
        if (material.isVariant) _variant(),
        const SizedBox(height: 6),
        _row(
          'Preset',
          EditorDropdown<String>(
            value: null,
            hint: 'Start from…',
            tooltip: 'Switches effects on with values, as one undo step',
            options: [
              for (final p in Material2DPreset.of(m.kind))
                EditorDropdownOption(
                  value: p.id,
                  label: p.label,
                  detail: p.detail,
                ),
            ],
            onChanged: (id) {
              final preset = Material2DPreset.byId(id);
              if (preset != null) change(preset.apply);
            },
          ),
        ),
        _row(
          'Kind',
          EditorSegmented<Material2DKind>(
            value: m.kind,
            options: const [
              (Material2DKind.sprite, 'Sprite'),
              (Material2DKind.screen, 'Screen'),
            ],
            disabled: material.isVariant
                ? const {Material2DKind.sprite, Material2DKind.screen}
                : const {},
            tooltips: const {
              Material2DKind.sprite: 'On sprites, shapes and tile layers',
              Material2DKind.screen: 'Over the whole frame, from the camera',
            },
            onChanged: (k) => change((x) => _asKind(x, k)),
          ),
        ),
        WorkspaceSections(view: _extensionView),
        for (final problem in problems)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              problem,
              style: TextStyle(color: EditorTheme.warning, fontSize: 11),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// [m] as a material of [kind]: the effects that work on it kept, the
  /// others (and their values) dropped.
  static Material2DFile _asKind(Material2DFile m, Material2DKind kind) {
    final keep = {for (final e in Material2DEffects.forKind(kind)) e.id};
    return Material2DFile(
      kind: kind,
      parent: m.parent,
      effects: {
        for (final e in m.effects.entries)
          if (keep.contains(e.key)) e.key: e.value,
      },
      values: {
        for (final v in m.values.entries)
          if (keep.contains(v.key.substring(0, v.key.indexOf('.'))))
            v.key: v.value,
      },
    );
  }

  // ── Effects ───────────────────────────────────────────────────────────

  // The effects panel, on the right: the effects that are on, in the order
  // they are applied, each a card; more are added from a menu.
  Widget _effects() {
    final m = shown;
    final on = [
      for (final e in Material2DEffects.forKind(m.kind))
        if (m.isOn(e.id)) e,
    ];
    // In a variant: effects it switches off itself, whatever its parent's.
    final offHere = [
      if (material.isVariant)
        for (final e in Material2DEffects.forKind(m.kind))
          if (material.effects[e.id] == false) e,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorSectionHeader(
          on.isEmpty ? 'Effects' : 'Effects · ${on.length}',
          trailing: Builder(
            builder: (context) => EditorButton(
              label: 'Add effect',
              icon: Icons.add,
              kind: EditorButtonKind.ghost,
              onPressed: _loaded ? () => openAddEffect(context) : null,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            controller: _effectsScroll,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              if (on.isEmpty)
                _note('No effect is on yet: add one, or start from a preset.'),
              for (final e in on) _card(e, m),
              if (offHere.isNotEmpty) ...[
                const EditorSectionHeader('Off in this variant'),
                for (final e in offHere) _offRow(e),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// [m] with [effect]'s values back to its defaults (a variant's to its
  /// parent's).
  static Material2DFile resetEffect(Material2DFile m, String effect) {
    var file = m;
    for (final key in m.values.keys.toList()) {
      if (key.startsWith('$effect.')) file = file.withoutValue(key);
    }
    return file;
  }

  Widget _card(Material2DEffect effect, Material2DFile m) {
    final solo = _solo == effect.id;
    final changed = material.values.keys.any(
      (k) => k.startsWith('${effect.id}.'),
    );
    final fold = '2d.${effect.id}';
    return MaterialCard(
      key: _cardKeys.putIfAbsent(effect.id, () => GlobalKey()),
      title: effect.label,
      description: effect.description,
      folded: MaterialCardFolds.isFolded(fold),
      onFold: (folded) => setState(() => MaterialCardFolds.set(fold, folded)),
      highlighted: solo,
      actions: [
        EditorIconButton(
          icon: Icons.center_focus_strong_outlined,
          tooltip: solo
              ? 'Showing it alone: show every effect'
              : 'Solo: show it alone in the preview',
          isActive: solo,
          iconSize: 14,
          size: 22,
          onTap: () => setSolo(solo ? null : effect.id),
        ),
        EditorIconButton(
          icon: Icons.restart_alt,
          tooltip: material.isVariant
              ? "Back to its parent's values"
              : 'Back to its defaults',
          iconSize: 14,
          size: 22,
          onTap: changed
              ? () => change((x) => resetEffect(x, effect.id))
              : null,
        ),
        if (material.isVariant) _inheritEffect(effect.id),
        EditorIconButton(
          icon: Icons.close,
          tooltip: 'Remove the effect',
          iconSize: 14,
          size: 22,
          onTap: () => removeEffect(effect.id),
        ),
      ],
      children: [for (final p in effect.params) _param(effect, p, m)],
    );
  }

  // An effect a variant switches off itself, with a way back to its
  // parent's.
  Widget _offRow(Material2DEffect effect) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            effect.label,
            style: TextStyle(color: EditorTheme.textPrimary, fontSize: 12),
          ),
        ),
        _inheritEffect(effect.id),
      ],
    ),
  );

  Widget _param(Material2DEffect effect, Material2DParam p, Material2DFile m) {
    final key = '${effect.id}.${p.name}';
    void set(Object v) => change((x) => x.withValue(key, v));
    void show(Object v) => preview((x) => x.withValue(key, v));
    const indent = 16.0;
    switch (p.type) {
      case Material2DValue.number:
        final min = p.min ?? 0, max = p.max ?? 1;
        return _row(
          p.label,
          EditorSlider(
            value: m.number(key).clamp(min, max).toDouble(),
            min: min,
            max: max,
            step: (max - min) / 200,
            decimals: max - min > 20 ? 0 : 2,
            unit: p.unit,
            onChanged: show,
            onChangeEnd: set,
          ),
          indent: indent,
          key: key,
        );
      case Material2DValue.colour:
        final argb = m.colour(key);
        return _row(
          p.label,
          Align(
            alignment: Alignment.centerLeft,
            child: MiniColorField(
              key: ValueKey('$key:$argb'),
              color: Color(argb),
              title: '${effect.label}: ${p.label}',
              onPreview: (c) => show(c.toARGB32()),
              onPreviewEnd: endPreview,
              onChanged: (c) => set(c.toARGB32()),
            ),
          ),
          indent: indent,
          key: key,
        );
      case Material2DValue.toggle:
        return _row(
          p.label,
          Align(
            alignment: Alignment.centerLeft,
            child: EditorToggle(
              value: m.toggle(key),
              label: p.label,
              onChanged: set,
            ),
          ),
          indent: indent,
          key: key,
        );
      case Material2DValue.choice:
        final value = m.text(key);
        return _row(
          p.label,
          EditorSegmented<String>(
            value: value,
            options: [for (final c in p.choices) (c, _title(c))],
            onChanged: set,
          ),
          indent: indent,
          key: key,
        );
      case Material2DValue.pair:
        final (x, y) = m.pair(key);
        final min = p.min ?? double.negativeInfinity;
        final max = p.max ?? double.infinity;
        Widget field(String axis, double v, List<double> Function(double) to) =>
            Expanded(
              child: Row(
                children: [
                  Text(axis, style: _label),
                  const SizedBox(width: 4),
                  Expanded(
                    child: MiniNumberField(
                      key: ValueKey('$key.$axis:$v'),
                      value: v,
                      fractionDigits: 1,
                      onSubmitted: (n) {
                        if (n.isFinite) set(to(n.clamp(min, max).toDouble()));
                      },
                    ),
                  ),
                ],
              ),
            );
        return _row(
          p.unit.isEmpty ? p.label : '${p.label} (${p.unit})',
          Row(
            children: [
              field('x', x, (n) => [n, y]),
              const SizedBox(width: 8),
              field('y', y, (n) => [x, n]),
            ],
          ),
          indent: indent,
          key: key,
        );
      case Material2DValue.path:
        final path = m.text(key);
        return _ownable(
          key,
          Padding(
            padding: const EdgeInsets.fromLTRB(12 + indent, 2, 12, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AssetRefEditorRow(
                  label: p.label,
                  value: path,
                  extensions: [
                    for (final e in Material2DFile.imageEndings) e.substring(1),
                  ],
                  onGenerate: effect.id == 'normalMap'
                      ? generateNormalMap
                      : null,
                  onChanged: set,
                ),
                if (path.isNotEmpty)
                  ValueListenableBuilder<int>(
                    valueListenable: _maps.revision,
                    builder: (context, _, _) => _mapDetail(path, () => set('')),
                  ),
                if (effect.id == 'normalMap')
                  Padding(
                    padding: const EdgeInsets.only(
                      left: InspectorField.labelWidth,
                      top: 2,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: EditorButton(
                        label: shownSpritePath == null
                            ? 'Make from a sprite…'
                            : 'Make from ${_nameOf(shownSpritePath!)}',
                        kind: EditorButtonKind.ghost,
                        onPressed: () async {
                          final made = await generateNormalMap();
                          if (made != null) set(made);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      case Material2DValue.stops:
        final stops = m.stops(key);
        List<Object> saved(List<(double, int)> s) => [
          for (final (at, c) in s) [at, c],
        ];
        return _ownable(
          key,
          Padding(
            padding: const EdgeInsets.fromLTRB(12 + indent, 4, 12, 4),
            child: GradientStopsEditor(
              stops: stops,
              maxItems: p.maxItems,
              onPreview: (s) => show(saved(s)),
              onPreviewEnd: endPreview,
              onChanged: (s) => set(saved(s)),
            ),
          ),
        );
      case Material2DValue.swaps:
        final swaps = m.swaps(key);
        List<Object> saved(List<(int, int)> s) => [
          for (final (from, to) in s) [from, to],
        ];
        return _ownable(
          key,
          Padding(
            padding: const EdgeInsets.fromLTRB(12 + indent, 4, 12, 4),
            child: ColourSwapsEditor(
              swaps: swaps,
              maxItems: p.maxItems,
              suggestions:
                  _subject == Material2DSubject.sample ||
                      stage.autoShows == Material2DAuto.sample
                  ? Material2DSamples.spriteColours
                  : const [],
              onPreview: (s) => show(saved(s)),
              onPreviewEnd: endPreview,
              onChanged: (s) => set(saved(s)),
            ),
          ),
        );
    }
  }

  static String _title(String name) {
    final spaced = name.replaceAllMapped(
      RegExp('[A-Z]'),
      (c) => ' ${c[0]!.toLowerCase()}',
    );
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  Widget _mapDetail(String path, VoidCallback onClear) {
    final picture = _maps.peek(path);
    final failed = _maps.failed(path);
    return Padding(
      padding: const EdgeInsets.fromLTRB(InspectorField.labelWidth, 2, 0, 2),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF15181D),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: EditorTheme.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: picture != null
                ? RawImage(image: picture.image, fit: BoxFit.contain)
                : Icon(
                    failed ? Icons.broken_image_outlined : Icons.image_outlined,
                    size: 16,
                    color: failed ? EditorTheme.warning : EditorTheme.textMuted,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              failed
                  ? "Can't be read"
                  : picture == null
                  ? 'Reading…'
                  : '${picture.width} × ${picture.height}',
              style: failed
                  ? TextStyle(color: EditorTheme.warning, fontSize: 11)
                  : _label,
            ),
          ),
          EditorButton(
            label: 'Clear',
            kind: EditorButtonKind.ghost,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }

  // ── Preview ───────────────────────────────────────────────────────────

  static const Map<Material2DSubject, IconData> _subjectIcons = {
    Material2DSubject.auto: Icons.auto_awesome,
    Material2DSubject.sample: Icons.circle_outlined,
    Material2DSubject.selected: Icons.ads_click,
    Material2DSubject.tiles: Icons.view_week_outlined,
  };

  static const Map<Material2DSubject, String> _subjectTips = {
    Material2DSubject.auto:
        "What it fits: the game's own sprite or shape drawn with it, else "
        'tiles (normal maps, waves, scrolling) or the sample disc',
    Material2DSubject.sample: 'The sample disc',
    Material2DSubject.selected: 'The sprite selected in the scene',
    Material2DSubject.tiles: 'A row of tiles',
  };

  Widget _previewPane() {
    final screen = shown.kind == Material2DKind.screen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(screen),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _view(screen)),
              Positioned(left: 10, right: 10, bottom: 8, child: _chips(screen)),
              if (_lightSettingsOpen && !screen)
                Positioned(top: 8, right: 10, child: _lightSettings()),
            ],
          ),
        ),
        if (stage.moving) _timeBar(),
      ],
    );
  }

  Widget _toolbar(bool screen) {
    final left = <Widget>[
      if (!screen)
        for (final s in Material2DSubject.values)
          EditorChip(
            label: s.label,
            icon: _subjectIcons[s],
            tooltip: _subjectTips[s],
            selected: _subject == s,
            onTap: () => setSubject(s),
          ),
      if (!screen && _subject == Material2DSubject.auto && _users.isNotEmpty)
        _usersChip(),
    ];
    final right = <Widget>[
      if (!screen) ...[
        EditorIconButton(
          icon: Icons.grid_on,
          tooltip: 'Tile 3 × 3: check the seams (T)',
          isActive: stage.tiled,
          onTap: () => setTiled(!stage.tiled),
        ),
        EditorIconButton(
          icon: Icons.terrain_outlined,
          tooltip: 'Normals: as the light sees them (N)',
          isActive: stage.showNormals,
          onTap: () => setShowNormals(!stage.showNormals),
        ),
      ],
      EditorIconButton(
        icon: Icons.compare,
        tooltip: 'Compare with and without the material (C; hold Space)',
        isActive: _compareAt != null,
        onTap: () => setCompare(_compareAt == null ? 0.5 : null),
      ),
      if (!screen) ...[
        const ToolSeparator(),
        EditorIconButton(
          icon: Icons.light_mode_outlined,
          tooltip: _lit ? 'Light on (L)' : 'Light off (L)',
          isActive: _lit,
          onTap: () => setLit(!_lit),
        ),
        EditorIconButton(
          icon: Icons.tune,
          tooltip: 'Light settings',
          isActive: _lightSettingsOpen,
          onTap: () => setLightSettingsOpen(!_lightSettingsOpen),
        ),
      ],
      const ToolSeparator(),
      // Its own size: in a wrap it would take the whole line.
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EditorSegmented<bool>(
            value: _lightBackground,
            options: const [(false, 'Dark'), (true, 'Bright')],
            tooltips: const {
              false: 'A dark background (B)',
              true: 'A light background (B)',
            },
            onChanged: setLightBackground,
          ),
        ],
      ),
      const ToolSeparator(),
      ZoomControls(
        label: ValueListenableBuilder<double>(
          valueListenable: _drawnScale,
          builder: (context, scale, _) => Text(
            stage.zoom == null
                ? 'Fit · ${(scale * 100).round()}%'
                : '${(scale * 100).round()}%',
            textAlign: TextAlign.center,
            style: _label,
          ),
        ),
        onZoomOut: () => zoomBy(-1),
        onZoomIn: () => zoomBy(1),
        steps: [
          for (final (label, zoom, tip) in const [
            ('Fit', null, 'Fit it to the preview (F; double-click)'),
            ('1:1', 1.0, 'A pixel of it a pixel of the screen (1)'),
            ('2×', 2.0, 'Twice as big (2)'),
            ('4×', 4.0, 'Four times as big (4)'),
          ])
            ZoomStep(
              label,
              tip,
              selected: zoom == null ? stage.zoom == null : stage.zoom == zoom,
              onTap: () => zoom == null ? fit() : setZoom(zoom),
            ),
        ],
      ),
      WorkspaceToolButtons(view: _extensionView),
      const ToolSeparator(),
      const ShortcutsHint(shortcuts),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 6,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: left,
          ),
          Wrap(
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: right,
          ),
        ],
      ),
    );
  }

  // Which of the game's sprites and shapes Auto shows it on.
  Widget _usersChip() {
    final user = _user;
    final more = _users.length > 1;
    return Builder(
      builder: (context) => Tooltip(
        message: more
            ? 'Shown on this; pick another drawn with the material'
            : 'Drawn with the material in the project',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: !more
              ? null
              : () async {
                  final picked = await showEditorMenuBelow<Material2DUser>(
                    context,
                    [
                      for (final u in _users)
                        editorMenuItem(
                          u,
                          u.count > 1 ? '${u.label}  × ${u.count}' : u.label,
                          icon: u.spritePath != null
                              ? Icons.image_outlined
                              : Icons.category_outlined,
                          color: identical(u, user) ? EditorTheme.accent : null,
                        ),
                    ],
                  );
                  if (picked != null) await pickUser(picked);
                },
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 3, 6, 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: EditorTheme.textPrimary.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  user?.spritePath != null
                      ? Icons.image_outlined
                      : Icons.category_outlined,
                  size: 12,
                  color: EditorTheme.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  user == null ? 'Nothing of the game' : 'On ${user.label}',
                  style: TextStyle(
                    color: EditorTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
                if (user != null && user.count > 1)
                  Text('  × ${user.count}', style: _label),
                if (more)
                  Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: EditorTheme.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // What the preview says: in chips over its foot.
  Widget _chips(bool screen) {
    final chips = <Widget>[
      if (!screen &&
          _subject == Material2DSubject.selected &&
          selectedSprite == null)
        PreviewChip(
          'Select a sprite in the scene to see it here; the sample shows '
          'meanwhile',
          icon: Icons.info_outline,
        ),
      if (_solo case final id?)
        PreviewChip(
          'Solo: ${Material2DEffects.byId(id)?.label ?? id}',
          icon: Icons.center_focus_strong_outlined,
          onClose: () => setSolo(null),
        ),
      if (!screen && stage.showNormals)
        PreviewChip(
          'Normals: red, green across and up; flat is blue',
          icon: Icons.terrain_outlined,
          onClose: () => setShowNormals(false),
        ),
      if (_holdingPlain)
        PreviewChip('Without the material', icon: Icons.compare),
      if (_lit && !screen && !stage.showNormals)
        PreviewChip(
          'Drag the sun to move the light',
          icon: Icons.light_mode_outlined,
        ),
      if (stage.library.errorOf(widget.path) case final error?)
        PreviewChip('$error', icon: Icons.warning_amber_rounded, warn: true),
      if (_generateNote case final note?)
        PreviewChip(
          note,
          icon: Icons.auto_fix_high,
          onClose: () => setState(() => _generateNote = null),
        ),
    ];
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  // The light's settings, over the preview's corner.
  Widget _lightSettings() {
    Widget slider(
      String label,
      double value,
      double min,
      double max,
      void Function(double v) set,
    ) => _row(
      label,
      EditorSlider(
        value: value.clamp(min, max).toDouble(),
        min: min,
        max: max,
        step: (max - min) / 100,
        decimals: 2,
        onChanged: set,
        onChangeEnd: set,
      ),
    );

    return Container(
      width: 300,
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: EditorTheme.panelBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EditorTheme.border),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
            child: Row(
              children: [
                Icon(
                  Icons.light_mode_outlined,
                  size: 14,
                  color: EditorTheme.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  'The light',
                  style: TextStyle(
                    color: EditorTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                EditorIconButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  iconSize: 14,
                  size: 22,
                  onTap: () => setLightSettingsOpen(false),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final MapEntry(key: name, value: (at, height))
                    in lightPresets.entries)
                  EditorChip(
                    label: name,
                    selected: stage.light == at && stage.lightHeight == height,
                    onTap: () {
                      if (!_lit) setLit(true);
                      setLight(at: at, height: height);
                    },
                  ),
              ],
            ),
          ),
          _row(
            'Colour',
            Align(
              alignment: Alignment.centerLeft,
              child: MiniColorField(
                key: ValueKey('light:${stage.lightColour.toARGB32()}'),
                color: stage.lightColour,
                title: 'The light: colour',
                onPreview: (c) => setLight(colour: c),
                onPreviewEnd: () {},
                onChanged: (c) => setLight(colour: c),
              ),
            ),
          ),
          slider(
            'Height',
            stage.lightHeight,
            0.02,
            1,
            (v) => setLight(height: v),
          ),
          slider('Reach', stage.lightReach, 0.1, 2, (v) => setLight(reach: v)),
          slider(
            'Strength',
            stage.lightStrength,
            0,
            4,
            (v) => setLight(strength: v),
          ),
        ],
      ),
    );
  }

  // Play, pause, speed and where it is, for what moves.
  Widget _timeBar() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
    child: Row(
      children: [
        EditorIconButton(
          icon: _playing ? Icons.pause : Icons.play_arrow,
          tooltip: _playing ? 'Pause (P)' : 'Play (P)',
          onTap: () => setPlaying(!_playing),
        ),
        const SizedBox(width: 6),
        EditorSegmented<double>(
          value: _speed,
          options: const [(0.25, '¼×'), (0.5, '½×'), (1.0, '1×'), (2.0, '2×')],
          onChanged: setSpeed,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: _clock,
            builder: (context, t, _) => EditorSlider(
              value: t,
              min: 0,
              max: loop,
              step: 0.01,
              decimals: 2,
              unit: 's',
              onChanged: scrub,
              onChangeEnd: scrub,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _view(bool screen) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final lit = !screen && (_lit || stage.showNormals);
      final split = _compareAt;
      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
            zoomBy(
              e.scrollDelta.dy < 0 ? 1 : -1,
              around: e.localPosition,
              size: size,
            );
          }
        },
        child: GestureDetector(
          onPanUpdate: (d) => panBy(d.delta),
          onDoubleTap: fit,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRect(
                  child: CustomPaint(
                    size: size,
                    painter: _StagePainter(
                      stage,
                      plainStage,
                      () => _holdingPlain ? 1.0 : _compareAt,
                      MediaQuery.devicePixelRatioOf(context),
                      _repaint,
                      onDrawn: (scale) {
                        if (scale == _drawnScale.value) return;
                        SchedulerBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _drawnScale.value = scale;
                        });
                      },
                    ),
                  ),
                ),
              ),
              if (split != null && !_holdingPlain) ...[
                Positioned(
                  left: split * size.width - 12,
                  top: 0,
                  bottom: 0,
                  width: 24,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) => setCompare(
                        (split * size.width + d.delta.dx) / size.width,
                      ),
                      child: Center(
                        child: Container(
                          width: 2,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: size.width * (1 - split) + 10,
                  child: PreviewChip('Without', icon: Icons.chevron_left),
                ),
                Positioned(
                  top: 8,
                  left: split * size.width + 10,
                  child: PreviewChip('With', icon: Icons.chevron_right),
                ),
              ],
              if (lit) _lightHandle(size),
              ...workspaceOverlays(_extensionView, size),
            ],
          ),
        ),
      );
    },
  );

  // The light: a sun to drag.
  Widget _lightHandle(Size size) {
    final at = stage.lightPosition(size);
    return Positioned(
      left: at.dx - 14,
      top: at.dy - 14,
      child: Tooltip(
        message: 'The light: drag it',
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: GestureDetector(
            onPanUpdate: (d) {
              final next = stage.lightPosition(size) + d.delta;
              setLight(at: Offset(next.dx / size.width, next.dy / size.height));
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.55),
                border: Border.all(color: EditorTheme.accent, width: 1.5),
              ),
              child: Icon(Icons.wb_sunny, size: 16, color: stage.lightColour),
            ),
          ),
        ),
      ),
    );
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter(
    this.stage,
    this.plain,
    this.split,
    this.pixelRatio,
    Listenable repaint, {
    required this.onDrawn,
  }) : super(repaint: repaint);

  /// Told the scale the stage was drawn at, each time it is.
  final void Function(double scale) onDrawn;

  final Material2DStage stage;

  /// The same drawn without the material.
  final Material2DStage plain;

  /// Where the compare line is (a share across: [plain] to its left), or
  /// null when not comparing.
  final double? Function() split;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final at = split();
    if (at == null) {
      stage.paint(canvas, size, pixelRatio: pixelRatio);
      onDrawn(stage.scale);
      return;
    }
    final x = size.width * at;
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(0, 0, x, size.height));
    plain.paint(canvas, size, pixelRatio: pixelRatio);
    canvas.restore();
    if (at >= 1) {
      onDrawn(plain.scale);
      return;
    }
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(x, 0, size.width - x, size.height));
    stage.paint(canvas, size, pixelRatio: pixelRatio);
    canvas.restore();
    onDrawn(stage.scale);
  }

  @override
  bool shouldRepaint(_StagePainter old) =>
      !identical(old.stage, stage) || old.pixelRatio != pixelRatio;
}

// What modules adding to the window see of it.
final class _Material2DView implements Material2DWorkspaceView {
  _Material2DView(this._state);

  final Material2DWorkspaceState _state;
  final ValueNotifier<int> _changes = ValueNotifier(0);
  bool _gone = false;

  // A late redraw, after the window went, changes nothing.
  void changed() {
    if (!_gone) _changes.value++;
  }

  void dispose() {
    _gone = true;
    _changes.dispose();
  }

  @override
  String get workspaceId => WorkspaceIds.material2D;

  @override
  String? get path => _state.widget.path;

  @override
  EditorScope get scope => _state.widget.workspace.scope;

  @override
  Listenable get changes => _changes;

  @override
  Material2DFile get material => _state.material;

  @override
  Material2DFile get shown => _state.shown;

  @override
  void change(Material2DFile Function(Material2DFile m) change) =>
      _state.change(change);

  @override
  void preview(Material2DFile Function(Material2DFile m) change) =>
      _state.preview(change);

  @override
  void endPreview() => _state.endPreview();
}
