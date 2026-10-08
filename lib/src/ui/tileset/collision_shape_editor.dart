import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../core/constants/editor_constants.dart';
import 'tileset_session.dart';

/// A tile's collision: which kind, a ready-made shape, or shapes drawn by
/// hand.
///
/// Presets and the kind apply to every selected tile; the drawing canvas
/// edits the one tile selected. Concave outlines are fine — they are cut
/// into convex pieces when the bodies are built.
class CollisionEditor extends StatelessWidget {
  const CollisionEditor({super.key, required this.session});

  final TilesetSession session;

  @override
  Widget build(BuildContext context) {
    final ts = session.data;
    final id = session.primary;
    if (id == null) return const SizedBox.shrink();
    final collision = ts.tile(id)?.collision;
    final w = ts.tileWidth;
    final h = ts.tileHeight;
    final preset = TileCollisionPreset.of(collision, w, h);
    final kinds = session.collisionKinds.all;
    final kind = collision?.kind ?? MapCollisionKinds.solid.id;
    final single = session.selection.value.length == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(width: 60, child: Text('Kind', style: _label)),
            Expanded(
              child: PopupMenuButton<String>(
                tooltip: 'What the tile\'s shapes do',
                enabled: collision != null,
                color: EditorTheme.menuBg,
                onSelected: session.setCollisionKind,
                itemBuilder: (context) => [
                  for (final k in kinds)
                    PopupMenuItem(
                      value: k.id,
                      height: 28,
                      child: Row(
                        children: [
                          _Swatch(color: Color(k.color)),
                          const SizedBox(width: 6),
                          Text(k.label, style: _value),
                        ],
                      ),
                    ),
                  // A kind the tileset names but this game has not
                  // registered still shows, so it is not silently lost.
                  if (!kinds.any((k) => k.id == kind))
                    PopupMenuItem(
                      value: kind,
                      height: 28,
                      child: Text('$kind (unknown here)', style: _value),
                    ),
                ],
                child: Row(
                  children: [
                    _Swatch(
                      color: Color(session.collisionKinds.resolve(kind).color),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      collision == null
                          ? '—'
                          : session.collisionKinds.byId(kind)?.label ?? kind,
                      style: _value,
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: EditorTheme.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final p in TileCollisionPreset.values)
              _PresetChip(
                preset: p,
                tileSize: Size(w.toDouble(), h.toDouble()),
                isOn: p == preset,
                onTap: () => session.setCollision(p.shapesFor(w, h)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (single)
          ShapeCanvas(
            key: ValueKey(('shapes', id)),
            session: session,
            tileId: id,
          )
        else
          Text(
            'Select one tile to draw its shapes by hand.',
            style: TextStyle(fontSize: 10, color: EditorTheme.textMuted),
          ),
      ],
    );
  }
}

TextStyle get _label => TextStyle(
  fontSize: 11,
  color: EditorTheme.textSecondary,
);
TextStyle get _value => TextStyle(
  fontSize: 11,
  color: EditorTheme.textPrimary,
);

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// A preset, drawn as the shape it makes.
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.preset,
    required this.tileSize,
    required this.isOn,
    required this.onTap,
  });

  final TileCollisionPreset preset;
  final Size tileSize;
  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: preset.label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        width: 30,
        height: 30,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isOn ? EditorTheme.selectionBg : EditorTheme.surfaceDark,
          border: Border.all(
            color: isOn ? EditorTheme.primaryBright : EditorTheme.border,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: CustomPaint(
          painter: _PresetPainter(
            preset.shapesFor(tileSize.width, tileSize.height),
            tileSize,
          ),
        ),
      ),
    ),
  );
}

class _PresetPainter extends CustomPainter {
  _PresetPainter(this.shapes, this.tile);

  final List<TileShape>? shapes;
  final Size tile;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = EditorTheme.textMuted.withValues(alpha: 0.5),
    );
    final list = shapes;
    if (list == null) {
      canvas.drawLine(
        Offset(0, size.height),
        Offset(size.width, 0),
        Paint()..color = EditorTheme.textMuted,
      );
      return;
    }
    final sx = size.width / tile.width;
    final sy = size.height / tile.height;
    for (final shape in list) {
      final pts = shape.outline();
      final path = Path()..moveTo(pts.first.dx * sx, pts.first.dy * sy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx * sx, p.dy * sy);
      }
      canvas.drawPath(path..close(), Paint()..color = const Color(0xFF4FC3F7));
    }
  }

  @override
  bool shouldRepaint(_PresetPainter old) => true;
}

/// One tile, large, with its shapes to drag about.
///
/// Drag a corner to move it; Ctrl+click an edge to add a corner there;
/// Alt+click a corner to take it away. Corners land on whole pixels, or on
/// eighths of the tile with Shift held.
class ShapeCanvas extends StatefulWidget {
  const ShapeCanvas({super.key, required this.session, required this.tileId});

  final TilesetSession session;
  final int tileId;

  /// How big the tile is drawn.
  static const double extent = 220;

