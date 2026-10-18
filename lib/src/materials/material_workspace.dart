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

/// A material file's look (`*.material.json`), with a live preview to turn:
/// the workspace a material opens in.
///
/// Its fields are in sections — Surface, Transparency, Maps (each with a
/// picture of its image), Layers, and how the maps are laid out — with
/// presets to start from. A slider being dragged or a colour being picked
/// shows in the preview at once and becomes one undo step when let go.
/// The preview shows the material on a ball, a cube, a cylinder, a ring or
/// a floor tile, in a studio, a sky's light or the open scene's own.
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
  GpuSurface? _surface;
  bool _rendering = false, _again = false, _noGpu = false;
  Object? _drawError;
  // A little way back, so the whole shape shows with room round it.
  static const double _startZoom = 0.85;
  double _yaw = -0.6, _pitch = -0.45, _zoom = _startZoom;
  Size _size = const Size(360, 360);
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
  void preview(MaterialFile Function(MaterialFile m) change) {
    setState(() => _live = change(shown));
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
        ui.Image? image;
        Object? problem;
        try {
          image = await widget.pictures.render(
            drawn,
            width: w,
            height: h,
            yaw: _yaw,
            pitch: _pitch,
            zoom: _zoom,
            shape: _shape,
            lighting: _lighting,
            scene: sceneLighting,
            into: surface,
          );
        } on Object catch (error) {
          // A map or layer that can't be read: say so, keep the last
          // picture.
          problem = error;
        }
        if (!mounted) {
          image?.dispose();
          return;
        }
        setState(() {
          _drawError = problem;
          if (image != null) {
            _image?.dispose();
            _image = image;
          }
        });
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
    _extensionView.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (!ctrl) return KeyEventResult.ignored;
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
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 340, child: _fields()),
                  const VerticalDivider(width: 1),
                  Expanded(child: _previewPane()),
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
      onChanged: (v) => preview((m) => set(m, v)),
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
        if (!layered) ...[
          const EditorSectionHeader('Surface'),
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
          const EditorSectionHeader('Transparency'),
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
          const EditorSectionHeader('Maps'),
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
        ] else ...[
          EditorSectionHeader(
            'Layers',
            trailing: material.isVariant ? _inherit('layers') : null,
          ),
          _note(
            "Blended by a mesh's vertex red, green, blue and alpha; each "
            "layer's colour map, tiled per metre as that layer says.",
          ),
          for (var i = 0; i < MaterialFile.maxLayers; i++)
            _layer(i, i < m.layers.length ? m.layers[i] : ''),
        ],
        const EditorSectionHeader('Laid out'),
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
                  'Projected from the world: no seams between pieces side by '
                  'side',
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

  Widget _previewPane() {
    final hasScene = sceneLighting != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: EditorSegmented<PreviewShape>(
                  value: _shape,
                  options: [for (final s in PreviewShape.values) (s, s.label)],
                  onChanged: setShape,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
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
              WorkspaceToolButtons(view: _extensionView),
            ],
          ),
        ),
        Expanded(child: _view()),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: Text(
            [
              'Drag to turn · scroll to zoom · double-click to face it again',
              if (_drawError != null) '$_drawError',
            ].join('\n'),
            style: _drawError == null
                ? _label
                : TextStyle(color: EditorTheme.warning, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _view() => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      if (size != _size && size.width > 0 && size.height > 0) {
        _size = size;
        _surface = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => _redraw());
      }
      return Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) return;
          final next = (_zoom * math.pow(0.999, event.scrollDelta.dy))
              .clamp(0.5, 3.0)
              .toDouble();
          if (next == _zoom) return;
          _zoom = next;
          _redraw();
        },
        child: GestureDetector(
          onPanUpdate: (d) {
            _yaw += d.delta.dx * 0.01;
            _pitch = (_pitch - d.delta.dy * 0.01).clamp(-1.5, 1.5);
            _redraw();
          },
          onDoubleTap: () {
            _yaw = -0.6;
            _pitch = -0.45;
            _zoom = _startZoom;
            _redraw();
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xFF15181D),
                  child: Center(
                    child: _image == null
                        ? Text(
                            _noGpu ? 'No GPU for a preview.' : 'Loading…',
                            style: _label,
                          )
                        : RawImage(image: _image, fit: BoxFit.contain),
                  ),
                ),
              ),
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
