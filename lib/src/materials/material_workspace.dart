import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';

import 'map_pictures.dart';
import 'material_pictures.dart';
import 'material_presets.dart';
import 'material_preview.dart';
import 'material_window_kit.dart';

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
class MaterialWorkspace extends StatefulWidget {
  /// The workspace for the material at [path] under [root].
  const MaterialWorkspace({
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
  final MaterialPictures pictures;

  /// The pictures of the maps' images; its own when null.
  final MapPictures? maps;

  /// Paths of files that changed on disk, as the editor hears of them: a
  /// parent, a map or a layer read again.
  final Stream<String>? changes;

  /// The editor's handle on the workspace.
  final WorkspaceContext workspace;

  /// Whether it reads the file as it opens; a test calls
  /// [MaterialWorkspaceState.load] itself instead.
  final bool loadOnStart;

  @override
  State<MaterialWorkspace> createState() => MaterialWorkspaceState();
}

/// The state of a [MaterialWorkspace]; public for tests.
class MaterialWorkspaceState extends State<MaterialWorkspace> {
  MaterialFile _saved = const MaterialFile();
  final List<MaterialFile> _history = [const MaterialFile()];
  int _at = 0;
  Object? _error;
  bool _loaded = false;

  /// The material as it will be saved: for a variant, its own values.
  MaterialFile get material => _history[_at];

  /// Whether it differs from the file.
  bool get dirty => material != _saved;

  // What is shown: the material over its parents, worked out once per
  // version of it.
  MaterialFile? _shownFor;
  MaterialFile _shown = const MaterialFile();
  List<String> _chainProblems = const [];
  final Map<String, MaterialFile?> _parents = {};

  /// What the fields and the preview show: [material], and for a variant
  /// its parents' values where it has none of its own.
  MaterialFile get shown {
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

  MaterialFile? _parent(String path) => _parents.putIfAbsent(path, () {
    try {
      return MaterialFile.parse(
        File('${widget.root}/$path').readAsStringSync(),
      );
    } on Object {
      return null;
    }
  });

  // A value being dragged or picked: drawn, not yet an undo step.
  MaterialFile? _live;

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
  static const MaterialFile plain = MaterialFile(
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

  /// Whether Space is held: a plain grey material drawn in its place.
  bool get holdingPlain => _holdingPlain;
  bool _holdingPlain = false;

  /// The material's panel's width, kept for the next material.
  static double _lastPanelWidth = 360;
  double get panelWidth => _panelWidth;
  double _panelWidth = _lastPanelWidth;
  late final MapPictures _maps = widget.maps ?? MapPictures(root: widget.root);
  StreamSubscription<String>? _changes;

  File get _file => File('${widget.root}/${widget.path}');

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

  /// Reads the file and draws the first preview.
  Future<void> load() async {
    try {
      final file = MaterialFile.parse(await _file.readAsString());
      if (!mounted) return;
      setState(() {
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

  /// Puts [next] in as the material, one undo step.
  void edit(MaterialFile next) {
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
  void change(MaterialFile Function(MaterialFile m) change) {
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
    MaterialFile Function(MaterialFile m) change, {
    bool rebuild = true,
  }) {
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
  MaterialFile get drawn => _live ?? shown;

  /// What modules adding to the window see of it ([WorkspaceIds.material]).
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
    if (!m.isVariant || m.overrides.isEmpty) return false;
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
    final parent = File('${widget.root}/${m.parent}');
    try {
      final theirs = jsonDecode(await parent.readAsString()) as Map;
      final mine = m.toJson()
        ..remove('parent')
        ..remove('formatVersion');
      final next = MaterialFile.fromJson({...theirs, ...mine});
      await parent.writeAsString(next.encode());
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
      return false;
    }
    _parents.remove(m.parent);
    _shownFor = null;
    widget.workspace.reloadAssets?.call(m.parent);
    edit(m.copyWith(overrides: const {}));
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
  MaterialLibrary? get sceneMaterials {
    final graphics = widget.workspace.scope.engine?.graphics3D;
    if (graphics == null || !graphics.isStarted) return null;
    return graphics.sceneRenderer.materials;
  }

  // The open scene draws what is edited — a value being dragged too —
  // until it is saved or put back.
  void _syncScene() {
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
  RenderScene? get sceneLighting {
    final graphics = widget.workspace.scope.engine?.graphics3D;
    if (graphics == null || !graphics.isStarted) return null;
    return graphics.sceneRenderer.scene;
  }

  Future<void> _redraw() async {
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
        final renderer = await widget.pictures.renderer();
        if (renderer == null) {
          if (mounted) setState(() => _noGpu = true);
          return;
        }
        if (!mounted) return;
        final surface = _surface ??= renderer.device.createSurface(w, h);
        Future<ui.Image?> draw(MaterialFile file, GpuSurface into) =>
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
              background: _backdrop.colour,
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
    _image?.dispose();
    _plainImage?.dispose();
    _pictures.dispose();
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
    setState(() => _compareAt = at?.clamp(0.02, 0.98).toDouble());
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

  /// The preview's keys, as its shortcut list says them.
  static const String shortcuts =
      'F  face it again      + / −  zoom in, out\n'
      'Wheel  zoom      Drag  turn      Double-click  face it again\n'
      'C  compare      Hold Space  without the material\n'
      'B  background\n'
      'Ctrl+S  save      Ctrl+Z / Ctrl+Y  undo, redo';

  KeyEventResult _onKey(KeyEvent event) {
    // Space held shows a plain grey material in its place.
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
              onSave: save,
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

  // ── Fields ────────────────────────────────────────────────────────────

  TextStyle get _label => TextStyle(color: EditorTheme.textMuted, fontSize: 11);

  Widget _note(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
    child: Text(
      text,
      style: color == null ? _label : TextStyle(color: color, fontSize: 11),
    ),
  );

  /// A field's row: its label, the field, and — in a variant — whether
  /// the value is the variant's own (with a way back to the parent's) or
  /// its parent's. [key] is the material key it edits.
  Widget _row(String label, Widget field, {String? key}) {
    final own = key != null && _isOwn(key);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: InspectorField.labelWidth,
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
          if (key != null && material.isVariant) _inherit(key),
        ],
      ),
    );
  }

  /// Whether [key] is the variant's own value.
  bool _isOwn(String key) =>
      material.isVariant && material.overrides.contains(key);

  /// In a variant: a way back to the parent's [key], or a sign that it is
  /// the parent's.
  Widget _inherit(String key) => SizedBox(
    width: 24,
    child: _isOwn(key)
        ? EditorIconButton(
            icon: Icons.undo,
            tooltip: "Its own: back to the parent's",
            iconSize: 14,
            size: 22,
            onTap: () => revert(key),
          )
        : Tooltip(
            message: "The parent's",
            child: Icon(Icons.link, size: 12, color: EditorTheme.textMuted),
          ),
  );

  Widget _colour(
    String label,
    int argb,
    MaterialFile Function(MaterialFile m, int argb) set, {
    String? key,
  }) => _row(
    key: key,
    label,
    Align(
      alignment: Alignment.centerLeft,
      child: MiniColorField(
        key: ValueKey('$label:$argb'),
        color: Color(argb),
        title: label,
        onPreview: (c) => preview((m) => set(m, c.toARGB32())),
        onPreviewEnd: endPreview,
        onChanged: (c) => change((m) => set(m, c.toARGB32())),
      ),
    ),
  );

  Widget _slider(
    String label,
    double value,
    double max,
    MaterialFile Function(MaterialFile m, double v) set, {
    double min = 0,
    double? step,
    int decimals = 2,
    String unit = '',
    String? key,
  }) => _row(
    key: key,
    label,
    EditorSlider(
      value: value.clamp(min, max).toDouble(),
      min: min,
      max: max,
      step: step ?? (max - min) / 100,
      decimals: decimals,
      unit: unit,
      onChanged: (v) => preview((m) => set(m, v), rebuild: false),
      onChangeEnd: (v) => change((m) => set(m, v)),
    ),
  );

  Widget _number(
    String label,
    double value,
    MaterialFile Function(MaterialFile m, double v) set, {
    bool positive = false,
    String? key,
  }) => _row(
    key: key,
    label,
    MiniNumberField(
      key: ValueKey('$label:$value'),
      value: value,
      fractionDigits: 2,
      onSubmitted: (v) {
        if (!v.isFinite || (positive && v <= 0)) return;
        change((m) => set(m, v));
      },
    ),
  );

  Widget _toggle(
    String label,
    String text,
    bool value,
    MaterialFile Function(MaterialFile m, bool v) set, {
    String? key,
  }) => _row(
    key: key,
    label,
    Row(
      children: [
        EditorToggle(
          value: value,
          label: text,
          onChanged: (v) => change((m) => set(m, v)),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: _label)),
      ],
    ),
  );

  /// A map's slot: its image picked from the project's, its picture and
  /// size beside it, and a way to clear it.
  Widget _map(
    String label,
    String path,
    MaterialFile Function(MaterialFile m, String path) set, {
    String? key,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _padded(
        Row(
          children: [
            Expanded(
              child: AssetRefEditorRow(
                label: label,
                value: path,
                extensions: const ['png', 'jpg', 'jpeg', 'webp'],
                onChanged: (p) => change((m) => set(m, p)),
              ),
            ),
            if (key != null && material.isVariant) _inherit(key),
          ],
        ),
      ),
      if (path.isNotEmpty)
        ValueListenableBuilder<int>(
          valueListenable: _maps.revision,
          builder: (context, _, _) {
            final picture = _maps.peek(path);
            final failed = _maps.failed(path);
            return _slotDetail(
              picture: picture == null
                  ? null
                  : RawImage(image: picture.image, fit: BoxFit.contain),
              text: failed
                  ? "Can't be read"
                  : picture == null
                  ? 'Reading…'
                  : '${picture.width} × ${picture.height}',
              warn: failed,
              onClear: () => change((m) => set(m, '')),
            );
          },
        ),
    ],
  );

  Widget _slotDetail({
    required Widget? picture,
    required String text,
    bool warn = false,
    required VoidCallback onClear,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(
      12 + InspectorField.labelWidth,
      2,
      12,
      4,
    ),
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
          child:
              picture ??
              Icon(
                warn ? Icons.broken_image_outlined : Icons.image_outlined,
                size: 16,
                color: warn ? EditorTheme.warning : EditorTheme.textMuted,
              ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: warn
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

  Widget _padded(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    child: child,
  );

  /// A layer's slot: another material, pictured on its ball.
  Widget _layer(int i, String path) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _padded(
        AssetRefEditorRow(
          label:
              'Layer ${i + 1} (${const ['red', 'green', 'blue', 'alpha'][i]})',
          value: path,
          extensions: const ['material.json'],
          onChanged: (p) => change((m) => _withLayer(m, i, p)),
        ),
      ),
      if (path.isNotEmpty)
        ValueListenableBuilder<int>(
          valueListenable: widget.pictures.revision,
          builder: (context, _, _) {
            final file = File('${widget.root}/$path');
            final there = file.existsSync();
            final image = there
                ? widget.pictures.peek(path, modified: file.lastModifiedSync())
                : null;
            return _slotDetail(
              picture: image == null
                  ? null
                  : RawImage(image: image, fit: BoxFit.contain),
              text: there ? _nameOf(path) : 'Missing',
              warn: !there,
              onClear: () => change((m) => _withLayer(m, i, '')),
            );
          },
        ),
    ],
  );

  static MaterialFile _withLayer(MaterialFile m, int i, String path) {
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

  Widget _variant() {
    final m = material;
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
                      m.overrides.isEmpty
                          ? 'Everything from its parent'
                          : '${m.overrides.length} of its own, the rest from '
                                'its parent',
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
          if (m.overrides.isNotEmpty)
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

  Widget _presets() => _row(
    'Preset',
    EditorDropdown<String>(
      value: null,
      hint: 'Start from…',
      tooltip: 'Sets a few values at once, as one undo step',
      options: [
        for (final p in MaterialPreset.all)
          EditorDropdownOption(value: p.id, label: p.label, detail: p.detail),
      ],
      onChanged: (id) {
        final preset = MaterialPreset.byId(id);
        if (preset != null) change(preset.apply);
      },
    ),
  );

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

  /// Whether the card [card] holds anything but the defaults (in a
  /// variant: anything of its own).
  bool cardChanged(String card) {
    final keys = cardKeys[card]!;
    final m = material;
    if (m.isVariant) return keys.any(m.overrides.contains);
    // Saved, a material keeps only what differs from the defaults.
    final saved = m.toJson();
    return keys.any(saved.containsKey);
  }

  /// The card [card]'s values back to the defaults — in a variant, to its
  /// parent's — as one undo step.
  void resetCard(String card) {
    final keys = cardKeys[card]!;
    final m = material;
    if (m.isVariant) {
      edit(m.copyWith(overrides: {...m.overrides}..removeAll(keys)));
      return;
    }
    edit(
      MaterialFile.fromJson(
        m.toJson()..removeWhere((k, _) => keys.contains(k)),
      ),
    );
  }

  Widget _card(String card, List<Widget> rows) {
    final (title, description) = _cardText[card]!;
    final fold = '3d.$card';
    final changed = cardChanged(card);
    return MaterialCard(
      title: title,
      description: description,
      folded: MaterialCardFolds.isFolded(fold),
      onFold: (folded) => setState(() => MaterialCardFolds.set(fold, folded)),
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

  Widget _fields() {
    final m = _live ?? shown;
    final layered = m.kind == MaterialKind.layered;
    final problems = material.validate();
    return ListView(
      children: [
        if (!_loaded && _error == null) _note('Loading…'),
        if (_error != null) _note('$_error', color: EditorTheme.warning),
        if (material.isVariant) _variant(),
        const SizedBox(height: 6),
        _presets(),
        _row(
          key: 'kind',
          'Kind',
          EditorSegmented<MaterialKind>(
            value: m.kind,
            options: const [
              (MaterialKind.lit, 'Lit'),
              (MaterialKind.layered, 'Layered'),
            ],
            tooltips: const {
              MaterialKind.lit: 'A colour, how metal and how rough, and maps',
              MaterialKind.layered:
                  "Up to four materials blended by a mesh's vertex colours — "
                  'terrain',
            },
            onChanged: (k) => change((x) => x.copyWith(kind: k)),
          ),
        ),
        const SizedBox(height: 4),
        if (!layered) ...[
          _card('surface', [
            _colour(
              'Colour',
              key: 'color',
              m.color,
              (x, v) => x.copyWith(color: v),
            ),
            _slider(
              'Metallic',
              key: 'metallic',
              m.metallic,
              1,
              (x, v) => x.copyWith(metallic: v),
            ),
            _slider(
              'Roughness',
              key: 'roughness',
              m.roughness,
              1,
              (x, v) => x.copyWith(roughness: v),
            ),
            _colour(
              'Glow',
              key: 'emission',
              m.emission,
              (x, v) => x.copyWith(emission: v),
            ),
            _slider(
              'Glow strength',
              key: 'emissionStrength',
              m.emissionStrength,
              20,
              (x, v) => x.copyWith(emissionStrength: v),
            ),
            _toggle(
              'Unlit',
              key: 'unlit',
              'Ignore lights',
              m.unlit,
              (x, v) => x.copyWith(unlit: v),
            ),
            _toggle(
              'Two-sided',
              key: 'doubleSided',
              'Both faces',
              m.doubleSided,
              (x, v) => x.copyWith(doubleSided: v),
            ),
          ]),
          _card('transparency', [
            _row(
              key: 'alpha',
              'Mode',
              EditorSegmented<MaterialAlpha>(
                value: m.alpha,
                options: const [
                  (MaterialAlpha.opaque, 'Opaque'),
                  (MaterialAlpha.cutout, 'Cutout'),
                  (MaterialAlpha.blend, 'Blend'),
                ],
                tooltips: const {
                  MaterialAlpha.opaque: 'Solid: nothing shows through',
                  MaterialAlpha.cutout:
                      "Holes where the colour map's alpha is below the cutoff "
                      '— leaves, fences',
                  MaterialAlpha.blend:
                      'See-through by its opacity — glass, water',
                },
                onChanged: (a) => change((x) => x.copyWith(alpha: a)),
              ),
            ),
            if (m.alpha == MaterialAlpha.cutout)
              _slider(
                'Cutoff',
                key: 'alphaCutoff',
                m.alphaCutoff,
                1,
                (x, v) => x.copyWith(alphaCutoff: v),
              ),
            if (m.alpha == MaterialAlpha.blend)
              _slider(
                'Opacity',
                key: 'opacity',
                m.opacity,
                1,
                (x, v) => x.copyWith(opacity: v),
              ),
          ]),
          _card('maps', [
            _map(
              'Colour',
              key: 'colorMap',
              m.colorMap,
              (x, p) => x.copyWith(colorMap: p),
            ),
            _map(
              'Metal & rough',
              key: 'metalRoughMap',
              m.metalRoughMap,
              (x, p) => x.copyWith(metalRoughMap: p),
            ),
            _map(
              'Normal',
              key: 'normalMap',
              m.normalMap,
              (x, p) => x.copyWith(normalMap: p),
            ),
            if (m.normalMap.isNotEmpty)
              _slider(
                'Normal strength',
                key: 'normalScale',
                m.normalScale,
                2,
                (x, v) => x.copyWith(normalScale: v),
              ),
            _map(
              'Occlusion',
              key: 'occlusionMap',
              m.occlusionMap,
              (x, p) => x.copyWith(occlusionMap: p),
            ),
            if (m.occlusionMap.isNotEmpty)
              _slider(
                'Occlusion strength',
                key: 'occlusionStrength',
                m.occlusionStrength,
                1,
                (x, v) => x.copyWith(occlusionStrength: v),
              ),
            _map(
              'Glow',
              key: 'emissionMap',
              m.emissionMap,
              (x, p) => x.copyWith(emissionMap: p),
            ),
          ]),
        ] else
          _card('layers', [
            for (var i = 0; i < MaterialFile.maxLayers; i++)
              _layer(i, i < m.layers.length ? m.layers[i] : ''),
          ]),
        _card('layout', [
          _row(
            key: 'uv',
            'How',
            EditorSegmented<MaterialUv>(
              value: m.uv,
              options: const [
                (MaterialUv.natural, 'Mesh'),
                (MaterialUv.metres, 'Metres'),
                (MaterialUv.world, 'World'),
              ],
              tooltips: const {
                MaterialUv.natural: "As the mesh's own coordinates say",
                MaterialUv.metres:
                    'Repeated per metre along the mesh, at any size',
                MaterialUv.world:
                    'Projected from the world: no seams between pieces side '
                    'by side',
              },
              onChanged: (v) => change((x) => x.copyWith(uv: v)),
            ),
          ),
          _number(
            m.uv == MaterialUv.natural ? 'Repeat across' : 'Repeat per m',
            key: 'tiling',
            m.tilingX,
            (x, v) => x.copyWith(tilingX: v),
            positive: true,
          ),
          _number(
            m.uv == MaterialUv.natural ? 'Repeat down' : 'Repeat per m (down)',
            key: 'tiling',
            m.tilingY,
            (x, v) => x.copyWith(tilingY: v),
            positive: true,
          ),
          _number(
            'Shift across',
            key: 'offset',
            m.offsetX,
            (x, v) => x.copyWith(offsetX: v),
          ),
          _number(
            'Shift down',
            key: 'offset',
            m.offsetY,
            (x, v) => x.copyWith(offsetY: v),
          ),
          _slider(
            'Turn',
            key: 'rotation',
            m.rotation,
            180,
            (x, v) => x.copyWith(rotation: v),
            min: -180,
            step: 1,
            decimals: 0,
            unit: '°',
          ),
        ]),
        for (final problem in problems)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              problem,
              style: TextStyle(color: EditorTheme.warning, fontSize: 11),
            ),
          ),
        WorkspaceSections(view: _extensionView),
        const SizedBox(height: 16),
      ],
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

  Widget _previewPane() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _toolbar(),
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(child: _view()),
            Positioned(left: 10, right: 10, bottom: 8, child: _chips()),
          ],
        ),
      ),
    ],
  );

  Widget _toolbar() {
    final hasScene = sceneLighting != null;
    final left = <Widget>[
      for (final s in PreviewShape.values)
        EditorChip(
          label: s.label,
          icon: _shapeLooks[s]!.$1,
          tooltip: _shapeLooks[s]!.$2,
          selected: _shape == s,
          onTap: () => setShape(s),
        ),
    ];
    final right = <Widget>[
      EditorIconButton(
        icon: Icons.compare,
        tooltip: 'Compare with a plain grey material (C; hold Space)',
        isActive: _compareAt != null,
        onTap: () => setCompare(_compareAt == null ? 0.5 : null),
      ),
      const ToolSeparator(),
      SizedBox(
        width: 120,
        child: EditorDropdown<PreviewLighting>(
          value: _lighting,
          tooltip: 'The light the preview is drawn in',
          options: [
            for (final l in PreviewLighting.values)
              EditorDropdownOption(
                value: l,
                label: l.label,
                detail: l == PreviewLighting.scene && !hasScene
                    ? 'No 3-D scene open: studio light'
                    : null,
              ),
          ],
          onChanged: setLighting,
        ),
      ),
      const ToolSeparator(),
      // Its own size: in a wrap it would take the whole line.
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EditorSegmented<PreviewBackdrop>(
            value: _backdrop,
            options: [for (final b in PreviewBackdrop.values) (b, b.label)],
            tooltips: const {
              PreviewBackdrop.sky: "The light's own sky behind it (B)",
              PreviewBackdrop.dark: 'A dark background (B)',
              PreviewBackdrop.bright: 'A light background (B)',
            },
            onChanged: setBackdrop,
          ),
        ],
      ),
      const ToolSeparator(),
      ValueListenableBuilder<int>(
        valueListenable: _framing,
        builder: (context, _, _) => ZoomControls(
          label: Text('${(zoom * 100).round()}%', style: _label),
          onZoomOut: () => zoomBy(-1),
          onZoomIn: () => zoomBy(1),
          steps: [
            ZoomStep(
              'Fit',
              'Face it again, as it started (F; double-click)',
              selected: atStart,
              onTap: fit,
            ),
          ],
        ),
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

  // What the preview says: in chips over its foot.
  Widget _chips() => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      if (_holdingPlain)
        const PreviewChip('A plain grey in its place', icon: Icons.compare),
      if (_drawError case final error?)
        PreviewChip('$error', icon: Icons.warning_amber_rounded, warn: true),
      if (_lighting == PreviewLighting.scene && sceneLighting == null)
        const PreviewChip(
          'No 3-D scene open: studio light',
          icon: Icons.info_outline,
        ),
      const PreviewChip(
        'Drag to turn · scroll to zoom · double-click to face it again',
        icon: Icons.threed_rotation,
      ),
    ],
  );

  Widget _picture(ui.Image? image) => Center(
    child: image == null
        ? Text(_noGpu ? 'No GPU for a preview.' : 'Loading…', style: _label)
        : RawImage(image: image, fit: BoxFit.contain),
  );

  Widget _view() => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      // The surfaces are kept, and resized as they are drawn into: one
      // made for every size a dragged panel went through held GPU memory
      // until the card was full.
      if (size != _size && size.width > 0 && size.height > 0) {
        _size = size;
        _resized?.cancel();
        if (_image == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _redraw());
        } else {
          // While a panel is dragged the picture is scaled to fit, and
          // drawn again once its size stops changing: each size drawn at
          // took fresh textures.
          _resized = Timer(resizeSettle, _redraw);
        }
      }
      final split = _holdingPlain ? 1.0 : _compareAt;
      return Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) return;
          _zoomTo(_zoom * math.pow(0.999, event.scrollDelta.dy));
        },
        child: GestureDetector(
          onPanUpdate: (d) {
            _yaw += d.delta.dx * 0.01;
            _pitch = (_pitch - d.delta.dy * 0.01).clamp(-1.5, 1.5);
            _turned();
          },
          onDoubleTap: fit,
          child: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<int>(
                  valueListenable: _pictures,
                  builder: (context, _, _) {
                    final plain = _plainImage;
                    return ColoredBox(
                      color: const Color(0xFF15181D),
                      child: split == null || plain == null
                          ? _picture(_image)
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRect(
                                  clipper: _Side(split, left: true),
                                  child: _picture(plain),
                                ),
                                if (split < 1)
                                  ClipRect(
                                    clipper: _Side(split, left: false),
                                    child: _picture(_image),
                                  ),
                              ],
                            ),
                    );
                  },
                ),
              ),
              if (_compareAt case final at? when !_holdingPlain) ...[
                Positioned(
                  left: at * size.width - 12,
                  top: 0,
                  bottom: 0,
                  width: 24,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) => setCompare(
                        (at * size.width + d.delta.dx) / size.width,
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
                  right: size.width * (1 - at) + 10,
                  child: const PreviewChip('Plain', icon: Icons.chevron_left),
                ),
                Positioned(
                  top: 8,
                  left: at * size.width + 10,
                  child: const PreviewChip('With', icon: Icons.chevron_right),
                ),
              ],
              ...workspaceOverlays(_extensionView, size),
            ],
          ),
        ),
      );
    },
  );

  /// [argb] as `#RRGGBB`, or `#RRGGBBAA` when not opaque.
  static String hexOf(int argb) {
    String two(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return '#${two(r)}${two(g)}${two(b)}${a == 0xFF ? '' : two(a)}';
  }

  /// `#RRGGBB` or `#RRGGBBAA` (the `#` optional) as ARGB; null for
  /// anything else.
  static int? argbOfHex(String text) {
    var t = text.trim();
    if (t.startsWith('#')) t = t.substring(1);
    if (t.length != 6 && t.length != 8) return null;
    final v = int.tryParse(t, radix: 16);
    if (v == null) return null;
    return t.length == 6 ? 0xFF000000 | v : ((v & 0xFF) << 24) | (v >> 8);
  }
}

// What modules adding to the window see of it.
final class _Material3DView implements Material3DWorkspaceView {
  _Material3DView(this._state);

  final MaterialWorkspaceState _state;
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
  String get workspaceId => WorkspaceIds.material;

  @override
  String? get path => _state.widget.path;

  @override
  EditorScope get scope => _state.widget.workspace.scope;

  @override
  Listenable get changes => _changes;

  @override
  MaterialFile get material => _state.material;

  @override
  MaterialFile get shown => _state.drawn;

  @override
  void change(MaterialFile Function(MaterialFile m) change) =>
      _state.change(change);

  @override
  void preview(MaterialFile Function(MaterialFile m) change) =>
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