  /// Room around the tile, so a corner on its edge can be grabbed from
  /// either side.
  static const double pad = 10;

  @override
  State<ShapeCanvas> createState() => _ShapeCanvasState();
}

class _ShapeCanvasState extends State<ShapeCanvas> {
  /// The shape and corner being dragged.
  (int, int)? _drag;
  int _dragStamp = 0;

  /// The shape last touched, for Delete and the buttons.
  int? _shape;

  TilesetSession get s => widget.session;
  TilesetData get ts => s.data;

  List<TileShape> get _shapes =>
      ts.tile(widget.tileId)?.collision?.shapes ?? const [];

  double get _scale =>
      ShapeCanvas.extent / math.max(ts.tileWidth, ts.tileHeight);

  Offset _toTile(Offset local) =>
      (local - const Offset(ShapeCanvas.pad, ShapeCanvas.pad)) / _scale;

  Offset _snap(Offset p) {
    final w = ts.tileWidth.toDouble();
    final h = ts.tileHeight.toDouble();
    final Offset snapped;
    if (HardwareKeyboard.instance.isShiftPressed) {
      snapped = Offset(
        (p.dx / (w / 8)).round() * (w / 8),
        (p.dy / (h / 8)).round() * (h / 8),
      );
    } else {
      snapped = Offset(p.dx.roundToDouble(), p.dy.roundToDouble());
    }
    return Offset(snapped.dx.clamp(0, w), snapped.dy.clamp(0, h));
  }

  /// The corners of [shape] that can be dragged.
  static List<Offset> handles(TileShape shape) => switch (shape) {
    TilePolygonShape(:final points) => points,
    TileRectShape(:final rect) => [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ],
    TileEllipseShape(:final bounds) => [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ],
  };

  /// [shape] with corner [i] moved to [to].
  static TileShape moved(TileShape shape, int i, Offset to) {
    switch (shape) {
      case TilePolygonShape(:final points):
        return TilePolygonShape([...points]..[i] = to);
      case TileRectShape(:final rect):
        return TileRectShape(_dragCorner(rect, i, to));
      case TileEllipseShape(:final bounds):
        return TileEllipseShape(_dragCorner(bounds, i, to));
    }
  }

  static Rect _dragCorner(Rect r, int i, Offset to) {
    final opposite = [r.bottomRight, r.bottomLeft, r.topLeft, r.topRight][i];
    return Rect.fromPoints(opposite, to);
  }

  (int, int)? _handleAt(Offset tilePoint) {
    final reach = 7 / _scale;
    final shapes = _shapes;
    for (var si = shapes.length - 1; si >= 0; si--) {
      final hs = handles(shapes[si]);
      for (var i = 0; i < hs.length; i++) {
        if ((hs[i] - tilePoint).distance <= reach) return (si, i);
      }
    }
    return null;
  }

  /// The polygon edge nearest [p], within reach: shape, and the corner the
  /// edge starts at.
  (int, int)? _edgeAt(Offset p) {
    final reach = 6 / _scale;
    final shapes = _shapes;
    for (var si = 0; si < shapes.length; si++) {
      final shape = shapes[si];
      if (shape is! TilePolygonShape) continue;
      final pts = shape.points;
      for (var i = 0; i < pts.length; i++) {
        final a = pts[i];
        final b = pts[(i + 1) % pts.length];
        if (_distanceToSegment(p, a, b) <= reach) return (si, i);
      }
    }
    return null;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }

  void _write(List<TileShape> shapes, {Object? mergeKey}) =>
      s.setShapes(widget.tileId, shapes, mergeKey: mergeKey);

  void _down(PointerDownEvent e) {
    final p = _toTile(e.localPosition);
    final keys = HardwareKeyboard.instance;
    final handle = _handleAt(p);
    if (keys.isAltPressed) {
      if (handle == null) return;
      final shape = _shapes[handle.$1];
      if (shape is TilePolygonShape && shape.points.length > 3) {
        _write([
          for (var i = 0; i < _shapes.length; i++)
            i == handle.$1
                ? TilePolygonShape([...shape.points]..removeAt(handle.$2))
                : _shapes[i],
        ]);
      } else {
        s.say('A shape needs three corners at least');
      }
      return;
    }
    if (keys.isControlPressed) {
      final edge = _edgeAt(p);
      if (edge == null) return;
      final shape = _shapes[edge.$1] as TilePolygonShape;
      _write([
        for (var i = 0; i < _shapes.length; i++)
          i == edge.$1
              ? TilePolygonShape(
                  [...shape.points]..insert(edge.$2 + 1, _snap(p)),
                )
              : _shapes[i],
      ]);
      setState(() => _shape = edge.$1);
      return;
    }
    if (handle != null) {
      setState(() {
        _drag = handle;
        _shape = handle.$1;
        _dragStamp++;
      });
      return;
    }
    // Inside a shape: select it.
    final shapes = _shapes;
    for (var si = shapes.length - 1; si >= 0; si--) {
      final path = Path()..addPolygon(shapes[si].outline(), true);
      if (path.contains(p)) {
        setState(() => _shape = si);
        return;
      }
    }
    setState(() => _shape = null);
  }

