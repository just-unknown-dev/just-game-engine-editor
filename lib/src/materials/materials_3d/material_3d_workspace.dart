import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart' show GpuSurface;

import '../map_pictures.dart';
import 'material_3d_pictures.dart';
import 'material_3d_preset.dart';
import 'material_3d_preview.dart';
import '../material_window_kit.dart';

part 'material_3d_workspace_fields.dart';
part 'material_3d_workspace_preview.dart';

/// A material file's look (`*.material.json`), with a live preview to turn:
/// the workspace a material opens in.
///
/// It looks and works as the 2-D material window does. Its values are in
/// cards in a panel on the left — Surface, Transparency, Maps (each with a
/// picture of its image), Layers, and how the maps are laid out — each
/// with what it holds, a reset and a fold, under presets to start from. A
/// slider being dragged or a colour being picked shows in the preview at
/// once and becomes one undo step when let go. The preview shows the
/// material on a ball, a cube, a cylinder, a ring or a floor tile, in a
/// studio, a sky's light or the open scene's own, in front of that sky or
/// a plain dark or light background; it zooms, and compares the material
/// with a plain grey one.
///
/// A variant (a material with a parent) shows its parent's values where it
/// has none of its own; whatever is changed becomes its own.
///
/// Its edits have an undo of their own; Save writes the file, and
/// everything drawn with it changes.
class Material3DWorkspace extends StatefulWidget {
  /// The workspace for the material at [path] under [root].
  const Material3DWorkspace({
    super.key,
    required this.path,
    required this.root,
    required this.pictures,
    required this.workspace,
    this.maps,
    this.changes,
    this.loadOnStart = true,
  });

  /// The material, project-relative.
  final String path;

  /// The project folder.
  final String root;

  /// Draws the preview, with the renderer the Assets dock's pictures use.
  final Material3DPictures pictures;

  /// The pictures of the maps' images; its own when null.
  final MapPictures? maps;

  /// Paths of files that changed on disk, as the editor hears of them: a
  /// parent, a map or a layer read again.
  final Stream<String>? changes;

  /// The editor's handle on the workspace.
  final WorkspaceContext workspace;

  /// Whether it reads the file as it opens; a test calls
  /// [Material3DWorkspaceState.load] itself instead.
  final bool loadOnStart;

  @override
  State<Material3DWorkspace> createState() => Material3DWorkspaceState();
}

/// The state of a [Material3DWorkspace]; public for tests.
class Material3DWorkspaceState extends State<Material3DWorkspace> {
  Material3DFile _saved = const Material3DFile();
  final List<Material3DFile> _history = [const Material3DFile()];
  int _at = 0;
  Object? _error;
  bool _loaded = false;

  /// The material as it will be saved: for a variant, its own values.
  Material3DFile get material => _history[_at];

  /// Whether it differs from the file.
  bool get dirty => material != _saved;

  // What is shown: the material over its parents, worked out once per
  // version of it.
  Material3DFile? _shownFor;
  Material3DFile _shown = const Material3DFile();
  List<String> _chainProblems = const [];
  final Map<String, Material3DFile?> _parents = {};

  /// What the fields and the preview show: [material], and for a variant
  /// its parents' values where it has none of its own.
  Material3DFile get shown {
    final m = material;
    if (!identical(_shownFor, m)) {
      _shownFor = m;
      if (!m.isVariant) {
        _shown = m;
        _chainProblems = const [];
      } else {
        final resolved = MaterialChain.resolve3D(
          widget.path,
          (p) => p == widget.path ? m : _parent(p),
        );
        _shown = resolved.value;
        _chainProblems = resolved.problems;
      }
    }
    return _shown;
  }

