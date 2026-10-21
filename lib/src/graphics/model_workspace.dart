import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';

import 'model_cooking.dart';
import 'model_thumbnails.dart';

/// A model's import settings and materials, with a live preview: the
/// workspace a model file opens in.
///
/// Its edits have an undo of their own; Save writes the settings beside
/// the model (`<model>.import.json`) and cooks it, and the game shows the
/// cooked model at once.
class ModelWorkspace extends StatefulWidget {
  /// The workspace for the model at [path].
  const ModelWorkspace({
    super.key,
    required this.path,
    required this.cooking,
    required this.thumbnails,
    required this.workspace,
    this.onCooked,
    this.loadOnStart = true,
  });

  /// Whether it reads the model as it opens; a test calls
  /// [ModelWorkspaceState.load] itself instead.
  final bool loadOnStart;

  /// The model, project-relative.
  final String path;

  /// Where settings are read and saved, and models cooked.
  final ModelCooking cooking;

  /// Shares its renderer for the preview.
  final ModelThumbnails thumbnails;

  /// The editor's handle on the workspace.
  final WorkspaceContext workspace;

  /// Told after a cook, with the path.
  final void Function(String path)? onCooked;

  @override
  State<ModelWorkspace> createState() => ModelWorkspaceState();
}

/// The state of a [ModelWorkspace]; public for tests.
class ModelWorkspaceState extends State<ModelWorkspace> {
  late ModelImportSettings _saved = widget.cooking.settingsOf(widget.path);
  late final List<ModelImportSettings> _history = [_saved];
  int _at = 0;

  /// The settings being edited.
  ModelImportSettings get settings => _history[_at];

  /// Whether the model has been read (its materials are listed).
  bool get loaded => _data != null || _error != null;

  /// Whether they differ from what is saved.
  bool get dirty =>
      settings.toJson().toString() != _saved.toJson().toString() ||
      !widget.cooking.hasSettings(widget.path);

  ModelData? _data;
  GpuModel? _gpu;
  Renderer3D? _renderer;
  GpuSurface? _surface;
  ui.Image? _image;
  Object? _error;
  String _status = '';
  bool _rendering = false, _again = false;
  double _yaw = -0.6, _pitch = -0.35;
  Size _size = const Size(400, 300);

  @override
  void initState() {
    super.initState();
    widget.workspace.setCloseGuard?.call(
      () async => mayLeaveUnsaved(context, dirty: dirty, save: save),
    );
    _status = widget.cooking.isCooked(widget.path)
        ? (widget.cooking.isStale(widget.path)
              ? 'Cooked, but the file or settings changed since.'
              : 'Cooked.')
        : 'Not cooked: the game loads the file as it is.';
    if (widget.loadOnStart) load();
  }

