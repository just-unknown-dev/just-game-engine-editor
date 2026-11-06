import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../map_pictures.dart';
import 'material_2d_fields.dart';
import 'material_2d_preset.dart';
import 'material_2d_samples.dart';
import '../normal_maps.dart';
import 'material_2d_stage.dart';
import 'material_2d_users.dart';
import '../material_window_kit.dart';

part 'material_2d_workspace_stage.dart';
part 'material_2d_workspace_fields.dart';
part 'material_2d_workspace_preview.dart';

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
    this.users,
    this.changes,
    this.loadOnStart = true,
  });

  /// The material, project-relative.
  final String path;

  /// The project folder.
  final String root;

  /// The pictures of the images its effects name; its own when null.
  final MapPictures? maps;

  /// What in the project draws with 2-D materials, for Auto; its own when
  /// null.
  final Material2DUsers? users;

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
      return Material2DFile.parse(_fileOf(path).readAsStringSync());
    } on Object {
      return null;
    }
  });

  // The file at [path]: the project's, or a package's asset key.
  File _fileOf(String path) =>
      File(PackageAssetPaths.of(widget.root).absolute(path));

  // Why [path] can't be written, or null when it can: a package in pub's
  // shared cache is every project's.
  String? _readOnly(String path) =>
      PackageAssetPaths.of(widget.root).isWritable(path)
      ? null
      : "$path is in pub's shared cache, used by every project: it can't be "
            'changed here.';

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

  /// The same subject drawn without the material, to compare with: it
  /// reads the material through [stage]'s library, so the images are
  /// decoded once for both.
  late final Material2DStage plainStage = Material2DStage(
    root: widget.root,
    filesFrom: stage,
  )..plain = true;

  /// Where the compare line is, a share of the preview across: drawn
  /// without the material to its left, with it to its right. Null when not
  /// comparing.
  double? get compareAt => _compareAt;
  double? _compareAt;

  // The compare line moved: the preview is built again, not the window.
  final ValueNotifier<int> _compareLine = ValueNotifier(0);

  // The zoom changed: the zoom controls are built again, not the window.
  final ValueNotifier<int> _framing = ValueNotifier(0);

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

  /// What in the project draws with 2-D materials: the module's, else its
  /// own.
  late final Material2DUsers _finder =
      widget.users ?? Material2DUsers(root: widget.root);

  /// Which cards are folded: the editor's, kept for the next material.
  late final MaterialCardFolds _folds = MaterialCardFolds.of(
    widget.workspace.scope,
  );
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  StreamSubscription<String>? _changes;

  File get _file => _fileOf(widget.path);

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

  /// The least time between two drawings of what moves: at most one every
  /// 12 ms, about 83 a second — every frame of a 60 Hz screen (whose frames
  /// come a little early or late), every other one of a 120 or 144 Hz one.
  static const Duration movingFrame = Duration(milliseconds: 12);

  // Seconds played that are not drawn yet, and when what moves last was.
  double _unshown = 0;
  Duration _lastMoved = Duration.zero;

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (_playing && stage.moving) _unshown += dt * _speed;
    final due = _unshown > 0 && elapsed - _lastMoved >= movingFrame;
    if (due) {
      _lastMoved = elapsed;
      _clock.value = (_clock.value + _unshown) % loop;
      _unshown = 0;
    }
    stage.time = plainStage.time = _clock.value;
    final comparing = _compareAt != null || _holdingPlain;
    if (due || !stage.ready || (comparing && !plainStage.ready)) {
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
    if (!mounted) return;
    setState(() {});
    _sync();
    if (path == _user?.spritePath) {
      // The sprite Auto shows it on: read again (the old image goes once
      // the new one is laid out).
      stage.forgetImage(path);
      unawaited(pickUser(_user));
    } else if (path.endsWith('.json') &&
        !path.endsWith('.material.json') &&
        !Material2DFile.isMaterial2DPath(path)) {
      // A scene or prefab: what is drawn with the material may be another.
      unawaited(_findUser());
    }
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
  // drawn with it — the first of them, until another is picked (and kept
  // when they are looked for again, while it is still one of them).
  Future<void> _findUser() async {
    final users = await _finder.findAll(widget.path);
    if (!mounted) return;
    final was = _user;
    setState(() => _users = users);
    await pickUser(
      users.where((u) => _sameUser(u, was)).firstOrNull ?? users.firstOrNull,
    );
  }

  static bool _sameUser(Material2DUser a, Material2DUser? b) =>
      b != null &&
      a.file == b.file &&
      a.entity == b.entity &&
      a.spritePath == b.spritePath;

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

  /// Puts [next] in as the material, one undo step. Nothing is edited until
  /// the file is read: one that could not be (broken JSON, a newer format)
  /// is never written over with the defaults shown meanwhile.
  void edit(Material2DFile next) {
    if (!_loaded) return;
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

  /// [m] as it draws: for a variant, laid over its parents.
  Material2DFile _resolved(Material2DFile m) => !m.isVariant
      ? m
      : MaterialChain.resolve2D(
          widget.path,
          (p) => p == widget.path ? m : _parent(p),
        ).value;

  /// [after] — what an edit made of [before], the material as it draws —
  /// kept as this window's material: on a variant, every effect switched
  /// and every value set that differs from [before] becomes its own, and
  /// the rest stay its parents'. A plain material is [after] itself.
  Material2DFile _withEdit(Material2DFile before, Material2DFile after) {
    final own = material;
    if (!own.isVariant) return after;
    final effects = {...own.effects};
    for (final id in {...before.effects.keys, ...after.effects.keys}) {
      final on = after.isOn(id);
      if (before.isOn(id) != on) effects[id] = on;
    }
    final values = {...own.values};
    for (final key in {...before.values.keys, ...after.values.keys}) {
      final value = after.values[key];
      if (jsonEncode(before.values[key]) == jsonEncode(value)) continue;
      if (value == null) {
        values.remove(key);
        continue;
      }
      values[key] = value;
      // A variant keeps a value under its effect switched on, as
      // [Material2DFile.withValue] does.
      final dot = key.indexOf('.');
      final id = dot < 0 ? key : key.substring(0, dot);
      if (after.isOn(id)) effects[id] = true;
    }
    return Material2DFile(
      kind: own.kind,
      parent: own.parent,
      effects: effects,
      values: values,
    );
  }

  /// Changes the material as it draws — a variant over its parents — as
  /// [change] says, as one undo step: what a module adding to the window
  /// edits ([Material2DWorkspaceView.change]), as the 3-D window's do.
  void changeShown(Material2DFile Function(Material2DFile m) change) {
    final before = _resolved(material);
    edit(_withEdit(before, change(before)));
  }

  /// [changeShown] without an undo step: a [preview].
  void previewShown(Material2DFile Function(Material2DFile m) change) {
    if (!_loaded) return;
    final before = _resolved(material);
    final after = _withEdit(before, change(before));
    preview((_) => after);
  }

  /// Shows [change] without making an undo step: a value being dragged or
  /// picked. [change] or [edit] puts it in for good; [endPreview] lets it
  /// go.
  ///
  /// Without [rebuild] only the preview is drawn again, not the window: for
  /// a slider, which shows the value dragged to itself — rebuilding the
  /// whole window at every step of a drag was most of its time.
  void preview(
    Material2DFile Function(Material2DFile m) change, {
    bool rebuild = true,
  }) {
    if (!_loaded) return;
    final live = change(material);
    if (rebuild) {
      setState(() => _live = live);
    } else {
      _live = live;
    }
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

  /// Writes the file, whole or not at all; whether it went through. Never
  /// when the file was not read ([load]): what is shown then is no more
  /// than defaults.
  Future<bool> save() async {
    if (!_loaded) return false;
    final current = material;
    if (_readOnly(widget.path) case final why?) {
      if (mounted) setState(() => _error = why);
      return false;
    }
    try {
      await ProjectFiles.writeString(_file.path, current.encode());
      _saved = current;
      // Read already: what went wrong before was a save's.
      if (mounted) setState(() => _error = null);
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
    if (!_loaded || !m.isVariant || own == 0) return false;
    if (_readOnly(m.parent) case final why?) {
      setState(() => _error = why);
      return false;
    }
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
    final file = _fileOf(m.parent);
    try {
      var parent = Material2DFile.parse(await file.readAsString());
      for (final MapEntry(:key, :value) in m.effects.entries) {
        parent = parent.withEffect(key, value);
      }
      for (final MapEntry(:key, :value) in m.values.entries) {
        parent = parent.withValue(key, value);
      }
      // Whole or not at all: every variant of it is drawn from it.
      await ProjectFiles.writeString(file.path, parent.encode());
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
      return false;
    }
    _parents.remove(m.parent);
    _shownFor = null;
    widget.workspace.reloadAssets?.call(m.parent);
    if (!mounted) return true;
    stage.library.reload(m.parent);
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
    return engine?.context.material2DLibrary;
  }

  // The open scene draws what is edited — a value being dragged too —
  // until it is saved or put back. Not once the window went: it put the
  // file back as it closed.
  void _syncScene() {
    if (!mounted) return;
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
    final next = at?.clamp(0.02, 0.98).toDouble();
    if (next == _compareAt) return;
    final turned = (next == null) != (_compareAt == null);
    _compareAt = next;
    if (turned) {
      // On or off: the toolbar's button says so.
      setState(() {});
    } else {
      // The line dragged: only the preview follows it.
      _compareLine.value++;
    }
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

  /// Opens the light's settings over the preview, or closes them.
  void setLightSettingsOpen(bool open) =>
      setState(() => _lightSettingsOpen = open);

  final ValueNotifier<int> _lightMoved = ValueNotifier(0);

  /// Where a light preset puts the light, and how high: from the top
  /// left, from above, grazing from the side, from behind the top right.
  static const Map<String, (Offset, double)> lightPresets = {
    'Top left': (Offset(0.3, 0.3), 0.2),
    'Above': (Offset(0.5, 0.42), 0.6),
    'Side': (Offset(0.06, 0.5), 0.06),
    'Rim': (Offset(0.86, 0.14), 0.08),
  };

  // The panels' widths changed: the window is laid out again, not built.
  final ValueNotifier<int> _widths = ValueNotifier(0);

  String? _generateNote;

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
    _lightMoved.dispose();
    _compareLine.dispose();
    _framing.dispose();
    _widths.dispose();
    _effectsScroll.dispose();
    _clock.dispose();
    _drawnScale.dispose();
    _extensionView.dispose();
    super.dispose();
  }

  /// The preview's keys, as its shortcut list says them: Cmd for Ctrl on
  /// macOS.
  static String get shortcuts =>
      'F  fit      1 / 2 / 4  zoom      + / −  zoom in, out\n'
      'Wheel  zoom      Drag  pan      Double-click  fit\n'
      'C  compare      Hold Space  without the material\n'
      'B  background      L  light      N  normals\n'
      'T  tile 3 × 3      P  play or pause\n'
      '${EditorKeys.withPrimary('S')}  save      '
      '${EditorKeys.withPrimary('Z')} / ${EditorKeys.withPrimary('Y')}  undo, '
      'redo';

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
              onSave: _loaded ? save : null,
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
            Expanded(child: _panels(_fields(), _previewPane(), _effects())),
          ],
        ),
      ),
    );
  }

  static String _nameOf(String path) =>
      path.substring(path.lastIndexOf('/') + 1);

  static const Map<String, String> _groups = {
    'color': 'Colour',
    'edges': 'Edges',
    'motion': 'Motion',
    'light': 'Light',
    'screen': 'The frame',
  };

  /// The groups [kind]'s effects are shown in, in order.
  static List<String> groupsOf(Material2DKind kind) =>
      kind == Material2DKind.screen
      ? const ['screen', 'color']
      : const ['color', 'edges', 'motion', 'light'];

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
      folded: _folds.isFolded(fold),
      onFold: (folded) => setState(() => _folds.set(fold, folded)),
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

  static String _title(String name) {
    final spaced = name.replaceAllMapped(
      RegExp('[A-Z]'),
      (c) => ' ${c[0]!.toLowerCase()}',
    );
    return spaced[0].toUpperCase() + spaced.substring(1);
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
      _state.changeShown(change);

  @override
  void preview(Material2DFile Function(Material2DFile m) change) =>
      _state.previewShown(change);

  @override
  void endPreview() => _state.endPreview();
}
