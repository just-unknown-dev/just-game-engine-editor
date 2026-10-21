import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';
import 'tileset_session.dart';

/// How to cut an image into tiles.
class TilesetCut {
  const TilesetCut({
    required this.image,
    required this.name,
    required this.tileWidth,
    required this.tileHeight,
    this.margin = 0,
    this.spacing = 0,
    this.imageWidth,
    this.imageHeight,
  });

  final String image;
  final String name;
  final int tileWidth;
  final int tileHeight;
  final int margin;
  final int spacing;

  /// The image's size, when the form has it already: the tileset is cut
  /// without loading the image again just to measure it.
  final int? imageWidth;
  final int? imageHeight;
}

/// Every `.png` under [root]/assets, project-relative — the images a
/// tileset could be cut from — then those installed packages ship
/// (`packages/<name>/…`). Sprite Studio's `.original.png` backups are left
/// out.
List<String> findImages(String root) {
  final dir = Directory('$root/assets');
  final out = <String>[];
  if (dir.existsSync()) {
    try {
      for (final f in dir.listSync(recursive: true)) {
        if (f is! File) continue;
        final p = f.path.replaceAll(r'\', '/');
        final lower = p.toLowerCase();
        if (!lower.endsWith('.png') || lower.endsWith('.original.png')) {
          continue;
        }
        out.add(p.startsWith('$root/') ? p.substring(root.length + 1) : p);
      }
    } on FileSystemException {
      out.clear();
    }
  }
  out.sort();
  return out..addAll([
    for (final p in PackageAssetPaths.of(
      root,
    ).packageFiles(endings: const ['.png']))
      if (!p.toLowerCase().endsWith('.original.png')) p,
  ]);
}

/// The file name of [path] without its folder or `.png`.
String imageBaseName(String path) {
  var name = path.substring(path.lastIndexOf('/') + 1);
  if (name.toLowerCase().endsWith('.png')) {
    name = name.substring(0, name.length - 4);
  }
  return name;
}

/// Picks an image and says how to cut it into tiles, showing the cut as it
/// is set up. What the Tileset Editor shows when it opens on an image, or
/// on nothing.
class CreateTilesetForm extends StatefulWidget {
  const CreateTilesetForm({
    super.key,
    required this.root,
    required this.onCreate,
    this.image,
    this.loadImage,
    this.onCancel,
    this.disposesImages,
  });

  /// The project folder.
  final String root;

  /// The image to cut, project-relative; null to choose one.
  final String? image;

  final TilesetImageLoader? loadImage;

  /// Whether the images [loadImage] hands back are the form's to dispose;
  /// by default only when it loads from the bundle itself.
  final bool? disposesImages;

  final ValueChanged<TilesetCut> onCreate;
  final VoidCallback? onCancel;

  @override
  State<CreateTilesetForm> createState() => _CreateTilesetFormState();
}

class _CreateTilesetFormState extends State<CreateTilesetForm> {
  String? _image;
  ui.Image? _picture;
  String? _error;
  String _name = '';
  int _tileWidth = 32;
  int _tileHeight = 32;
  int _margin = 0;
  int _spacing = 0;

  /// The images to choose from: listed once, not on every change to the
  /// form (the whole of `assets/` is walked).
  late final List<String> _images = widget.image == null
      ? findImages(widget.root)
      : const <String>[];

  bool get _ownsImages => widget.disposesImages ?? widget.loadImage == null;

  @override
  void initState() {
    super.initState();
    if (widget.image != null) _choose(widget.image!);
  }

  @override
  void dispose() {
    _letGo(_picture);
    super.dispose();
  }

  void _letGo(ui.Image? picture) {
    if (_ownsImages) picture?.dispose();
  }

  Future<void> _choose(String image) async {
    final previous = _picture;
    setState(() {
      _image = image;
      _picture = null;
      _error = null;
      _name = imageBaseName(image);
    });
    _letGo(previous);
    try {
      final picture =
          await (widget.loadImage ?? BundleSpriteAssetLoader().loadImage)(
            image,
          );
      if (!mounted || _image != image) {
        _letGo(picture);
        return;
      }
      setState(() {
        _picture = picture;
        // Small pictures are usually small tiles.
        final guess = picture.width <= 128 && picture.height <= 128 ? 16 : 32;
        _tileWidth = guess;
        _tileHeight = guess;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load $image: $e');
    }
  }

  int get _columns => _picture == null
      ? 0
      : TilesetData.gridCount(_picture!.width, _tileWidth, _margin, _spacing);
  int get _rows => _picture == null
      ? 0
      : TilesetData.gridCount(_picture!.height, _tileHeight, _margin, _spacing);

  @override
  Widget build(BuildContext context) {
    final images = _images;
    final ready = _picture != null && _columns > 0 && _rows > 0;
    return Material(
      color: EditorTheme.panelBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 300,
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Text(
                  'New tileset',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: EditorTheme.textBright,
                  ),
                ),
                const SizedBox(height: 10),
                if (widget.image == null)
                  DropdownEditorRow(
                    label: 'Image',
                    value: _image ?? '',
                    options: images,
                    searchable: true,
                    onChanged: _choose,
                  )
                else
                  ReadonlyRow(label: 'Image', value: widget.image!),
                if (images.isEmpty && widget.image == null)
                  Text(
                    'No .png files under assets/ yet.',
                    style: TextStyle(
                      fontSize: 10,
                      color: EditorTheme.textMuted,
                    ),
                  ),
                TextEditorRow(
                  label: 'Name',
                  initialValue: _name,
                  key: ValueKey(('name', _image)),
                  onSubmitted: (v) => setState(() => _name = v.trim()),
                ),
                for (final (label, value, set, min) in [
                  ('Tile W', _tileWidth, (int v) => _tileWidth = v, 1),
                  ('Tile H', _tileHeight, (int v) => _tileHeight = v, 1),
                  ('Margin', _margin, (int v) => _margin = v, 0),
                  ('Spacing', _spacing, (int v) => _spacing = v, 0),
                ])
                  _IntRow(
                    key: ValueKey(('cut', label, _image)),
                    label: label,
                    value: value,
                    onChanged: (v) => setState(() => set(v < min ? min : v)),
                  ),
                const SizedBox(height: 8),
                Text(
                  _picture == null
                      ? (_error ??
                            (_image == null ? 'Choose an image.' : 'Loading…'))
                      : '${_picture!.width} × ${_picture!.height} px: '
                            '$_columns × $_rows = ${_columns * _rows} tiles',
                  style: TextStyle(
                    fontSize: 11,
                    color: EditorTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (widget.onCancel != null)
                      TextButton(
                        onPressed: widget.onCancel,
                        child: const Text('Cancel'),
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed: ready
                          ? () => widget.onCreate(
                              TilesetCut(
                                image: _image!,
                                name: _name.isEmpty
                                    ? imageBaseName(_image!)
                                    : _name,
                                tileWidth: _tileWidth,
                                tileHeight: _tileHeight,
                                margin: _margin,
                                spacing: _spacing,
                                imageWidth: _picture!.width,
                                imageHeight: _picture!.height,
                              ),
                            )
                          : null,
                      child: const Text('Create'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: EditorTheme.border),
          Expanded(
            child: _picture == null
                ? const SizedBox.shrink()
                : InteractiveViewer(
                    constrained: false,
                    minScale: 0.25,
                    maxScale: 8,
                    child: CustomPaint(
                      size: Size(
                        _picture!.width.toDouble() * 2,
                        _picture!.height.toDouble() * 2,
                      ),
                      painter: _CutPainter(
                        picture: _picture!,
                        tileWidth: _tileWidth,
                        tileHeight: _tileHeight,
                        margin: _margin,
                        spacing: _spacing,
                        columns: _columns,
                        rows: _rows,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _IntRow extends StatelessWidget {
  const _IntRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: EditorTheme.textSecondary),
          ),
        ),
        Expanded(
          child: MiniNumberField(
            value: value.toDouble(),
            fractionDigits: 0,
            // `Infinity` reads as a number but is no size.
            onSubmitted: (v) {
              if (v.isFinite) onChanged(v.round());
            },
          ),
        ),
      ],
    ),
  );
}

class _CutPainter extends CustomPainter {
  _CutPainter({
    required this.picture,
    required this.tileWidth,
    required this.tileHeight,
    required this.margin,
    required this.spacing,
    required this.columns,
    required this.rows,
  });

  final ui.Image picture;
  final int tileWidth;
  final int tileHeight;
  final int margin;
  final int spacing;
  final int columns;
  final int rows;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(2);
    canvas.drawImage(
      picture,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.none,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0
      ..color = const Color(0xAA4FC3F7);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        canvas.drawRect(
          Rect.fromLTWH(
            (margin + c * (tileWidth + spacing)).toDouble(),
            (margin + r * (tileHeight + spacing)).toDouble(),
            tileWidth.toDouble(),
            tileHeight.toDouble(),
          ),
          line,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CutPainter old) => true;
}