  /// Reads the model and draws the first preview.
  Future<void> load() async {
    try {
      final file = File('${widget.cooking.root}/${widget.path}');
      final folder = file.parent.path;
      final data = await loadModelData(
        await file.readAsBytes(),
        name: widget.path,
        fetch: (uri) => File('$folder/$uri').readAsBytes(),
      );
      if (!mounted) return;
      setState(() => _data = data);
      final renderer = await widget.thumbnails.renderer();
      if (renderer == null || !mounted) return;
      _renderer = renderer;
      _gpu = await renderer.uploader.upload(data);
      _redraw();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// Changes the settings as one undo step.
  void edit(ModelImportSettings next) {
    setState(() {
      _history
        ..removeRange(_at + 1, _history.length)
        ..add(next);
      _at = _history.length - 1;
    });
    _redraw();
  }

  /// Steps back through the edits.
  void undo() {
    if (_at == 0) return;
    setState(() => _at--);
    _redraw();
  }

  /// Steps forward again.
  void redo() {
    if (_at >= _history.length - 1) return;
    setState(() => _at++);
    _redraw();
  }

  /// Saves the settings and cooks the model; whether it went through.
  Future<bool> save() async {
    final current = settings;
    try {
      await widget.cooking.saveSettings(widget.path, current);
      setState(() => _status = 'Cooking…');
      final result = await widget.cooking.cook(widget.path);
      _saved = current;
      widget.onCooked?.call(widget.path);
      widget.workspace.reloadAssets?.call(
        ModelImportSettings.cookedOf(widget.path),
      );
      if (mounted) {
        final mb = (result.textureBytes / (1024 * 1024)).toStringAsFixed(1);
        setState(() {
          _status = [
            'Cooked: $mb MB of textures.',
            ...result.warnings,
          ].join('\n');
        });
      }
      return true;
    } on Object catch (error) {
      if (mounted) setState(() => _status = 'Could not cook: $error');
      return false;
    }
  }

  // Materials as the settings change them, the textures kept.
  Future<void> _redraw() async {
    if (_rendering) {
      _again = true;
      return;
    }
    final renderer = _renderer, gpu = _gpu, data = _data;
    if (renderer == null || gpu == null || data == null) return;
    _rendering = true;
    try {
      do {
        _again = false;
        final values = [
          for (var i = 0; i < data.materials.length; i++)
            settings.materials[ModelImportSettings.materialKey(data, i)]
                    ?.applyTo(data.materials[i]) ??
                data.materials[i],
        ];
        final w = math.max(16, _size.width.round()),
            h = math.max(16, _size.height.round());
        final scene = RenderScene()
          ..addModel(gpu.withMaterialValues(values), Matrix4.identity());
        final view = _view(data, w, h);
        final surface = _surface ??= renderer.device.createSurface(w, h);
        if (surface.width != w || surface.height != h) surface.resize(w, h);
        if (await renderer.render(scene, view, surface)) {
          final image = surface.image;
          if (!mounted) {
            image?.dispose();
            return;
          }
          setState(() {
            _image?.dispose();
            _image = image;
          });
        }
      } while (_again && mounted);
    } finally {
      _rendering = false;
    }
  }

  RenderView _view(ModelData data, int w, int h) {
    final box = Aabb3();
    data.bounds.transformInto(gltfToEngine, box);
    if (box.isEmpty) box.setValues(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5);
    final centre = Vector3.zero();
    box.centerInto(centre);
    final radius = math.max(0.05, box.min.distanceTo(box.max) / 2);
    const fov = math.pi / 4;
    final distance = radius / math.sin(fov / 2) * 1.1;
    final forward = Vector3(
      math.cos(_pitch) * math.sin(_yaw),
      -math.sin(_pitch),
      math.cos(_pitch) * math.cos(_yaw),
    );
    final view = RenderView()
      ..width = w
      ..height = h;
    view.lookAt(centre - forward * distance, centre);
    view.projection.setPerspectiveYDown(
      fov,
      w / h,
      math.max(0.01, distance - radius * 2),
      distance + radius * 2,
    );
    return view;
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = EditorKeys.primaryPressed;
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
              icon: Icons.view_in_ar,
              title: 'Model',
              file: name,
              dirty: dirty,
              onSave: save,
              onUndo: _at > 0 ? undo : null,
              onRedo: _at < _history.length - 1 ? redo : null,
              fullScreen: widget.workspace.fullScreen,
              onToggleFullScreen: widget.workspace.onToggleFullScreen,
              onClose: widget.workspace.onClose,
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 300, child: _settingsPanel()),
                  const VerticalDivider(width: 1),
                  Expanded(child: _preview()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle get _label => TextStyle(color: EditorTheme.textMuted, fontSize: 11);

  Widget _row(String label, Widget field) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 92, child: Text(label, style: _label)),
        Expanded(child: field),
      ],
    ),
  );

  Widget _settingsPanel() {
    final s = settings;
    final data = _data;
    return ListView(
      children: [
        const EditorSectionHeader('Import'),
        _row(
          'Scale',
          CommitTextField(
            key: ValueKey('scale:${s.scale}'),
            value: '${s.scale}',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            accept: (t) => (double.tryParse(t) ?? 0) > 0,
            onCommit: (t) => edit(s.copyWith(scale: double.parse(t))),
          ),
        ),
        _row(
          'Textures up to',
          EditorSegmented<int>(
            value: s.maxTextureSize,
            options: const [
              (512, '512'),
              (1024, '1K'),
              (2048, '2K'),
              (4096, '4K'),
              (0, 'Any'),
            ],
            onChanged: (v) => edit(s.copyWith(maxTextureSize: v)),
          ),
        ),
        _row(
          'Mipmaps',
          EditorToggle(
            value: s.mipmaps,
            label: 'Smaller levels',
            onChanged: (v) => edit(s.copyWith(mipmaps: v)),
          ),
        ),
        _row(
          'Compression',
          EditorSegmented<TextureCompression>(
            value: s.textureCompression,
            options: const [
              (TextureCompression.none, 'None'),
              (TextureCompression.etc2, 'ETC2'),
              (TextureCompression.astc, 'ASTC'),
            ],
            tooltips: const {
              TextureCompression.etc2: 'Not made yet: cooked uncompressed',
              TextureCompression.astc: 'Not made yet: cooked uncompressed',
            },
            onChanged: (v) => edit(s.copyWith(textureCompression: v)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Text(_status, style: _label),
        ),
        if (data != null) ...[
          const EditorSectionHeader('Materials'),
          for (var i = 0; i < data.materials.length; i++) _material(data, i),
          if (data.materials.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('No materials.', style: _label),
            ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Could not read it: $_error', style: _label),
          ),
      ],
    );
  }

  Widget _material(ModelData data, int index) {
    final key = ModelImportSettings.materialKey(data, index);
    final base = data.materials[index];
    final change = settings.materials[key] ?? const MaterialOverride();
    final shown = change.applyTo(base);
    void set(MaterialOverride next) {
      final materials = {...settings.materials};
      if (next.isEmpty) {
        materials.remove(key);
      } else {
        materials[key] = next;
      }
      edit(settings.copyWith(materials: materials));
    }

    MaterialOverride copy({
      Object? baseColor = _keep,
      Object? metallic = _keep,
      Object? roughness = _keep,
      Object? emissiveStrength = _keep,
      Object? doubleSided = _keep,
      Object? unlit = _keep,
    }) => MaterialOverride(
      baseColor: identical(baseColor, _keep)
          ? change.baseColor
          : baseColor as (double, double, double, double)?,
      metallic: identical(metallic, _keep)
          ? change.metallic
          : metallic as double?,
      roughness: identical(roughness, _keep)
          ? change.roughness
          : roughness as double?,
      emissive: change.emissive,
      emissiveStrength: identical(emissiveStrength, _keep)
          ? change.emissiveStrength
          : emissiveStrength as double?,
      doubleSided: identical(doubleSided, _keep)
          ? change.doubleSided
          : doubleSided as bool?,
      unlit: identical(unlit, _keep) ? change.unlit : unlit as bool?,
    );

    Widget slider(
      String label,
      double value,
      double max,
      void Function(double) commit,
    ) => _row(
      label,
      EditorSlider(
        value: value,
        min: 0,
        max: max,
        step: max / 100,
        decimals: 2,
        onChanged: (_) {},
        onChangeEnd: commit,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  key,
                  style: TextStyle(
                    color: EditorTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!change.isEmpty)
                EditorButton(
                  label: 'Reset',
                  onPressed: () => set(const MaterialOverride()),
                ),
            ],
          ),
        ),
        _row(
          'Colour',
          CommitTextField(
            key: ValueKey('colour:$key:${shown.baseColor}'),
            value: srgbHexOf(shown.baseColor),
            accept: (t) => linearOfHex(t) != null,
            onCommit: (t) => set(copy(baseColor: linearOfHex(t))),
          ),
        ),
        slider('Metallic', shown.metallic, 1, (v) => set(copy(metallic: v))),
        slider('Roughness', shown.roughness, 1, (v) => set(copy(roughness: v))),
        slider(
          'Glow',
          shown.emissiveStrength,
          20,
          (v) => set(copy(emissiveStrength: v)),
        ),
        _row(
          'Two-sided',
          EditorToggle(
            value: shown.doubleSided,
            label: 'Both faces',
            onChanged: (v) => set(copy(doubleSided: v)),
          ),
        ),
        _row(
          'Unlit',
          EditorToggle(
            value: shown.unlit,
            label: 'Ignore lights',
            onChanged: (v) => set(copy(unlit: v)),
          ),
        ),
      ],
    );
  }

  Widget _preview() {
    final data = _data;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth,
          math.max(1, constraints.maxHeight - 28),
        );
        if (size != _size) {
          _size = size;
          WidgetsBinding.instance.addPostFrameCallback((_) => _redraw());
        }
        return Column(
          children: [
            Expanded(
              child: GestureDetector(
                onPanUpdate: (d) {
                  _yaw += d.delta.dx * 0.01;
                  _pitch = (_pitch - d.delta.dy * 0.01).clamp(-1.5, 1.5);
                  _redraw();
                },
                child: ColoredBox(
                  color: const Color(0xFF15181D),
                  child: Center(
                    child: _image == null
                        ? Text(
                            _renderer == null && _data != null
                                ? 'No GPU for a preview.'
                                : 'Loading…',
                            style: _label,
                          )
                        : RawImage(image: _image, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 28,
              child: Center(
                child: Text(
                  data == null ? '' : describe(data, settings.scale),
                  style: _label,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// A line about [data] imported at [scale]: its size, meshes, triangles
  /// and animations.
  static String describe(ModelData data, double scale) {
    final box = Aabb3();
    data.bounds.transformInto(gltfToEngine, box);
    final size = Vector3.zero();
    if (!box.isEmpty) box.sizeInto(size);
    var triangles = 0;
    for (final mesh in data.meshes) {
      for (final p in mesh.primitives) {
        triangles += p.indices.length ~/ 3;
      }
    }
    String m(double v) => (v * scale).toStringAsFixed(2);
    return '${m(size.x)} × ${m(size.y)} × ${m(size.z)} m · ${data.meshes.length} meshes · $triangles triangles'
        '${data.animations.isEmpty ? '' : ' · ${data.animations.length} animations'}';
  }

  /// [linear] RGBA as `#RRGGBBAA` in sRGB.
  static String srgbHexOf((double, double, double, double) linear) {
    String c(double v, {bool alpha = false}) {
      final x = v.clamp(0.0, 1.0);
      final e = alpha
          ? x
          : (x <= 0.0031308 ? x * 12.92 : 1.055 * math.pow(x, 1 / 2.4) - 0.055);
      return (e * 255 + 0.5)
          .floor()
          .clamp(0, 255)
          .toRadixString(16)
          .padLeft(2, '0')
          .toUpperCase();
    }

    return '#${c(linear.$1)}${c(linear.$2)}${c(linear.$3)}${c(linear.$4, alpha: true)}';
  }

  /// The linear RGBA of `#RRGGBB` or `#RRGGBBAA` (sRGB), or null.
  static (double, double, double, double)? linearOfHex(String text) {
    final t = text.trim().replaceFirst('#', '');
    if (t.length != 6 && t.length != 8) return null;
    final v = int.tryParse(t, radix: 16);
    if (v == null) return null;
    final bytes = t.length == 6
        ? [(v >> 16) & 255, (v >> 8) & 255, v & 255, 255]
        : [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];
    double lin(int b) {
      final c = b / 255;
      return c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return (lin(bytes[0]), lin(bytes[1]), lin(bytes[2]), bytes[3] / 255);
  }
}

const Object _keep = Object();