  void _move(PointerMoveEvent e) {
    final drag = _drag;
    if (drag == null) return;
    final to = _snap(_toTile(e.localPosition));
    final shapes = _shapes;
    if (drag.$1 >= shapes.length) return;
    _write(
      [
        for (var i = 0; i < shapes.length; i++)
          i == drag.$1 ? moved(shapes[i], drag.$2, to) : shapes[i],
      ],
      mergeKey: ('corner', widget.tileId, _dragStamp),
    );
  }

  void _addPolygon() {
    final w = ts.tileWidth.toDouble();
    final h = ts.tileHeight.toDouble();
    _write([
      ..._shapes,
      TilePolygonShape([
        Offset(w * 0.25, h * 0.75),
        Offset(w * 0.5, h * 0.25),
        Offset(w * 0.75, h * 0.75),
      ]),
    ]);
    setState(() => _shape = _shapes.length - 1);
  }

  void _removeShape() {
    final i = _shape;
    if (i == null || i >= _shapes.length) return;
    _write([..._shapes]..removeAt(i));
    setState(() => _shape = null);
  }

  void _toPolygon() {
    final i = _shape;
    if (i == null || i >= _shapes.length) return;
    final shape = _shapes[i];
    if (shape is TilePolygonShape) return;
    _write([..._shapes]..[i] = TilePolygonShape(shape.outline(segments: 8)));
  }

  @override
  Widget build(BuildContext context) {
    final w = ts.tileWidth * _scale;
    final h = ts.tileHeight * _scale;
    final collision = ts.tile(widget.tileId)?.collision;
    final color = Color(
      s.collisionKinds.resolve(collision?.kind ?? 'solid').color,
    );
    final selected = _shape != null && _shape! < _shapes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Listener(
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: (_) => setState(() => _drag = null),
            child: CustomPaint(
              size: Size(w + 2 * ShapeCanvas.pad, h + 2 * ShapeCanvas.pad),
              painter: _ShapePainter(
                image: s.image.value,
                source: ts.sourceRect(widget.tileId),
                shapes: _shapes,
                scale: _scale,
                color: color,
                selected: _shape,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          children: [
            _TextButton(label: 'Add shape', onTap: _addPolygon),
            _TextButton(
              label: 'To polygon',
              onTap: selected && _shapes[_shape!] is! TilePolygonShape
                  ? _toPolygon
                  : null,
            ),
            _TextButton(label: 'Remove', onTap: selected ? _removeShape : null),
          ],
        ),
        Text(
          'Drag a corner · Ctrl+click an edge adds one · Alt+click removes '
          'one · Shift snaps to eighths',
          style: TextStyle(fontSize: 10, color: EditorTheme.textMuted),
        ),
      ],
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 26),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(label, style: const TextStyle(fontSize: 11)),
  );
}

class _ShapePainter extends CustomPainter {
  _ShapePainter({
    required this.image,
    required this.source,
    required this.shapes,
    required this.scale,
    required this.color,
    required this.selected,
  });

  final ui.Image? image;
  final Rect source;
  final List<TileShape> shapes;
  final double scale;
  final Color color;
  final int? selected;

  @override
  void paint(Canvas canvas, Size outer) {
    const pad = ShapeCanvas.pad;
    final size = Size(outer.width - 2 * pad, outer.height - 2 * pad);
    canvas
      ..save()
      ..translate(pad, pad);
    // A checkerboard, so transparent pixels read as transparent.
    const cell = 8.0;
    final dark = Paint()..color = const Color(0xFF2A2A2E);
    final light = Paint()..color = const Color(0xFF34343A);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final even = ((x / cell).floor() + (y / cell).floor()).isEven;
        canvas.drawRect(
          Rect.fromLTWH(
            x,
            y,
            math.min(cell, size.width - x),
            math.min(cell, size.height - y),
          ),
          even ? dark : light,
        );
      }
    }
    final img = image;
    if (img != null) {
      canvas.drawImageRect(
        img,
        source,
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    final pixel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0
      ..color = const Color(0x14FFFFFF);
    for (var x = 0.0; x <= size.width; x += scale) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pixel);
    }
    for (var y = 0.0; y <= size.height; y += scale) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pixel);
    }
    for (var i = 0; i < shapes.length; i++) {
      final pts = [for (final p in shapes[i].outline()) p * scale];
      final path = Path()..addPolygon(pts, true);
      canvas
        ..drawPath(
          path,
          Paint()..color = color.withValues(alpha: i == selected ? 0.4 : 0.25),
        )
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = i == selected ? 2 : 1.5
            ..color = color,
        );
      for (final h in _ShapeCanvasState.handles(shapes[i])) {
        canvas
          ..drawCircle(h * scale, 4.5, Paint()..color = Colors.white)
          ..drawCircle(h * scale, 3, Paint()..color = color);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShapePainter old) => true;
}