  Material3DFile? _parent(String path) => _parents.putIfAbsent(path, () {
    try {
      return Material3DFile.parse(_fileOf(path).readAsStringSync());
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

  // A value being dragged or picked: drawn, not yet an undo step.
  Material3DFile? _live;

  /// The preview's shape and light, kept for the next material opened.
  static PreviewShape _lastShape = PreviewShape.ball;
  static PreviewLighting _lastLighting = PreviewLighting.studio;

  /// What the preview shows the material on.
  PreviewShape get shape => _shape;
  PreviewShape _shape = _lastShape;

  /// The light the preview is drawn in.
  PreviewLighting get lighting => _lighting;
  PreviewLighting _lighting = _lastLighting;

  ui.Image? _image;
  // Bumped when a picture is drawn: what shows it listens.
  final ValueNotifier<int> _pictures = ValueNotifier(0);
  GpuSurface? _surface;
  bool _rendering = false, _again = false, _noGpu = false;
  Object? _drawError;
  // A little way back, so the whole shape shows with room round it.
  static const double _startZoom = 0.85;
  static const double _startYaw = -0.6, _startPitch = -0.45;
  double _yaw = _startYaw, _pitch = _startPitch, _zoom = _startZoom;
  Size _size = const Size(360, 360);
  ui.Image? _plainImage;
  GpuSurface? _plainSurface;

  /// What Compare shows on the other side of its line: a plain grey.
  static const Material3DFile plain = Material3DFile(
    color: 0xFF5F646B,
    roughness: 0.6,
  );

  /// What the preview is drawn in front of, kept for the next material.
  static PreviewBackdrop _lastBackdrop = PreviewBackdrop.sky;
  PreviewBackdrop get backdrop => _backdrop;
  PreviewBackdrop _backdrop = _lastBackdrop;

  /// Where the compare line is, a share of the preview across: a plain
  /// grey material to its left, this one to its right. Null when not
  /// comparing.
  double? get compareAt => _compareAt;
  double? _compareAt;

  // The compare line moved: the preview is built again, not the window.
  final ValueNotifier<int> _compareLine = ValueNotifier(0);

  /// Whether Space is held: a plain grey material drawn in its place.
  bool get holdingPlain => _holdingPlain;
  bool _holdingPlain = false;

  /// The material's panel's width, kept for the next material.
  static double _lastPanelWidth = 360;
  double get panelWidth => _panelWidth;
  double _panelWidth = _lastPanelWidth;
  late final MapPictures _maps = widget.maps ?? MapPictures(root: widget.root);

  /// Which cards are folded: the editor's, kept for the next material.
  late final MaterialCardFolds _folds = MaterialCardFolds.of(
    widget.workspace.scope,
  );
  StreamSubscription<String>? _changes;

  File get _file => _fileOf(widget.path);

  @override
  void initState() {
    super.initState();
    widget.workspace.setCloseGuard?.call(
      () async => mayLeaveUnsaved(context, dirty: dirty, save: save),
    );
    _changes = widget.changes?.listen(_changed);
    if (widget.loadOnStart) load();
  }

  void _changed(String path) {
    if (path == widget.path) return;
    final parent = _parents.containsKey(path);
    _parents.remove(path);
    _maps.forget(path);
    if (parent) _shownFor = null;
    if (mounted) setState(() {});
    _redraw();
  }

  /// What the file holds that a material does not — a note added by hand,
  /// another tool's key — kept as it is and written back by [save].
  Map<String, Object?> _extra = const {};

  /// The keys a material file has: its values, its version and its parent.
  static final Set<String> _known = {
    ...Material3DFile.keys,
    'formatVersion',
    'parent',
  };

  /// What of [json] is not a material's: kept, not dropped, by a save.
  static Map<String, Object?> _extraOf(Map<Object?, Object?> json) => {
    for (final MapEntry(:key, :value) in json.entries)
      if (key is String && !_known.contains(key)) key: value,
  };

  /// [m] as saved, with [extra] after its own keys.
  static String _encode(Material3DFile m, Map<String, Object?> extra) =>
      extra.isEmpty
      ? m.encode()
      : '${const JsonEncoder.withIndent('  ').convert({...m.toJson(), ...extra})}\n';

  /// Reads the file and draws the first preview.
  Future<void> load() async {
    try {
      final text = await _file.readAsString();
      final file = Material3DFile.parse(text);
      final extra = _extraOf(jsonDecode(text) as Map);
      if (!mounted) return;
      setState(() {
        _extra = extra;
        _saved = file;
        _history
          ..clear()
          ..add(file);
        _at = 0;
        _loaded = true;
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
    _redraw();
  }

  /// Puts [next] in as the material, one undo step. Nothing is edited until
  /// the file is read: one that could not be (broken JSON, a newer format)
  /// is never written over with the defaults shown meanwhile.
  void edit(Material3DFile next) {
    if (!_loaded) return;
    _live = null;
    if (next == material) {
      _redraw();
      return;
    }
    setState(() {
      _history
        ..removeRange(_at + 1, _history.length)
        ..add(next);
      _at = _history.length - 1;
    });
    _redraw();
  }

  /// Changes what is [shown] as [change] says, as one undo step; on a
  /// variant every value it changes becomes the variant's own.
  void change(Material3DFile Function(Material3DFile m) change) {
    final before = shown;
    edit(material.withEdit(change(before), shown: before));
  }

  /// Shows [change] in the preview without making an undo step: a value
  /// being dragged or picked. [change] or [edit] puts it in for good;
  /// [endPreview] lets it go.
  ///
  /// Without [rebuild] only the preview is drawn again, not the window: for
  /// a slider, which shows the value dragged to itself.
  void preview(
    Material3DFile Function(Material3DFile m) change, {
    bool rebuild = true,
  }) {
    if (!_loaded) return;
    final live = change(shown);
    if (rebuild) {
      setState(() => _live = live);
    } else {
      _live = live;
    }
    _redraw();
  }

  /// Stops showing a [preview].
  void endPreview() {
    if (_live == null) return;
    setState(() => _live = null);
    _redraw();
  }

  /// What the preview draws: a [preview], or what is [shown].
  Material3DFile get drawn => _live ?? shown;

  /// What modules adding to the window see of it ([WorkspaceIds.material3D]).
  Material3DWorkspaceView get view => _extensionView;
  late final _Material3DView _extensionView = _Material3DView(this);

  /// Steps back through the edits.
  void undo() {
    if (_at == 0) return;
    setState(() {
      _live = null;
      _at--;
    });
    _redraw();
  }

  /// Steps forward again.
  void redo() {
    if (_at >= _history.length - 1) return;
    setState(() {
      _live = null;
      _at++;
    });
    _redraw();
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
      await ProjectFiles.writeString(_file.path, _encode(current, _extra));
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

  /// In a variant: [key] taken from the parent again, as one undo step.
  void revert(String key) => edit(material.withoutOverride(key));

  /// In a variant: everything taken from the parent again, as one undo
  /// step.
  void revertAll() => edit(material.copyWith(overrides: const {}));

  /// In a variant: its own values written into its parent's file — so
  /// the parent, and everything made from it, has them — and then taken
  /// from the parent here (one undo step; the parent's file is not undone
  /// with it). Asks first unless [confirm] is false. Whether it went
  /// through.
  Future<bool> applyToParent({bool confirm = true}) async {
    final m = material;
    if (!_loaded || !m.isVariant || m.overrides.isEmpty) return false;
    if (_readOnly(m.parent) case final why?) {
      setState(() => _error = why);
      return false;
    }
    if (confirm &&
        !await showEditorConfirm(
          context,
          title: 'Apply to ${_nameOf(m.parent)}?',
          message:
              'Writes ${m.overrides.length} of this variant\'s values into '
              '${m.parent} now — that is not undone here — and everything made '
              'from it changes. This variant then takes them from it.',
          confirmLabel: 'Apply',
          danger: false,
        )) {
      return false;
    }
    final parent = _fileOf(m.parent);
    try {
      final theirs = jsonDecode(await parent.readAsString()) as Map;
      final mine = m.toJson()
        ..remove('parent')
        ..remove('formatVersion');
      final next = Material3DFile.fromJson({...theirs, ...mine});
      // Whole or not at all: every variant of it is drawn from it. What of
      // it is not a material's is kept.
      await ProjectFiles.writeString(
        parent.path,
        _encode(next, _extraOf(theirs)),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
      return false;
    }
    _parents.remove(m.parent);
    _shownFor = null;
    widget.workspace.reloadAssets?.call(m.parent);
    if (mounted) edit(m.copyWith(overrides: const {}));
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

  /// The materials the open scene is drawn with, when its 3-D renderer is
  /// running.
  Material3DLibrary? get sceneMaterials {
    final graphics = widget.workspace.scope.engine?.graphics3D;
    if (graphics == null || !graphics.isStarted) return null;
    return graphics.sceneRenderer.materials;
  }

  // The open scene draws what is edited — a value being dragged too —
  // until it is saved or put back. Not once the window went: it put the
  // file back as it closed.
  void _syncScene() {
    if (!mounted) return;
    final library = sceneMaterials;
    if (library == null) return;
    final live = _live;
    final source = live == null
        ? material
        : material.withEdit(live, shown: shown);
    if (!_liveInScene || !_loaded || source == _saved) {
      library.endPreview(widget.path);
    } else {
      library.preview(widget.path, source);
    }
  }

  /// Shows the material on [shape].
  void setShape(PreviewShape shape) {
    if (shape == _shape) return;
    setState(() => _shape = _lastShape = shape);
    _redraw();
  }

  /// Draws the preview in [lighting].
  void setLighting(PreviewLighting lighting) {
    if (lighting == _lighting) return;
    setState(() => _lighting = _lastLighting = lighting);
    _redraw();
  }

  /// The open scene's drawing, when its 3-D renderer is running: what
  /// [PreviewLighting.scene] lights the preview with.
  Render3DScene? get sceneLighting {
    final graphics = widget.workspace.scope.engine?.graphics3D;
    if (graphics == null || !graphics.isStarted) return null;
    return graphics.sceneRenderer.scene;
  }

  Future<void> _redraw() async {
    // A late call (a frame's callback, a load) after the window went.
    if (!mounted) return;
    _extensionView.changed();
    _syncScene();
    if (_rendering) {
      _again = true;
      return;
    }
    _rendering = true;
    try {
      do {
        _again = false;
        final w = math.max(16, _size.width.round());
        final h = math.max(16, _size.height.round());
        final Renderer3D? renderer;
        try {
          renderer = await widget.pictures.renderer();
        } on Object catch (error) {
          // The renderer could not start (its shaders, the driver): no
          // preview, and the chips say why — every redraw would only throw
          // the same again.
          if (mounted) {
            setState(() {
              _noGpu = true;
              _drawError = error;
            });
          }
          return;
        }
        if (renderer == null) {
          if (mounted) setState(() => _noGpu = true);
          return;
        }
        if (!mounted) return;
        final surface = _surface ??= renderer.device.createSurface(w, h);
        Future<ui.Image?> draw(Material3DFile file, GpuSurface into) =>
            widget.pictures.render(
              file,
              width: w,
              height: h,
              yaw: _yaw,
              pitch: _pitch,
              zoom: _zoom,
              shape: _shape,
              lighting: _lighting,
              scene: sceneLighting,
              background: _backdrop.color,
              into: into,
            );
        ui.Image? image, plainImage;
        Object? problem;
        try {
          image = await draw(drawn, surface);
          // Compare's other side: the same, in a plain grey.
          if (_comparing) {
            plainImage = await draw(
              plain,
              _plainSurface ??= renderer.device.createSurface(w, h),
            );
          }
        } on Object catch (error) {
          // A map or layer that can't be read: say so, keep the last
          // picture.
          problem = error;
        }
        if (!mounted) {
          image?.dispose();
          plainImage?.dispose();
          return;
        }
        if (image != null) {
          _image?.dispose();
          _image = image;
        }
        if (plainImage != null) {
          _plainImage?.dispose();
          _plainImage = plainImage;
        }
        // A new picture is shown by the picture alone — the window was
        // built again for each, a turn or a drag at a time — and the chips
        // only when what went wrong did.
        if ('$problem' != '$_drawError') {
          setState(() => _drawError = problem);
        } else {
          _pictures.value++;
        }
      } while (_again && mounted);
    } finally {
      _rendering = false;
    }
  }

  @override
  void dispose() {
    // Put back: the scene draws the file again.
    sceneMaterials?.endPreview(widget.path);
    _changes?.cancel();
    if (widget.maps == null) _maps.dispose();
    // The maps drawn at full size here: the dock keeps its own, smaller.
    widget.pictures.releaseFullSizeMaps();
    _image?.dispose();
    _plainImage?.dispose();
    _pictures.dispose();
    _compareLine.dispose();
    _widths.dispose();
    _framing.dispose();
    _resized?.cancel();
    _extensionView.dispose();
    super.dispose();
  }

  /// Draws the preview in front of [backdrop].
  void setBackdrop(PreviewBackdrop backdrop) {
    if (backdrop == _backdrop) return;
    setState(() => _backdrop = _lastBackdrop = backdrop);
    _redraw();
  }

  /// Compares the material with a plain grey one — a line across the
  /// preview at [at] (a share of it across), the plain one to its left —
  /// or stops.
  void setCompare(double? at) {
    final was = _comparing;
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
    if (_comparing && !was) _redraw();
  }

  /// Draws a plain grey material in its place while Space is held.
  void setHoldingPlain(bool on) {
    if (on == _holdingPlain) return;
    final was = _comparing;
    setState(() => _holdingPlain = on);
    if (_comparing && !was) _redraw();
  }

  bool get _comparing => _compareAt != null || _holdingPlain;

  /// How close the preview is, as a share of how close it starts.
  double get zoom => _zoom / _startZoom;

  /// Whether the preview is turned and zoomed as it started.
  bool get atStart =>
      _yaw == _startYaw && _pitch == _startPitch && _zoom == _startZoom;

  /// A step closer (+1) or further (-1).
  void zoomBy(int steps) => _zoomTo(_zoom * math.pow(1.25, steps));

  void _zoomTo(num zoom) {
    final next = zoom.clamp(0.5, 3.0).toDouble();
    if (next == _zoom) return;
    _zoom = next;
    _turned();
  }

  /// Turns and zooms the preview as it started.
  void fit() {
    _yaw = _startYaw;
    _pitch = _startPitch;
    _zoom = _startZoom;
    _turned();
  }

  // The preview was turned or zoomed: drawn again, and the zoom controls
  // say so — the window is not built again for each turn of the wheel.
  void _turned() {
    _framing.value++;
    _redraw();
  }

  final ValueNotifier<int> _framing = ValueNotifier(0);

  /// How long the preview's size must stay the same before it is drawn at
  /// it again.
  static const Duration resizeSettle = Duration(milliseconds: 150);
  Timer? _resized;

  /// Sizes the material's panel [width] logical pixels wide.
  void setPanelWidth(double width) {
    _panelWidth = _lastPanelWidth = width.clamp(260, 640).toDouble();
    _widths.value++;
  }

  // The panel's width changed: the window is laid out again, not built.
  final ValueNotifier<int> _widths = ValueNotifier(0);

  /// The preview's keys, as its shortcut list says them: Cmd for Ctrl on
  /// macOS.
  static String get shortcuts =>
      'F  face it again      + / −  zoom in, out\n'
      'Wheel  zoom      Drag  turn      Double-click  face it again\n'
      'C  compare      Hold Space  without the material\n'
      'B  background\n'
      '${EditorKeys.withPrimary('S')}  save      '
      '${EditorKeys.withPrimary('Z')} / ${EditorKeys.withPrimary('Y')}  undo, '
      'redo';

  KeyEventResult _onKey(KeyEvent event) {
    // Space held shows a plain grey material in its place.
    if (event.logicalKey == LogicalKeyboardKey.space &&
        !WorkspaceKeyScope.isTyping) {
      if (event is KeyDownEvent) setHoldingPlain(true);
      if (event is KeyUpEvent) setHoldingPlain(false);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Ctrl is Cmd on macOS.
    final ctrl = EditorKeys.primaryPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (!ctrl) {
      if (WorkspaceKeyScope.isTyping) return KeyEventResult.ignored;
      // A chord is not a bare key: Alt+C, or Ctrl+C on a Mac, is not C.
      if (HardwareKeyboard.instance.isAltPressed || EditorKeys.otherPressed) {
        return KeyEventResult.ignored;
      }
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyF:
          fit();
        case LogicalKeyboardKey.equal:
        case LogicalKeyboardKey.numpadAdd:
          zoomBy(1);
        case LogicalKeyboardKey.minus:
        case LogicalKeyboardKey.numpadSubtract:
          zoomBy(-1);
        case LogicalKeyboardKey.keyC:
          setCompare(_compareAt == null ? 0.5 : null);
        case LogicalKeyboardKey.keyB:
          const all = PreviewBackdrop.values;
          setBackdrop(all[(_backdrop.index + 1) % all.length]);
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
    return WorkspaceKeyScope(
      onKey: _onKey,
      child: ColoredBox(
        color: EditorTheme.panelBg,
        child: Column(
          children: [
            WorkspaceHeader(
              icon: Icons.texture,
              title: 'Material',
              file: name,
              dirty: dirty,
              onSave: _loaded ? save : null,
              onUndo: _at > 0 ? undo : null,
              onRedo: _at < _history.length - 1 ? redo : null,
              tools: [
                Tooltip(
                  message:
                      'Unsaved edits show in the open scene as they are made',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EditorToggle(
                        value: _liveInScene,
                        label: 'In the scene',
                        onChanged: setLiveInScene,
                      ),
                      const SizedBox(width: 4),
                      Text('In the scene', style: _label),
                    ],
                  ),
                ),
              ],
              fullScreen: widget.workspace.fullScreen,
              onToggleFullScreen: widget.workspace.onToggleFullScreen,
              onClose: widget.workspace.onClose,
            ),
            Expanded(child: _panels(_fields(), _previewPane())),
          ],
        ),
      ),
    );
  }

  // The panel and the preview side by side, the panel as wide as it is
  // dragged to. A drag builds only this row: both are the ones the window
  // was built with, and are laid out again.
  Widget _panels(Widget fields, Widget preview) => ValueListenableBuilder<int>(
    valueListenable: _widths,
    builder: (context, _, _) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: _panelWidth, child: fields),
        PanelResizeHandle(onDrag: (dx) => setPanelWidth(_panelWidth + dx)),
        Expanded(child: preview),
      ],
    ),
  );

  static Material3DFile _withLayer(Material3DFile m, int i, String path) {
    final layers = [...m.layers];
    while (layers.length <= i) {
      layers.add('');
    }
    layers[i] = path;
    while (layers.isNotEmpty && layers.last.isEmpty) {
      layers.removeLast();
    }
    return m.copyWith(layers: layers);
  }

  static String _nameOf(String path) =>
      path.substring(path.lastIndexOf('/') + 1);

  /// The keys of the material each card holds, by card: what its reset
  /// and, in a variant, its revert take back.
  static const Map<String, List<String>> cardKeys = {
    'surface': [
      'color',
      'metallic',
      'roughness',
      'emission',
      'emissionStrength',
      'unlit',
      'doubleSided',
    ],
    'transparency': ['alpha', 'opacity', 'alphaCutoff'],
    'maps': [
      'colorMap',
      'metalRoughMap',
      'normalMap',
      'normalScale',
      'occlusionMap',
      'occlusionStrength',
      'emissionMap',
    ],
    'layers': ['layers'],
    'layout': ['uv', 'tiling', 'offset', 'rotation'],
  };

  // Each card's name, and a line on what it holds.
  static const Map<String, (String, String)> _cardText = {
    'surface': (
      'Surface',
      'Its colour, how metal and how rough it is, and its glow.',
    ),
    'transparency': (
      'Transparency',
      "Solid, cut out where the colour map's alpha is low, or see-through.",
    ),
    'maps': (
      'Maps',
      'Images for its colour, its metal and roughness, its bumps, the shade '
          'in its creases and its glow.',
    ),
    'layers': (
      'Layers',
      "Up to four materials blended by a mesh's vertex red, green, blue and "
          "alpha; each layer's colour map tiled per metre as that layer says.",
    ),
    'layout': (
      'Laid out',
      'How the maps lie on the mesh — by its own coordinates, per metre or '
          'from the world — repeated, shifted and turned.',
    ),
  };

  Widget _card(String card, List<Widget> rows) {
    final (title, description) = _cardText[card]!;
    final fold = '3d.$card';
    final changed = cardChanged(card);
    return MaterialCard(
      title: title,
      description: description,
      folded: _folds.isFolded(fold),
      onFold: (folded) => setState(() => _folds.set(fold, folded)),
      actions: [
        EditorIconButton(
          icon: Icons.restart_alt,
          tooltip: material.isVariant
              ? "Back to its parent's values"
              : 'Back to its defaults',
          iconSize: 14,
          size: 22,
          onTap: changed ? () => resetCard(card) : null,
        ),
        if (material.isVariant)
          SizedBox(
            width: 24,
            child: changed
                ? EditorIconButton(
                    icon: Icons.undo,
                    tooltip: "Its own: back to the parent's",
                    iconSize: 14,
                    size: 22,
                    onTap: () => resetCard(card),
                  )
                : Tooltip(
                    message: "The parent's",
                    child: Icon(
                      Icons.link,
                      size: 12,
                      color: EditorTheme.textMuted,
                    ),
                  ),
          ),
      ],
      children: rows,
    );
  }

  // ── Preview ───────────────────────────────────────────────────────────

  static const Map<PreviewShape, (IconData, String)> _shapeLooks = {
    PreviewShape.ball: (
      Icons.circle_outlined,
      'On a ball: every angle at once',
    ),
    PreviewShape.cube: (
      Icons.view_in_ar_outlined,
      'On a cube: flat faces and edges',
    ),
    PreviewShape.cylinder: (
      Icons.crop_portrait,
      'On a cylinder: a curve one way, flat the other',
    ),
    PreviewShape.torus: (Icons.donut_large, 'On a ring'),
    PreviewShape.plane: (
      Icons.crop_landscape,
      'On a floor tile: how the maps tile and lie',
    ),
  };
}

// What modules adding to the window see of it.
final class _Material3DView implements Material3DWorkspaceView {
  _Material3DView(this._state);

  final Material3DWorkspaceState _state;
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
  String get workspaceId => WorkspaceIds.material3D;

  @override
  String? get path => _state.widget.path;

  @override
  EditorScope get scope => _state.widget.workspace.scope;

  @override
  Listenable get changes => _changes;

  @override
  Material3DFile get material => _state.material;

  @override
  Material3DFile get shown => _state.drawn;

  @override
  void change(Material3DFile Function(Material3DFile m) change) =>
      _state.change(change);

  @override
  void preview(Material3DFile Function(Material3DFile m) change) =>
      _state.preview(change);

  @override
  void endPreview() => _state.endPreview();
}

// One side of the compare line at [at] (a share across) of what it clips.
class _Side extends CustomClipper<Rect> {
  _Side(this.at, {required this.left});

  final double at;
  final bool left;

  @override
  Rect getClip(Size size) {
    final x = size.width * at;
    return left
        ? Rect.fromLTWH(0, 0, x, size.height)
        : Rect.fromLTWH(x, 0, size.width - x, size.height);
  }

  @override
  bool shouldReclip(_Side old) => old.at != at || old.left != left;
}
